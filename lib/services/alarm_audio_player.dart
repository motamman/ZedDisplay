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
  Timer? _repeatTimer;
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
    Duration repeatInterval = const Duration(seconds: 5),
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
      await _player!.setVolume(1.0);
      await _player!.play(AssetSource(assetPath));
      _playing = true;

      _repeatTimer = Timer.periodic(repeatInterval, (_) async {
        if (!_playing || _muted) {
          _repeatTimer?.cancel();
          if (_muted) _stopInternal();
          return;
        }
        try {
          // Create fresh player per repeat — seek+resume is unreliable on Android
          _player?.dispose();
          _player = AudioPlayer();
          await _player!.setVolume(1.0);
          await _player!.play(AssetSource(assetPath));
        } catch (e) {
          if (kDebugMode) {
            print('AlarmAudioPlayer: error repeating sound: $e');
          }
        }
      });
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
    _repeatTimer?.cancel();
    _repeatTimer = null;
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
    _repeatTimer?.cancel();
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
