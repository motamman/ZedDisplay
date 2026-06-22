import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/alert_event.dart';

/// Singleton audio player for alarm sounds.
/// Prevents audio overlap with severity-based preemption.
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

  AudioPlayer? _player;
  bool _playing = false;
  bool _muted = false;
  String? _activeSource;
  AlertSeverity? _activeSeverity;

  String? get activeSource => _activeSource;
  AlertSeverity? get activeSeverity => _activeSeverity;
  bool get isPlaying => _playing;
  bool get isMuted => _muted;

  /// Mute all audio. Current playback stops, future play() calls are no-ops.
  void mute() {
    _muted = true;
    _stopInternal();
  }

  /// Unmute. Audio will play on next submitAlert with wantsAudio.
  void unmute() {
    _muted = false;
  }

  /// Play alarm. Higher-or-equal severity preempts current. Lower is no-op.
  Future<void> play({
    required String assetPath,
    required AlertSeverity severity,
    required String source,
  }) async {
    if (_muted) return;

    // If already playing, only preempt if new severity >= current
    if (_playing && _activeSeverity != null && severity < _activeSeverity!) {
      return;
    }

    // Stop current if playing
    await _stopInternal();

    _activeSource = source;
    _activeSeverity = severity;
    try {
      _player = AudioPlayer();
      // Loop natively instead of tearing down and rebuilding a MediaPlayer
      // every cycle. The old approach disposed + recreated the player every
      // `repeatInterval`, which spammed Android's cleanDrmObj/resetDrmState
      // logs and churned CPU. One player now, created here and disposed in
      // _stopInternal()/stop(). NOTE: the alarm is now continuous rather than
      // the previous ~5s-spaced repeat.
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(1.0);
      await _player!.play(AssetSource(assetPath));
      _playing = true;
    } catch (e) {
      if (kDebugMode) {
        print('AlarmAudioPlayer: error playing sound: $e');
      }
      _playing = false;
      _activeSource = null;
      _activeSeverity = null;

    }
  }

  /// Stop if started by [source]. Null = stop unconditionally.
  Future<void> stop({String? source}) async {
    if (source != null && _activeSource != source) return;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    try {
      await _player?.stop();
      _player?.dispose();
    } catch (e) {
      if (kDebugMode) {
        print('AlarmAudioPlayer: error stopping: $e');
      }
    }
    _player = null;
    _playing = false;
    _activeSource = null;
    _activeSeverity = null;
  }

  void dispose() {
    try {
      _player?.stop();
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _playing = false;
    _activeSource = null;
    _activeSeverity = null;
  }
}
