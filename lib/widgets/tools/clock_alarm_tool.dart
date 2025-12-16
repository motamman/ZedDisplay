import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_clock/one_clock.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../services/notification_service.dart';
import '../../utils/color_extensions.dart';

/// Clock face style options
enum ClockFaceStyle {
  analog,
  digital,
  minimal,
  nautical,
  modern,
}

/// Alarm sound options
enum AlarmSound {
  ding,
  foghorn,
  bell,
  whistle,
  chimes,
}

/// Alarm sound metadata
class AlarmSoundInfo {
  final String name;
  final String description;
  final IconData icon;
  final String assetPath; // Local asset path

  const AlarmSoundInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.assetPath,
  });
}

/// Available alarm sounds with local asset paths
const Map<AlarmSound, AlarmSoundInfo> alarmSounds = {
  AlarmSound.ding: AlarmSoundInfo(
    name: 'Ding',
    description: 'Standard alarm ding',
    icon: Icons.notifications_active,
    assetPath: 'assets/sounds/alarm_ding.mp3',
  ),
  AlarmSound.foghorn: AlarmSoundInfo(
    name: 'Fog Horn',
    description: 'Deep ship fog horn',
    icon: Icons.volume_up,
    assetPath: 'assets/sounds/alarm_foghorn.mp3',
  ),
  AlarmSound.bell: AlarmSoundInfo(
    name: 'Ship Bell',
    description: 'Nautical ship bell',
    icon: Icons.doorbell,
    assetPath: 'assets/sounds/alarm_bell.mp3',
  ),
  AlarmSound.whistle: AlarmSoundInfo(
    name: 'Whistle',
    description: 'Bosun whistle',
    icon: Icons.air,
    assetPath: 'assets/sounds/alarm_whistle.mp3',
  ),
  AlarmSound.chimes: AlarmSoundInfo(
    name: 'Chimes',
    description: 'Alert chimes',
    icon: Icons.campaign,
    assetPath: 'assets/sounds/alarm_chimes.mp3',
  ),
};

/// Alarm data model
class Alarm {
  final String id;
  String label;
  int hour;
  int minute;
  bool enabled;
  List<int> repeatDays; // 0=Sun, 1=Mon, etc. Empty = one-time
  bool snoozed;
  DateTime? snoozeUntil;
  AlarmSound sound;
  DateTime? lastDismissedAt; // For "dismiss for all" - shared via SignalK

  Alarm({
    required this.id,
    this.label = 'Alarm',
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.repeatDays = const [],
    this.snoozed = false,
    this.snoozeUntil,
    this.sound = AlarmSound.ding,
    this.lastDismissedAt,
  });

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as String? ?? const Uuid().v4(),
      label: json['label'] as String? ?? 'Alarm',
      hour: json['hour'] as int? ?? 0,
      minute: json['minute'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      repeatDays: (json['repeatDays'] as List?)?.cast<int>() ?? [],
      snoozed: json['snoozed'] as bool? ?? false,
      snoozeUntil: json['snoozeUntil'] != null
          ? DateTime.tryParse(json['snoozeUntil'] as String)
          : null,
      sound: AlarmSound.values.firstWhere(
        (s) => s.name == (json['sound'] as String?),
        orElse: () => AlarmSound.ding,
      ),
      lastDismissedAt: json['lastDismissedAt'] != null
          ? DateTime.tryParse(json['lastDismissedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'repeatDays': repeatDays,
    'snoozed': snoozed,
    'snoozeUntil': snoozeUntil?.toIso8601String(),
    'sound': sound.name,
    'lastDismissedAt': lastDismissedAt?.toIso8601String(),
  };

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool shouldTrigger(DateTime now) {
    if (!enabled) return false;
    if (snoozed && snoozeUntil != null && now.isBefore(snoozeUntil!)) return false;

    // Check if dismissed for all within the last 2 minutes
    if (lastDismissedAt != null) {
      final dismissedMinutesAgo = now.difference(lastDismissedAt!).inMinutes;
      if (dismissedMinutesAgo < 2) return false;
    }

    if (now.hour == hour && now.minute == minute) {
      if (repeatDays.isEmpty) return true;
      return repeatDays.contains(now.weekday % 7);
    }
    return false;
  }
}

/// Smart Clock with alarm functionality
class ClockAlarmTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ClockAlarmTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<ClockAlarmTool> createState() => _ClockAlarmToolState();
}

class _ClockAlarmToolState extends State<ClockAlarmTool> with TickerProviderStateMixin {
  // Custom resource type for isolation from other apps
  static const String _alarmResourceType = 'zeddisplay-alarms';

