import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// NWS Alert severity levels
enum AlertSeverity {
  extreme,
  severe,
  moderate,
  minor,
  unknown;

  static AlertSeverity fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'extreme':
        return AlertSeverity.extreme;
      case 'severe':
        return AlertSeverity.severe;
      case 'moderate':
        return AlertSeverity.moderate;
      case 'minor':
        return AlertSeverity.minor;
      default:
        return AlertSeverity.unknown;
    }
  }

  Color get color {
    switch (this) {
      case AlertSeverity.extreme:
        return Colors.purple.shade700;
      case AlertSeverity.severe:
        return Colors.red.shade700;
      case AlertSeverity.moderate:
        return Colors.orange.shade700;
      case AlertSeverity.minor:
        return Colors.yellow.shade700;
      case AlertSeverity.unknown:
        return Colors.grey.shade600;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case AlertSeverity.extreme:
        return Colors.purple.shade100;
      case AlertSeverity.severe:
        return Colors.red.shade100;
      case AlertSeverity.moderate:
        return Colors.orange.shade100;
      case AlertSeverity.minor:
        return Colors.yellow.shade100;
      case AlertSeverity.unknown:
        return Colors.grey.shade200;
    }
  }

  IconData get icon {
    switch (this) {
      case AlertSeverity.extreme:
        return PhosphorIcons.warning();
      case AlertSeverity.severe:
        return PhosphorIcons.warningCircle();
      case AlertSeverity.moderate:
        return PhosphorIcons.info();
      case AlertSeverity.minor:
        return PhosphorIcons.bellRinging();
      case AlertSeverity.unknown:
        return PhosphorIcons.question();
    }
  }

  int get priority {
    switch (this) {
      case AlertSeverity.extreme:
        return 0;
      case AlertSeverity.severe:
        return 1;
      case AlertSeverity.moderate:
        return 2;
      case AlertSeverity.minor:
        return 3;
      case AlertSeverity.unknown:
        return 4;
    }
  }
}

/// Parsed NWS Alert
class NWSAlert {
  final String id;
  final String event;
  final String headline;
  final String description;
  final String? instruction;
  final AlertSeverity severity;
  final String certainty;
  final String urgency;
  final DateTime? effective;
  final DateTime? expires;
  final DateTime? onset;
  final DateTime? ends;
  final String areaDesc;
  final String senderName;

  NWSAlert({
    required this.id,
    required this.event,
    required this.headline,
    required this.description,
    this.instruction,
    required this.severity,
    required this.certainty,
    required this.urgency,
    this.effective,
    this.expires,
    this.onset,
    this.ends,
    required this.areaDesc,
    required this.senderName,
  });

  /// Check if alert is currently active
  bool get isActive {
    final now = DateTime.now();
    if (expires != null && now.isAfter(expires!)) return false;
    if (ends != null && now.isAfter(ends!)) return false;
    if (urgency.toLowerCase() == 'past') return false;
    return true;
  }

  /// Check if alert is imminent (onset within 2 hours)
  bool get isImminent {
    if (onset == null) return false;
    final now = DateTime.now();
    final diff = onset!.difference(now);
    return diff.inHours <= 2 && diff.inMinutes >= 0;
  }
}

/// Global notifier for expanding a specific alert from snackbar/notification
class WeatherAlertsNotifier extends ChangeNotifier {
  static final WeatherAlertsNotifier instance = WeatherAlertsNotifier._();
  WeatherAlertsNotifier._();

  String? _expandAlertId;
  String? get expandAlertId => _expandAlertId;

  void requestExpandAlert(String alertId) {
    _expandAlertId = alertId;
    notifyListeners();
    // Clear after a short delay so it can be triggered again
    Future.delayed(const Duration(milliseconds: 100), () {
      _expandAlertId = null;
    });
  }
}

/// Weather Alerts Tool - displays NWS alerts with severity-based alerting
class WeatherAlertsTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WeatherAlertsTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<WeatherAlertsTool> createState() => _WeatherAlertsToolState();
}

