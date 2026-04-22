import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/service_constants.dart';
import '../models/weather_route_request.dart';
import '../models/weather_route_result.dart';
import 'route_planner_auth_service.dart';

/// Lifecycle of a compute job. Mirrors the server's JobStatus vocabulary
/// (`routes.py` + `jobs.py`) plus a local `idle` state for "no job in flight".
enum WeatherRoutingStatus {
  idle,
  submitting,
  queued,
  running,
  done,
  cancelled,
  error,
}

/// Colour-coded log line — mirrors the web UI's `#modalLog` styling where
/// `error` lines render red and `done` lines render bold green.
class WeatherRoutingLogLine {
  WeatherRoutingLogLine(this.text, this.kind);
  final String text;
  final WeatherRoutingLogKind kind;
}

enum WeatherRoutingLogKind { log, error, done, status }

/// Submits, tracks, and streams a weather-routing compute job.
///
/// Exposed as a `ChangeNotifier` so panel tabs / the chart overlay can
/// rebuild off a single source of truth. The service survives the modal
/// sheet being dismissed, meaning the user can navigate away from the
/// chart and come back to a still-streaming job. Pattern modelled on
/// [WeatherApiService] — `_isLoading` / `_errorMessage` + `notifyListeners`.
class WeatherRoutingService extends ChangeNotifier {
  WeatherRoutingService(this._auth);

  final RoutePlannerAuthService _auth;

