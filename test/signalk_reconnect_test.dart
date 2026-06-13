import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zed_display/services/signalk_service.dart';

/// Minimal in-memory [WebSocketSink]. `close()` can be made to hang to
/// exercise the `_reconnectLight` close-timeout path.
class _FakeSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  final bool hangClose;
  final _doneCompleter = Completer<void>();
  bool closed = false;

  _FakeSink(this._controller, {this.hangClose = false});

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future get done => _doneCompleter.future;

  @override
  Future close([int? closeCode, String? closeReason]) {
    if (hangClose) {
      // Never completes — simulates a half-open socket whose close handshake
      // hangs (the production `.timeout(wsCloseTimeout)` must rescue us).
      return Completer<void>().future;
    }
    closed = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    if (!_controller.isClosed) _controller.close();
    return Future.value();
  }
}

/// Controllable [WebSocketChannel] for tests. The test pushes data, errors, or
/// onDone through [fireData] / [fireError] / [fireDone].
class _FakeChannel implements WebSocketChannel {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  late final _FakeSink _sink;

  _FakeChannel({bool hangClose = false}) {
    _sink = _FakeSink(_controller, hangClose: hangClose);
  }

  // The StreamChannel helper methods (cast/pipe/transform/…) are never exercised
  // by these tests; fall through rather than implement each.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void fireData(dynamic data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  void fireError(Object error) {
    if (!_controller.isClosed) _controller.addError(error);
  }

  void fireDone() {
    if (!_controller.isClosed) _controller.close();
  }

  @override
  Stream get stream => _controller.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

void main() {
  late SignalKService service;
  late int factoryCalls;
  late List<_FakeChannel> produced;

  /// Install a factory that hands out fresh fake channels. [delay] lets a test
  /// hold the swap mid-flight to probe coalescing.
  void installFactory({Completer<void>? gate, bool hangClose = false}) {
    factoryCalls = 0;
    produced = [];
    service.channelFactory = (url, headers) async {
      factoryCalls++;
      if (gate != null) await gate.future;
      final ch = _FakeChannel(hangClose: hangClose);
      produced.add(ch);
      return ch;
    };
  }

  setUp(() {
    service = SignalKService();
  });

  tearDown(() {
    // Cancel every timer the swap machinery may have armed (liveness, backoff,
    // background probe, cache cleanup) so the test ends with nothing pending.
    service.debugStopAllTimers();
  });

  test('stale onDone from a superseded socket is IGNORED (regression: '
      'connected-but-no-data after sleep)', () async {
    installFactory();

    // gen 1 — original socket, listener still live.
    final c1 = _FakeChannel();
    service.debugSeedConnected(c1);
    expect(service.debugSocketGeneration, 1);

    // gen 2 — a swap attaches a new listener WITHOUT cancelling c1's (this is
    // exactly the orphaned-socket condition a racing second swap produces).
    final c2 = _FakeChannel();
    service.debugSeedConnected(c2);
    expect(service.debugSocketGeneration, 2);
    expect(service.debugChannel, same(c2));

    // The orphaned gen-1 socket finally fires onDone.
    c1.fireDone();
    await Future.delayed(Duration.zero);

    // The live socket must be untouched, and recovery must NOT have been kicked.
    expect(service.isConnected, isTrue, reason: 'gen-1 onDone clobbered live socket');
    expect(service.debugChannel, same(c2));
    expect(service.reconnectAttempt, 0);
    expect(
      service.connectionLog.any((l) => l.contains('onDone gen=1 ignored')),
      isTrue,
      reason: 'expected the stale event to be logged as ignored',
    );
  });

  test('overlapping _reconnectLight calls coalesce onto one swap', () async {
    final gate = Completer<void>();
    final c1 = _FakeChannel();
    service.debugSeedConnected(c1);
    installFactory(gate: gate);

    // Two concurrent swaps; the second must ride the first's in-flight future.
    final f1 = service.debugReconnectLight();
    final f2 = service.debugReconnectLight();
    gate.complete();
    await Future.wait([f1, f2]);

    expect(factoryCalls, 1, reason: 'concurrent swaps should not each open a socket');
    expect(produced.length, 1);
    expect(service.debugChannel, same(produced.single));
    expect(service.isConnected, isTrue);
  });

  test('hanging sink.close() does not strand or corrupt the swap', () async {
    // The OLD socket's close() hangs; the new socket must still come up.
    final c1 = _FakeChannel(hangClose: true);
    service.debugSeedConnected(c1);
    installFactory();

    await service.debugReconnectLight(); // close times out (~2s) then proceeds

    expect(service.isConnected, isTrue);
    expect(service.debugChannel, same(produced.single));
    expect(service.debugSocketGeneration, 2);

    // A late onDone from the abandoned gen-1 socket is still ignored.
    c1.fireDone();
    await Future.delayed(Duration.zero);
    expect(service.isConnected, isTrue);
    expect(service.debugChannel, same(produced.single));
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('onError drives teardown + reconnect (parity with onDone)', () async {
    installFactory();
    final c1 = _FakeChannel();
    service.debugSeedConnected(c1);

    c1.fireError('boom');
    await Future.delayed(Duration.zero);

    // Old code only set isConnected=false and stopped. Now it must recover.
    expect(service.isConnected, isFalse);
    expect(service.debugHasChannel, isFalse);
    expect(service.connectionState, SignalKConnectionState.reconnecting);
    expect(service.reconnectAttempt, greaterThan(0));
  });

  test('quiet boat: watchdog does NOT swap a healthy-but-silent socket', () async {
    installFactory();
    final c1 = _FakeChannel();
    service.debugSeedConnected(c1);

    final threshold = service.debugLivenessStaleThreshold;

    // Silent for less than the threshold → must be left alone.
    service.debugLastMessageAt =
        DateTime.now().subtract(threshold - const Duration(seconds: 5));
    await service.debugCheckLiveness();
    expect(factoryCalls, 0, reason: 'a merely quiet socket must not be replaced');
    expect(service.debugChannel, same(c1));
    expect(service.debugSocketGeneration, 1);

    // Past the threshold → now it should replace the (assumed half-open) socket.
    service.debugLastMessageAt =
        DateTime.now().subtract(threshold + const Duration(seconds: 5));
    await service.debugCheckLiveness();
    expect(factoryCalls, 1);
    expect(service.debugSocketGeneration, 2);
  });
}