  DateTime _now = DateTime.now();
  Timer? _timer;
  Timer? _alarmSoundTimer;
  List<Alarm> _alarms = [];
  bool _loadingAlarms = false;
  Alarm? _activeAlarm;
  late AnimationController _pulseController;
  AudioPlayer? _alarmPlayer;

  ClockFaceStyle get _faceStyle {
    final styleStr = widget.config.style.customProperties?['faceStyle'] as String?;
    return ClockFaceStyle.values.firstWhere(
      (s) => s.name == styleStr,
      orElse: () => ClockFaceStyle.analog,
    );
  }

  Color get _primaryColor {
    return widget.config.style.primaryColor?.toColor(
      fallback: Colors.blue,
    ) ?? Colors.blue;
  }

  /// Get complementary (opposite) color for second hand
  Color get _secondHandColor {
    final hsl = HSLColor.fromColor(_primaryColor);
    // Rotate hue by 180 degrees to get complementary color
    final complementaryHue = (hsl.hue + 180) % 360;
    return HSLColor.fromAHSL(
      hsl.alpha,
      complementaryHue,
      hsl.saturation,
      hsl.lightness,
    ).toColor();
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _startClock();
    _ensureResourceTypeAndLoadAlarms();
  }

  Future<void> _ensureResourceTypeAndLoadAlarms() async {
    // Ensure custom resource type exists on server
    if (widget.signalKService.isConnected) {
      await widget.signalKService.ensureResourceTypeExists(
        _alarmResourceType,
        description: 'ZedDisplay shared alarms',
      );
    }
    await _loadAlarms();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopAlarmSound();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _playAlarmSound() async {
    if (_activeAlarm == null) return;

    final sound = _activeAlarm!.sound;
    final soundInfo = alarmSounds[sound]!;
    final assetPath = soundInfo.assetPath;

    if (kDebugMode) print('Playing alarm sound: ${soundInfo.name} from $assetPath');

    try {
      // Create new player with local asset
      _alarmPlayer = AudioPlayer();
      await _alarmPlayer!.setVolume(1.0);
      await _alarmPlayer!.play(AssetSource(assetPath.replaceFirst('assets/', '')));
      if (kDebugMode) print('Alarm sound started');

      // Set up timer to repeat the sound
      _alarmSoundTimer?.cancel();
      _alarmSoundTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        // Check if alarm is still active
        if (_activeAlarm == null) {
          _alarmSoundTimer?.cancel();
          return;
        }

        try {
          // Create a fresh player each time for reliability
          _alarmPlayer?.dispose();
          _alarmPlayer = AudioPlayer();
          await _alarmPlayer!.setVolume(1.0);
          await _alarmPlayer!.play(AssetSource(assetPath.replaceFirst('assets/', '')));
          if (kDebugMode) print('Alarm sound repeated');
        } catch (e) {
          if (kDebugMode) print('Error repeating alarm sound: $e');
        }
      });
    } catch (e, stack) {
      if (kDebugMode) {
        print('Error playing alarm sound: $e');
        print('Stack: $stack');
      }
    }
  }