  // ===== Configuration (set per-submission from tool config) =====
  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    notifyListeners();
  }

  // ===== Planned endpoints (user-placed pins on the chart) =====
  //
  // Shared state for the chart's drag-markers, the long-press handler,
  // and the compose panel. Null = not yet placed; the compose tab
  // falls back to the vessel's current position for start at submit
  // time so an unconfigured pin doesn't block the happy path.
  LatLon? _plannedStart;
  LatLon? _plannedEnd;
  LatLon? get plannedStart => _plannedStart;
  LatLon? get plannedEnd => _plannedEnd;

  set plannedStart(LatLon? v) {
    if (_isSamePoint(_plannedStart, v)) return;
    _plannedStart = v;
    notifyListeners();
  }

  set plannedEnd(LatLon? v) {
    if (_isSamePoint(_plannedEnd, v)) return;
    _plannedEnd = v;
    notifyListeners();
  }

  void clearPlannedPins() {
    if (_plannedStart == null && _plannedEnd == null) return;
    _plannedStart = null;
    _plannedEnd = null;
    notifyListeners();
  }

  static bool _isSamePoint(LatLon? a, LatLon? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.lat == b.lat && a.lon == b.lon;
  }

  // ===== Live job state =====
  WeatherRoutingStatus _status = WeatherRoutingStatus.idle;
  WeatherRoutingStatus get status => _status;

  String? _currentJobId;
  String? get currentJobId => _currentJobId;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<WeatherRoutingLogLine> _logLines = [];
  List<WeatherRoutingLogLine> get logLines =>
      List.unmodifiable(_logLines);

  WeatherRouteResult? _currentResult;
  WeatherRouteResult? get currentResult => _currentResult;

  WeatherRouteRequest? _lastRequest;
  WeatherRouteRequest? get lastRequest => _lastRequest;

  DateTime? _submittedAt;
  DateTime? get submittedAt => _submittedAt;

  // ===== Internal =====
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  String? _lastEventId;

  bool get isBusy =>
      _status == WeatherRoutingStatus.submitting ||
      _status == WeatherRoutingStatus.queued ||
      _status == WeatherRoutingStatus.running;

  /// Submit a new route compute job. Cancels any in-flight job first.
  ///
  /// The auth token must already be configured on [RoutePlannerAuthService]
  /// — on a missing token the call fails fast with [_errorMessage] set so
  /// the UI can prompt "Sign in first".
  Future<void> submitRoute(WeatherRouteRequest request) async {
    await _teardownSse();

    if (!_auth.hasToken) {
      _errorMessage = 'Sign in or paste a bearer token first.';
      _status = WeatherRoutingStatus.error;
      notifyListeners();
      return;
    }

    _status = WeatherRoutingStatus.submitting;
    _errorMessage = null;
    _logLines.clear();
    _currentResult = null;
    _currentJobId = null;
    _lastEventId = null;
    _lastRequest = request;
    _submittedAt = DateTime.now();
    notifyListeners();

    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes');
      final resp = await http
          .post(
            uri,
            headers: _auth.authorisedHeaders(
              extra: const {'Content-Type': 'application/json'},
            ),
            body: jsonEncode(request.toJson()),
          )
          .timeout(ServiceConstants.longHttpTimeout);

      if (resp.statusCode != 202) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'Submit failed: HTTP ${resp.statusCode} '
            '${_shortBody(resp.body)}';
        notifyListeners();
        return;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      _currentJobId = body['job_id'] as String?;
      _status = _parseStatus(body['status'] as String?) ??
          WeatherRoutingStatus.queued;
      notifyListeners();

      if (_currentJobId == null) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'Server returned no job_id.';
        notifyListeners();
        return;
      }

      _appendLog('Submitted job ${_currentJobId!}.', WeatherRoutingLogKind.status);
      unawaited(_listenToEvents(_currentJobId!));
    } on TimeoutException {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'Request timed out contacting $_baseUrl';
      notifyListeners();
    } catch (e) {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'Submit error: $e';
      notifyListeners();
    }
  }

  Future<void> cancelJob() async {
    final id = _currentJobId;
    if (id == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$id/cancel');
      await http
          .post(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
    } catch (_) {
      // Best-effort cancel; server may have already finished.
    }
    _appendLog('Cancellation requested.', WeatherRoutingLogKind.status);
    await _teardownSse();
    if (_status != WeatherRoutingStatus.done) {
      _status = WeatherRoutingStatus.cancelled;
    }
    notifyListeners();
  }

  /// Clear the current result + logs. Does not touch the remote job.
  void clearResult() {
    _currentResult = null;
    _logLines.clear();
    _currentJobId = null;
    _status = WeatherRoutingStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> deleteRemoteJob() async {
    final id = _currentJobId;
    if (id == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$id');
      await http
          .delete(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
    } catch (_) {
      // Best-effort delete.
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _sseClient?.close();
    super.dispose();
  }

  // ---------- SSE ----------

  /// Stream `/api/v1/routes/{id}/events`. Parses `event:` / `data:` / `id:`
  /// frames separated by blank lines (RFC EventSource format). Server adds a
  /// 1000-frame ring buffer so `Last-Event-ID` header lets us reconnect
  /// without missing frames.
  Future<void> _listenToEvents(String jobId) async {
    await _teardownSse();
    final client = http.Client();
    _sseClient = client;

    final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId/events');
    final req = http.Request('GET', uri);
    req.headers.addAll(_auth.authorisedHeaders(
      extra: const {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
    ));
    if (_lastEventId != null) {
      req.headers['Last-Event-ID'] = _lastEventId!;
    }

    try {
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'SSE failed: HTTP ${resp.statusCode}';
        notifyListeners();
        await _teardownSse();
        return;
      }

      final stream = resp.stream.transform(utf8.decoder);
      String buffer = '';
      _sseSub = stream.listen(
        (chunk) {
          buffer += chunk;
          // Frames are separated by a blank line. Support both \n\n and
          // \r\n\r\n to be robust to server formatting.
          final pattern = RegExp(r'\r?\n\r?\n');
          while (true) {
            final match = pattern.firstMatch(buffer);
            if (match == null) break;
            final frame = buffer.substring(0, match.start);
            buffer = buffer.substring(match.end);
            _handleFrame(frame);
          }
        },
        onError: (e) {
          if (kDebugMode) {
            debugPrint('SSE stream error: $e');
          }
          // Silently swallow: if the connection dropped before `done`,
          // the UI still shows the last known status. A future
          // enhancement could auto-reconnect via _lastEventId here.
        },
        onDone: () {
          // Server closed the stream — terminal event already handled
          // in _handleFrame, nothing else to do.
        },
        cancelOnError: true,
      );
    } catch (e) {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'SSE connect error: $e';
      notifyListeners();
      await _teardownSse();
    }
  }

  void _handleFrame(String frame) {
    String? event;
    final dataLines = <String>[];
    String? id;
    for (final raw in frame.split('\n')) {
      if (raw.isEmpty) continue;
      if (raw.startsWith(':')) continue; // comment
      final colon = raw.indexOf(':');
      if (colon < 0) continue;
      final field = raw.substring(0, colon);
      var value = raw.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
        case 'id':
          id = value;
          break;
      }
    }
    if (id != null && id.isNotEmpty) _lastEventId = id;
    if (event == null && dataLines.isEmpty) return;

    final data = dataLines.join('\n');
    switch (event) {
      case 'status':
        _handleStatusEvent(data);
        break;
      case 'log':
        _handleLogEvent(data);
        break;
      case 'route':
        _handleRouteEvent(data);
        break;
      case 'done':
        _handleDoneEvent(data);
        break;
      case 'error':
        _handleErrorEvent(data);
        break;
      default:
        // Unknown event — surface as a log line for visibility.
        _appendLog('[$event] $data', WeatherRoutingLogKind.log);
    }
  }

  void _handleStatusEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final s = _parseStatus(m['status'] as String?);
      if (s != null) {
        _status = s;
        _appendLog('Status: ${m['status']}', WeatherRoutingLogKind.status);
        notifyListeners();
      }
    } catch (_) {
      _appendLog('status: $data', WeatherRoutingLogKind.status);
    }
  }

  void _handleLogEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final line = (m['line'] as String?) ?? data;
      _appendLog(line, WeatherRoutingLogKind.log);
    } catch (_) {
      _appendLog(data, WeatherRoutingLogKind.log);
    }
  }

  void _handleRouteEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      _currentResult = WeatherRouteResult.fromGeoJson(m);
      notifyListeners();
    } catch (e) {
      _appendLog('Failed to parse route: $e', WeatherRoutingLogKind.error);
    }
  }

  void _handleDoneEvent(String data) {
    _status = WeatherRoutingStatus.done;
    _appendLog('Done.', WeatherRoutingLogKind.done);
    // Some deployments send `route` as part of the `done` payload rather
    // than a separate frame. Parse defensively.
    if (_currentResult == null) {
      try {
        final m = jsonDecode(data) as Map<String, dynamic>;
        final gj = m['geojson'] ?? m['result'];
        if (gj is Map<String, dynamic>) {
          _currentResult = WeatherRouteResult.fromGeoJson(gj);
        }
      } catch (_) {/* result already null — fetch via /result below */}
    }
    notifyListeners();
    // Fall back to a direct /result fetch if no route came through SSE.
    if (_currentResult == null && _currentJobId != null) {
      unawaited(_fetchResultFallback(_currentJobId!));
    }
    _teardownSse();
  }

  void _handleErrorEvent(String data) {
    _status = WeatherRoutingStatus.error;
    String message = data;
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      message = (m['message'] as String?) ?? data;
    } catch (_) {/* leave as raw */}
    _errorMessage = message;
    _appendLog(message, WeatherRoutingLogKind.error);
    notifyListeners();
    _teardownSse();
  }

  Future<void> _fetchResultFallback(String jobId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId/result');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        _currentResult = WeatherRouteResult.fromGeoJson(m);
        notifyListeners();
      } else {
        _appendLog('Fetch /result failed: HTTP ${resp.statusCode}',
            WeatherRoutingLogKind.error);
      }
    } catch (e) {
      _appendLog('Fetch /result error: $e', WeatherRoutingLogKind.error);
    }
  }

  Future<void> _teardownSse() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  void _appendLog(String text, WeatherRoutingLogKind kind) {
    _logLines.add(WeatherRoutingLogLine(text, kind));
    // Cap log history to avoid unbounded memory growth for long jobs.
    const maxLines = 2000;
    if (_logLines.length > maxLines) {
      _logLines.removeRange(0, _logLines.length - maxLines);
    }
    notifyListeners();
  }

  static WeatherRoutingStatus? _parseStatus(String? s) {
    switch (s) {
      case 'queued':
        return WeatherRoutingStatus.queued;
      case 'running':
        return WeatherRoutingStatus.running;
      case 'done':
        return WeatherRoutingStatus.done;
      case 'cancelled':
        return WeatherRoutingStatus.cancelled;
      case 'error':
        return WeatherRoutingStatus.error;
      default:
        return null;
    }
  }

  static String _shortBody(String body) {
    if (body.length <= 200) return body;
    return '${body.substring(0, 200)}…';
  }
}
