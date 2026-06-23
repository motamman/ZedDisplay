import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// Singleton audio SINK for alarm sounds — DECLARATIVE, with exactly one
/// underlying [AudioPlayer] for the whole app lifetime.
///
/// All policy (which alert sounds, severity, mute, acknowledge) lives in
/// [AlertCoordinator], which expresses "what should be sounding" as a single
/// desired target via [setTarget]. The coordinator may call [setTarget] many
/// times in a burst (once per reconcile, i.e. once per alert during a load
/// storm); each call just rewrites the same desired target — it never starts a
/// new player.
///
/// A single converge loop drives the ONE reused player toward the desired
/// target (switch the looping source, or stop). Because only one [AudioPlayer]
/// ever exists and only one converge loop ever runs, a second `MediaPlayer`
/// cannot be created — pile-up and orphaned-looping-players are impossible by
/// construction, not by bolted-on guards. (That orphaning was the "DISMISS ALL
/// won't stop the audio" regression.)
class AlarmAudioPlayer {
  static final AlarmAudioPlayer _instance = AlarmAudioPlayer._();
  factory AlarmAudioPlayer() => _instance;
  AlarmAudioPlayer._();

  /// Shared sound asset map (key → file path).
  static const Map<String, String> alarmSounds = {
    'bell': 'sounds/alarm_bell.mp3',
    'foghorn': 'sounds/alarm_foghorn.mp3',
    'chimes': 'sounds/alarm_chimes.mp3',
    'ding': 'sounds/alarm_ding.mp3',
    'whistle': 'sounds/alarm_whistle.mp3',
    'dog': 'sounds/alarm_dog.mp3',
  };

  /// Display names for alarm sounds (key → human label).
  static const Map<String, String> alarmSoundNames = {
    'bell': 'Bell',
    'foghorn': 'Foghorn',
    'chimes': 'Chimes',
    'ding': 'Ding',
    'whistle': 'Whistle',
    'dog': 'Dog Bark',
  };

  /// The ONE player. Created lazily on first play, reused forever, only torn
  /// down in [dispose].
  AudioPlayer? _player;
  bool _configured = false;

  /// Desired target (what should be sounding), written synchronously by
  /// [setTarget]. Null key = silence.
  String? _desiredKey;
  String? _desiredAsset;

  /// What is actually playing right now (the converge loop's progress).
  String? _actualKey;

  /// Guards the single converge loop so plays/stops can never overlap.
  bool _converging = false;

  /// Bounded backoff for transient `play()` failures, so a one-off platform
  /// error doesn't silence a still-wanted alarm until a different target is set.
  int _playFailures = 0;
  static const int _maxPlayRetries = 3;
  static const Duration _playRetryBackoff = Duration(milliseconds: 400);

  /// The alert key currently sounding (null when silent).
  String? get currentKey => _actualKey;
  bool get isPlaying => _actualKey != null;

  /// Declare what should be sounding. SYNCHRONOUS and idempotent: records the
  /// desired target and kicks the converge loop if it isn't already running.
  /// Pass `key == null` to silence.
  void setTarget(String? key, [String? asset]) {
    _desiredKey = key;
    _desiredAsset = asset;
    _kick();
  }

  void _kick() {
    if (_converging) return;
    _converging = true;
    unawaited(_converge());
  }

  /// Drive the one player toward the desired target. Re-checks the target after
  /// every await (it may change mid-flight). Exactly one instance runs at a
  /// time; on exit it re-verifies and re-kicks if the target moved during the
  /// final step, so it can never stop one step short.
  Future<void> _converge() async {
    try {
      while (_actualKey != _desiredKey) {
        final wantKey = _desiredKey;
        final wantAsset = _desiredAsset;
        try {
          if (wantKey == null) {
            await _player?.stop();
          } else {
            final player = _player ??= AudioPlayer();
            if (!_configured) {
              await player.setReleaseMode(ReleaseMode.loop);
              await player.setVolume(1.0);
              _configured = true;
            }
            // play() on the reused player swaps the source and (re)starts the
            // loop — it never creates a new player.
            await player.play(AssetSource(wantAsset!));
          }
          _actualKey = wantKey;
          _playFailures = 0;
        } catch (e) {
          if (kDebugMode) {
            print('AlarmAudioPlayer: converge error: $e');
          }
          // Distinguish play-failure from stop-failure. A transient play() error
          // on a still-wanted alarm gets a bounded backoff-retry rather than
          // going silent until a different target is set (safety-critical audio).
          // Stop-failures (or a changed/exhausted target) mark the target reached
          // so a persistently-failing call can't hot-spin the loop.
          if (wantKey != null &&
              _desiredKey == wantKey &&
              _playFailures < _maxPlayRetries) {
            _playFailures++;
            await Future.delayed(_playRetryBackoff);
            // Leave _actualKey unchanged so the loop retries the same target.
          } else {
            _actualKey = wantKey;
            _playFailures = 0;
          }
        }
      }
    } finally {
      _converging = false;
    }
    // No awaits between the loop exit and here, so this check is atomic w.r.t.
    // setTarget: if the target moved during the final step we restart cleanly.
    if (_actualKey != _desiredKey) _kick();
  }

  void dispose() {
    try {
      _player?.stop();
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _configured = false;
    _desiredKey = null;
    _desiredAsset = null;
    _actualKey = null;
  }
}