class _WeatherAlertsToolState extends State<WeatherAlertsTool>
    with SingleTickerProviderStateMixin {
  List<NWSAlert> _alerts = [];
  Set<String> _seenAlertIds = {};
  Set<String> _newAlertIds = {};
  String? _expandedAlertId;
  late AnimationController _pulseController;
  Timer? _debounceTimer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    widget.signalKService.addListener(_onDataChanged);
    WeatherAlertsNotifier.instance.addListener(_onExpandRequest);

    // Initial load after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadAlerts();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _debounceTimer?.cancel();
    widget.signalKService.removeListener(_onDataChanged);
    WeatherAlertsNotifier.instance.removeListener(_onExpandRequest);
    super.dispose();
  }

  void _onExpandRequest() {
    final alertId = WeatherAlertsNotifier.instance.expandAlertId;
    if (alertId != null && mounted) {
      // Find matching alert and expand it
      final matchingAlert = _alerts.where((a) =>
        a.id == alertId ||
        a.id.contains(alertId) ||
        alertId.contains(a.id)
      ).firstOrNull;

      if (matchingAlert != null) {
        setState(() {
          _expandedAlertId = matchingAlert.id;
          _newAlertIds.remove(matchingAlert.id);
        });
      }
    }
  }

  void _onDataChanged() {
    // Debounce to avoid processing every websocket message
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _loadAlerts();
    });
  }

  void _loadAlerts() {
    // Prevent concurrent loads
    if (_isLoading) return;
    _isLoading = true;

    try {
      final alerts = <NWSAlert>[];
      final basePath = 'environment.outside.nws.alert';

      // Get all alert keys by checking for known alert fields
      final allPaths = widget.signalKService.latestData.keys;
      final alertPaths = allPaths.where((p) => p.startsWith('$basePath.') && p.endsWith('.event'));

      for (final path in alertPaths) {
        // Extract alert ID from path like "environment.outside.nws.alert.abc123.event"
        final parts = path.split('.');
        if (parts.length >= 5) {
          final alertId = parts[4];
          final alert = _parseAlert(alertId, basePath);
          if (alert != null) {
            alerts.add(alert);
          }
        }
      }

      // Sort by severity (highest first), then by onset time
      alerts.sort((a, b) {
        final severityCompare = a.severity.priority.compareTo(b.severity.priority);
        if (severityCompare != 0) return severityCompare;
        if (a.onset != null && b.onset != null) {
          return a.onset!.compareTo(b.onset!);
        }
        return 0;
      });

      // Check for new alerts
      final currentIds = alerts.map((a) => a.id).toSet();
      final newIds = currentIds.difference(_seenAlertIds);

      if (mounted) {
        setState(() {
          _alerts = alerts;
          _newAlertIds = newIds;
          _seenAlertIds = currentIds;
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  NWSAlert? _parseAlert(String alertId, String basePath) {
    String? getValue(String field) {
      final data = widget.signalKService.getValue('$basePath.$alertId.$field');
      return data?.value?.toString();
    }

    DateTime? getDateTime(String field) {
      final value = getValue(field);
      if (value == null) return null;
      return DateTime.tryParse(value);
    }

    final event = getValue('event');
    if (event == null) return null;

    final headline = getValue('headline') ?? event;
    final description = getValue('description') ?? '';
    final severityStr = getValue('severity');

    return NWSAlert(
      id: alertId,
      event: event,
      headline: headline,
      description: description,
      instruction: getValue('instruction'),
      severity: AlertSeverity.fromString(severityStr),
      certainty: getValue('certainty') ?? 'Unknown',
      urgency: getValue('urgency') ?? 'Unknown',
      effective: getDateTime('effective'),
      expires: getDateTime('expires'),
      onset: getDateTime('onset'),
      ends: getDateTime('ends'),
      areaDesc: getValue('areaDesc') ?? '',
      senderName: getValue('senderName') ?? 'NWS',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeAlerts = _alerts.where((a) => a.isActive).toList();
    final props = widget.config.style.customProperties;
    final showCompact = props?['compact'] as bool? ?? false;
    final showDescription = props?['showDescription'] as bool? ?? true;
    final showInstruction = props?['showInstruction'] as bool? ?? true;
    final showAreaDesc = props?['showAreaDesc'] as bool? ?? false;
    final showSenderName = props?['showSenderName'] as bool? ?? false;
    final showTimeRange = props?['showTimeRange'] as bool? ?? true;

    if (activeAlerts.isEmpty) {
      return _buildNoAlerts(isDark);
    }

    if (showCompact) {
      return _buildCompactView(activeAlerts, isDark);
    }

    return _buildFullView(
      activeAlerts,
      isDark,
      showTimeRange: showTimeRange,
      showDescription: showDescription,
      showInstruction: showInstruction,
      showAreaDesc: showAreaDesc,
      showSenderName: showSenderName,
    );
  }

  Widget _buildNoAlerts(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.checkCircle(),
            size: 48,
            color: Colors.green.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'No Active Alerts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView(List<NWSAlert> alerts, bool isDark) {
    final highestSeverity = alerts.first.severity;
    final hasNew = _newAlertIds.isNotEmpty;

    return GestureDetector(
      onTap: () => _showAlertsDialog(alerts),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = hasNew || highestSeverity == AlertSeverity.extreme
              ? 0.3 + (_pulseController.value * 0.2)
              : 0.0;

          return Container(
            decoration: BoxDecoration(
              color: highestSeverity.backgroundColor.withValues(alpha: 0.3 + pulse),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: highestSeverity.color,
                width: 2,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        highestSeverity.icon,
                        size: 32,
                        color: highestSeverity.color,
                      ),
                      if (alerts.length > 1)
                        Positioned(
                          right: -8,
                          top: -8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: highestSeverity.color,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${alerts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      alerts.first.event,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: highestSeverity.color,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullView(
    List<NWSAlert> alerts,
    bool isDark, {
    required bool showTimeRange,
    required bool showDescription,
    required bool showInstruction,
    required bool showAreaDesc,
    required bool showSenderName,
  }) {
    return Column(
      children: [
        // Header with alert count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: alerts.first.severity.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.warning(),
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${alerts.length} Active Alert${alerts.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                'NWS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Alert list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final isExpanded = _expandedAlertId == alert.id;
              final isNew = _newAlertIds.contains(alert.id);

              return _buildAlertCard(
                alert,
                isExpanded,
                isNew,
                isDark,
                showTimeRange: showTimeRange,
                showDescription: showDescription,
                showInstruction: showInstruction,
                showAreaDesc: showAreaDesc,
                showSenderName: showSenderName,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlertCard(
    NWSAlert alert,
    bool isExpanded,
    bool isNew,
    bool isDark, {
    required bool showTimeRange,
    required bool showDescription,
    required bool showInstruction,
    required bool showAreaDesc,
    required bool showSenderName,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = isNew ? 0.3 + (_pulseController.value * 0.2) : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: alert.severity.backgroundColor.withValues(alpha: 0.5 + pulse),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: alert.severity.color,
              width: isNew ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _expandedAlertId = isExpanded ? null : alert.id;
                // Mark as seen when tapped
                _newAlertIds.remove(alert.id);
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Icon(
                        alert.severity.icon,
                        color: alert.severity.color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alert.event,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: alert.severity.color,
                          ),
                        ),
                      ),
                      if (alert.isImminent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'IMMINENT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: alert.severity.color,
                      ),
                    ],
                  ),

                  // Time info
                  if (showTimeRange && (alert.onset != null || alert.ends != null)) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTimeRange(alert),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],

                  // Expanded content
                  if (isExpanded) ...[
                    const Divider(height: 16),
                    Text(
                      alert.headline,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (showDescription) ...[
                      const SizedBox(height: 8),
                      Text(
                        alert.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                    if (showInstruction && alert.instruction != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              PhosphorIcons.info(),
                              size: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                alert.instruction!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (showAreaDesc && alert.areaDesc.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Areas: ${alert.areaDesc}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                    if (showSenderName) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Source: ${alert.senderName}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimeRange(NWSAlert alert) {
    final now = DateTime.now();
    final parts = <String>[];

    if (alert.onset != null) {
      final onsetLocal = alert.onset!.toLocal();
      if (onsetLocal.isAfter(now)) {
        parts.add('Starts: ${_formatDateTime(onsetLocal)}');
      } else {
        parts.add('Started: ${_formatDateTime(onsetLocal)}');
      }
    }

    if (alert.ends != null) {
      final endsLocal = alert.ends!.toLocal();
      parts.add('Until: ${_formatDateTime(endsLocal)}');
    }

    return parts.join(' | ');
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dtDate = DateTime(dt.year, dt.month, dt.day);

    String dayPart;
    if (dtDate == today) {
      dayPart = 'Today';
    } else if (dtDate == tomorrow) {
      dayPart = 'Tomorrow';
    } else {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      dayPart = days[dt.weekday - 1];
    }

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$dayPart $displayHour:$minute $ampm';
  }

  void _showAlertsDialog(List<NWSAlert> alerts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(PhosphorIcons.warning(), color: alerts.first.severity.color),
            const SizedBox(width: 8),
            Text('${alerts.length} Active Alerts'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return ExpansionTile(
                leading: Icon(alert.severity.icon, color: alert.severity.color),
                title: Text(
                  alert.event,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: alert.severity.color,
                  ),
                ),
                subtitle: Text(_formatTimeRange(alert)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alert.description),
                        if (alert.instruction != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            alert.instruction!,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Builder for Weather Alerts tool
class WeatherAlertsToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'weather_alerts',
      name: 'NWS Weather Alerts',
      description: 'Display NWS weather alerts with severity-based alerting',
      category: ToolCategory.display,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [
          'compact',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [],
      style: StyleConfig(
        customProperties: {
          'compact': false,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WeatherAlertsTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