  void _stopAlarmSound() {
    if (kDebugMode) print('Stopping alarm sound');
    _alarmSoundTimer?.cancel();
    _alarmSoundTimer = null;
    try {
      _alarmPlayer?.stop();
      _alarmPlayer?.dispose();
    } catch (e) {
      if (kDebugMode) print('Error stopping alarm player: $e');
    }
    _alarmPlayer = null;
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newNow = DateTime.now();

      // Check alarms on minute change
      if (newNow.minute != _now.minute) {
        _checkAlarms(newNow);
      }

      setState(() => _now = newNow);
    });
  }

  Future<void> _loadAlarms() async {
    if (_loadingAlarms) return;
    setState(() => _loadingAlarms = true);

    try {
      final resources = await widget.signalKService.getResources(_alarmResourceType);
      final alarms = <Alarm>[];

      for (final entry in resources.entries) {
        final resourceData = entry.value as Map<String, dynamic>;

        try {
          final description = resourceData['description'] as String?;
          if (description != null) {
            final alarmData = Map<String, dynamic>.from(
              Uri.splitQueryString(description).map((k, v) => MapEntry(k, _parseValue(v)))
            );
            alarmData['id'] = entry.key;
            alarms.add(Alarm.fromJson(alarmData));
          }
        } catch (e) {
          if (kDebugMode) print('Error parsing alarm: $e');
        }
      }

      if (mounted) {
        setState(() {
          _alarms = alarms;
          _loadingAlarms = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading alarms: $e');
      if (mounted) setState(() => _loadingAlarms = false);
    }
  }

  dynamic _parseValue(String value) {
    if (value == 'true') return true;
    if (value == 'false') return false;
    final intVal = int.tryParse(value);
    if (intVal != null) return intVal;
    if (value.startsWith('[') && value.endsWith(']')) {
      final inner = value.substring(1, value.length - 1);
      if (inner.isEmpty) return <int>[];
      return inner.split(',').map((s) => int.parse(s.trim())).toList();
    }
    return value;
  }

  Future<void> _saveAlarm(Alarm alarm) async {
    // Ensure resource type exists before saving
    await widget.signalKService.ensureResourceTypeExists(
      _alarmResourceType,
      description: 'ZedDisplay shared alarms',
    );

    final data = alarm.toJson();
    final description = data.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    final resourceData = {
      'name': 'Alarm: ${alarm.label} (${alarm.timeString})',
      'description': description,
      'position': {'latitude': 0.0, 'longitude': 0.0},
    };

    final success = await widget.signalKService.putResource(_alarmResourceType, alarm.id, resourceData);
    if (kDebugMode && !success) {
      print('Failed to save alarm ${alarm.id}');
    }
  }

  Future<void> _deleteAlarm(Alarm alarm) async {
    await widget.signalKService.deleteResource(_alarmResourceType, alarm.id);
    if (mounted) {
      setState(() => _alarms.removeWhere((a) => a.id == alarm.id));
    }
  }

  void _checkAlarms(DateTime now) {
    for (final alarm in _alarms) {
      if (alarm.shouldTrigger(now)) {
        _triggerAlarm(alarm);
        break;
      }
    }
  }

  Future<void> _triggerAlarm(Alarm alarm) async {
    setState(() => _activeAlarm = alarm);
    _pulseController.repeat(reverse: true);

    // Trigger haptic feedback immediately
    HapticFeedback.heavyImpact();

    // Show system notification immediately (don't await)
    NotificationService().showAlarmNotification(
      title: alarm.label,
      body: 'Alarm: ${alarm.timeString}',
      alarmId: alarm.id,
    ).catchError((e) {
      if (kDebugMode) print('Error showing alarm notification: $e');
    });

    // Play looping alarm sound (don't await - let it play in background)
    _playAlarmSound().catchError((e) {
      if (kDebugMode) print('Error playing alarm sound: $e');
    });
  }

  /// Dismiss alarm for this device only
  void _dismissAlarmLocal() {
    _stopAlarmSound();
    _pulseController.stop();
    _pulseController.reset();

    if (_activeAlarm != null) {
      final alarm = _activeAlarm!;
      // Cancel the notification
      NotificationService().cancelAlarmNotification(alarm.id);
      if (alarm.repeatDays.isEmpty) {
        alarm.enabled = false;
        _saveAlarm(alarm);
      }
      setState(() => _activeAlarm = null);
    }
  }

  /// Dismiss alarm for all devices (saves to SignalK)
  void _dismissAlarmForAll() {
    _stopAlarmSound();
    _pulseController.stop();
    _pulseController.reset();

    if (_activeAlarm != null) {
      final alarm = _activeAlarm!;
      // Cancel the notification
      NotificationService().cancelAlarmNotification(alarm.id);
      alarm.lastDismissedAt = DateTime.now();
      if (alarm.repeatDays.isEmpty) {
        alarm.enabled = false;
      }
      _saveAlarm(alarm);
      setState(() => _activeAlarm = null);
    }
  }

  void _snoozeAlarm() {
    if (_activeAlarm != null) {
      final alarm = _activeAlarm!;
      alarm.snoozed = true;
      alarm.snoozeUntil = DateTime.now().add(const Duration(minutes: 9));
      _saveAlarm(alarm);
    }
    _dismissAlarmLocal();
  }

  void _showAlarmEditor([Alarm? existingAlarm]) {
    final isNew = existingAlarm == null;
    final alarm = existingAlarm ?? Alarm(
      id: const Uuid().v4(),
      hour: TimeOfDay.now().hour,
      minute: (TimeOfDay.now().minute ~/ 5) * 5,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AlarmEditorSheet(
        alarm: alarm,
        isNew: isNew,
        primaryColor: _primaryColor,
        onSave: (savedAlarm) async {
          await _saveAlarm(savedAlarm);
          if (isNew) {
            setState(() => _alarms.add(savedAlarm));
          } else {
            setState(() {
              final idx = _alarms.indexWhere((a) => a.id == savedAlarm.id);
              if (idx >= 0) _alarms[idx] = savedAlarm;
            });
          }
        },
        onDelete: isNew ? null : () => _deleteAlarm(alarm),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show active alarm overlay
    if (_activeAlarm != null) {
      return _buildAlarmOverlay();
    }

    return GestureDetector(
      onLongPress: () => _showAlarmsPanel(),
      child: Stack(
        children: [
          _buildClockFace(),
          if (_alarms.any((a) => a.enabled))
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.alarm,
                color: _primaryColor.withAlpha(180),
                size: 16,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlarmOverlay() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.05);
        return Container(
          color: Colors.black.withAlpha(230),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm, size: 80, color: _primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    _activeAlarm!.label,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                  Text(
                    _activeAlarm!.timeString,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Snooze button
                  ElevatedButton.icon(
                    onPressed: _snoozeAlarm,
                    icon: const Icon(Icons.snooze),
                    label: const Text('Snooze 9m'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Dismiss buttons row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _dismissAlarmLocal,
                        icon: const Icon(Icons.volume_off),
                        label: const Text('Dismiss Here'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _dismissAlarmForAll,
                        icon: const Icon(Icons.alarm_off),
                        label: const Text('Dismiss All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClockFace() {
    switch (_faceStyle) {
      case ClockFaceStyle.digital:
        return _buildDigitalClock();
      case ClockFaceStyle.minimal:
        return _buildMinimalClock();
      case ClockFaceStyle.nautical:
        return _buildNauticalClock();
      case ClockFaceStyle.modern:
        return _buildModernClock();
      case ClockFaceStyle.analog:
        return _buildAnalogClock();
    }
  }

  Widget _buildAnalogClock() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return Center(
          child: AnalogClock(
            width: size * 0.9,
            height: size * 0.9,
            isLive: true,
            hourHandColor: _primaryColor,
            minuteHandColor: _primaryColor,
            secondHandColor: _secondHandColor,
            numberColor: _primaryColor,
            showNumbers: true,
            showSecondHand: true,
            showTicks: true,
            showAllNumbers: false,
            textScaleFactor: 1.2,
            decoration: BoxDecoration(
              border: Border.all(width: 2.0, color: _primaryColor),
              color: Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDigitalClock() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DigitalClock(
                isLive: true,
                showSeconds: true,
                digitalClockTextColor: _primaryColor,
                textScaleFactor: 1.5,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(_now),
                style: TextStyle(
                  fontSize: 16,
                  color: _primaryColor.withAlpha(180),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMinimalClock() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: DigitalClock(
            isLive: true,
            showSeconds: false,
            digitalClockTextColor: _primaryColor,
            textScaleFactor: 2.0,
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
          ),
        );
      },
    );
  }

  Widget _buildNauticalClock() {
    // Nautical style: numbers, thick markers, classic look
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return Center(
          child: AnalogClock(
            width: size * 0.9,
            height: size * 0.9,
            isLive: true,
            hourHandColor: _primaryColor,
            minuteHandColor: _primaryColor,
            secondHandColor: _secondHandColor,
            numberColor: _primaryColor,
            showNumbers: true,
            showSecondHand: true,
            showTicks: true,
            showAllNumbers: true, // Show all 12 numbers
            textScaleFactor: 1.0,
            decoration: BoxDecoration(
              border: Border.all(width: 4.0, color: _primaryColor),
              color: Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernClock() {
    // Modern style: minimal, no numbers, clean
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        return Center(
          child: AnalogClock(
            width: size * 0.9,
            height: size * 0.9,
            isLive: true,
            hourHandColor: _primaryColor,
            minuteHandColor: _primaryColor,
            secondHandColor: _secondHandColor,
            numberColor: _primaryColor,
            showNumbers: false, // No numbers for modern look
            showSecondHand: true,
            showTicks: true,
            showAllNumbers: false,
            textScaleFactor: 1.0,
            decoration: BoxDecoration(
              border: Border.all(width: 1.0, color: _primaryColor.withAlpha(100)),
              color: Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday % 7]}, ${months[dt.month - 1]} ${dt.day}';
  }

  void _showAlarmsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AlarmsPanelSheet(
        alarms: _alarms,
        primaryColor: _primaryColor,
        onAddAlarm: () {
          Navigator.pop(context);
          _showAlarmEditor();
        },
        onEditAlarm: (alarm) {
          Navigator.pop(context);
          _showAlarmEditor(alarm);
        },
        onToggleAlarm: (alarm) async {
          alarm.enabled = !alarm.enabled;
          await _saveAlarm(alarm);
          setState(() {});
        },
        onDeleteAlarm: (alarm) async {
          await _deleteAlarm(alarm);
        },
        onRefresh: _loadAlarms,
      ),
    );
  }
}

/// Alarms panel bottom sheet
class _AlarmsPanelSheet extends StatefulWidget {
  final List<Alarm> alarms;
  final Color primaryColor;
  final VoidCallback onAddAlarm;
  final Function(Alarm) onEditAlarm;
  final Future<void> Function(Alarm) onToggleAlarm;
  final Function(Alarm) onDeleteAlarm;
  final VoidCallback onRefresh;

  const _AlarmsPanelSheet({
    required this.alarms,
    required this.primaryColor,
    required this.onAddAlarm,
    required this.onEditAlarm,
    required this.onToggleAlarm,
    required this.onDeleteAlarm,
    required this.onRefresh,
  });

  @override
  State<_AlarmsPanelSheet> createState() => _AlarmsPanelSheetState();
}

class _AlarmsPanelSheetState extends State<_AlarmsPanelSheet> {
  Future<void> _handleToggle(Alarm alarm) async {
    await widget.onToggleAlarm(alarm);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Alarms',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: widget.onRefresh,
                          tooltip: 'Refresh',
                        ),
                        IconButton(
                          icon: Icon(Icons.add, color: widget.primaryColor),
                          onPressed: widget.onAddAlarm,
                          tooltip: 'Add Alarm',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Alarms list
              Expanded(
                child: widget.alarms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.alarm_off, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No alarms set',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: widget.onAddAlarm,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Alarm'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: widget.alarms.length,
                        itemBuilder: (context, index) {
                          final alarm = widget.alarms[index];
                          return Dismissible(
                            key: Key(alarm.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => widget.onDeleteAlarm(alarm),
                            child: ListTile(
                              leading: Icon(
                                alarm.enabled ? Icons.alarm : Icons.alarm_off,
                                color: alarm.enabled ? widget.primaryColor : Colors.grey,
                              ),
                              title: Text(
                                alarm.timeString,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w300,
                                  color: alarm.enabled ? null : Colors.grey,
                                ),
                              ),
                              subtitle: Text(
                                alarm.label + (alarm.repeatDays.isNotEmpty ? ' • ${_formatRepeat(alarm.repeatDays)}' : ''),
                                style: TextStyle(
                                  color: alarm.enabled ? null : Colors.grey,
                                ),
                              ),
                              trailing: Switch(
                                value: alarm.enabled,
                                onChanged: (_) => _handleToggle(alarm),
                                activeTrackColor: widget.primaryColor.withAlpha(180),
                                activeThumbColor: widget.primaryColor,
                              ),
                              onTap: () => widget.onEditAlarm(alarm),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatRepeat(List<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.length == 5 && !days.contains(0) && !days.contains(6)) return 'Weekdays';
    if (days.length == 2 && days.contains(0) && days.contains(6)) return 'Weekends';

    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days.map((d) => dayNames[d]).join(', ');
  }
}

/// Alarm editor bottom sheet
class _AlarmEditorSheet extends StatefulWidget {
  final Alarm alarm;
  final bool isNew;
  final Color primaryColor;
  final Function(Alarm) onSave;
  final VoidCallback? onDelete;

  const _AlarmEditorSheet({
    required this.alarm,
    required this.isNew,
    required this.primaryColor,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_AlarmEditorSheet> createState() => _AlarmEditorSheetState();
}

class _AlarmEditorSheetState extends State<_AlarmEditorSheet> {
  late TextEditingController _labelController;
  late int _hour; // Always stored in 24-hour format
  late int _minute;
  late List<int> _repeatDays;
  late AlarmSound _sound;
  bool _use24Hour = true; // Toggle between 12-hour and 24-hour display
  AudioPlayer? _previewPlayer;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.alarm.label);
    _hour = widget.alarm.hour;
    _minute = widget.alarm.minute;
    _repeatDays = List.from(widget.alarm.repeatDays);
    _sound = widget.alarm.sound;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _previewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _previewSound(AlarmSound sound) async {
    try {
      _previewPlayer?.stop();
      _previewPlayer?.dispose();
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setVolume(1.0);
      final soundInfo = alarmSounds[sound]!;
      final assetPath = soundInfo.assetPath.replaceFirst('assets/', '');
      if (kDebugMode) print('Preview sound: ${soundInfo.name} from $assetPath');
      await _previewPlayer!.play(AssetSource(assetPath));
    } catch (e) {
      if (kDebugMode) print('Error previewing sound: $e');
    }
  }

  // Convert 24-hour to 12-hour display value
  int get _displayHour {
    if (_use24Hour) return _hour;
    if (_hour == 0) return 12;
    if (_hour > 12) return _hour - 12;
    return _hour;
  }

  // Get AM/PM indicator
  bool get _isPM => _hour >= 12;

  // Set hour from 12-hour input
  void _setHourFrom12Hour(int displayHour) {
    if (_use24Hour) {
      _hour = displayHour;
    } else {
      if (_isPM) {
        _hour = displayHour == 12 ? 12 : displayHour + 12;
      } else {
        _hour = displayHour == 12 ? 0 : displayHour;
      }
    }
  }

  // Toggle AM/PM
  void _toggleAmPm() {
    if (_hour < 12) {
      _hour += 12;
    } else {
      _hour -= 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Text(
                widget.isNew ? 'New Alarm' : 'Edit Alarm',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 12/24 hour toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('12h'),
                    selected: !_use24Hour,
                    onSelected: (_) => setState(() => _use24Hour = false),
                    selectedColor: widget.primaryColor.withAlpha(100),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('24h'),
                    selected: _use24Hour,
                    onSelected: (_) => setState(() => _use24Hour = true),
                    selectedColor: widget.primaryColor.withAlpha(100),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Time picker
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimePicker(
                    value: _displayHour,
                    maxValue: _use24Hour ? 23 : 12,
                    minValue: _use24Hour ? 0 : 1,
                    onChanged: (v) => setState(() {
                      if (_use24Hour) {
                        _hour = v;
                      } else {
                        _setHourFrom12Hour(v);
                      }
                    }),
                  ),
                  Text(
                    ':',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: widget.primaryColor,
                    ),
                  ),
                  _buildTimePicker(
                    value: _minute,
                    maxValue: 59,
                    minValue: 0,
                    onChanged: (v) => setState(() => _minute = v),
                  ),
                  // AM/PM selector (only in 12-hour mode)
                  if (!_use24Hour) ...[
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            if (_isPM) _toggleAmPm();
                          }),
                          style: TextButton.styleFrom(
                            backgroundColor: !_isPM ? widget.primaryColor.withAlpha(50) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            'AM',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: !_isPM ? FontWeight.bold : FontWeight.normal,
                              color: !_isPM ? widget.primaryColor : Colors.grey,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            if (!_isPM) _toggleAmPm();
                          }),
                          style: TextButton.styleFrom(
                            backgroundColor: _isPM ? widget.primaryColor.withAlpha(50) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            'PM',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: _isPM ? FontWeight.bold : FontWeight.normal,
                              color: _isPM ? widget.primaryColor : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              // Label
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: 'Label',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.label_outline),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.primaryColor),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Repeat days
              Text(
                'Repeat',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  const dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                  final isSelected = _repeatDays.contains(i);
                  return FilterChip(
                    label: Text(dayNames[i]),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _repeatDays.add(i);
                        } else {
                          _repeatDays.remove(i);
                        }
                        _repeatDays.sort();
                      });
                    },
                    selectedColor: widget.primaryColor.withAlpha(100),
                    checkmarkColor: widget.primaryColor,
                  );
                }),
              ),
              const SizedBox(height: 20),
              // Sound selection
              Text(
                'Alarm Sound',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AlarmSound.values.map((sound) {
                  final soundInfo = alarmSounds[sound]!;
                  final isSelected = _sound == sound;
                  return ChoiceChip(
                    avatar: Icon(
                      soundInfo.icon,
                      size: 18,
                      color: isSelected ? widget.primaryColor : null,
                    ),
                    label: Text(soundInfo.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _sound = sound);
                        _previewSound(sound);
                      }
                    },
                    selectedColor: widget.primaryColor.withAlpha(100),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  if (widget.onDelete != null) ...[
                    IconButton(
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red,
                      tooltip: 'Delete',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _previewPlayer?.stop();
                        Navigator.pop(context);
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker({
    required int value,
    required int maxValue,
    required int minValue,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // UP arrow = scroll up = earlier time = decrease value
          IconButton(
            onPressed: () {
              int newValue = value - 1;
              if (newValue < minValue) newValue = maxValue;
              onChanged(newValue);
            },
            icon: const Icon(Icons.keyboard_arrow_up),
            iconSize: 32,
          ),
          Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w300,
              color: widget.primaryColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // DOWN arrow = scroll down = later time = increase value
          IconButton(
            onPressed: () {
              int newValue = value + 1;
              if (newValue > maxValue) newValue = minValue;
              onChanged(newValue);
            },
            icon: const Icon(Icons.keyboard_arrow_down),
            iconSize: 32,
          ),
        ],
      ),
    );
  }

  void _save() {
    _previewPlayer?.stop();
    widget.alarm.label = _labelController.text.isEmpty ? 'Alarm' : _labelController.text;
    widget.alarm.hour = _hour;
    widget.alarm.minute = _minute;
    widget.alarm.repeatDays = _repeatDays;
    widget.alarm.sound = _sound;
    widget.alarm.enabled = true;
    widget.alarm.snoozed = false;
    widget.alarm.snoozeUntil = null;
    widget.onSave(widget.alarm);
    Navigator.pop(context);
  }
}

/// Builder for clock alarm tool
class ClockAlarmToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'clock_alarm',
      name: 'Clock & Alarm',
      description: 'Smart clock with multiple face styles and alarms stored in SignalK',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [
          'primaryColor',
          'faceStyle',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'faceStyle': 'analog',
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ClockAlarmTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
