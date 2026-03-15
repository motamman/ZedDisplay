import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/cpa_alert_state.dart';
import '../../models/notification_payload.dart';
import '../../services/signalk_service.dart';
import '../../services/cpa_alert_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/notification_navigation_service.dart';
import '../../services/notification_service.dart';
import '../../services/messaging_service.dart';
import '../../services/storage_service.dart';
import '../../services/alert_coordinator.dart';
import '../../services/tool_registry.dart';
import '../../services/tool_service.dart';
import '../../utils/color_extensions.dart';
import '../ais_polar_chart.dart';
import '../tool_info_button.dart';

/// Config-driven AIS polar chart tool
///
/// This tool visualizes nearby AIS vessels in polar coordinates:
/// - Own vessel at center (0,0)
/// - Other vessels plotted at relative bearing and distance
/// - CPA/TCPA calculations using own vessel COG and SOG
/// - CPA alert service created/owned by this widget (anchor alarm pattern)
class AISPolarChartTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AISPolarChartTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Default paths for AIS chart
  static const _defaultPaths = [
    'navigation.position',              // 0: own position
    'navigation.courseOverGroundTrue',  // 1: own COG for CPA calculation
    'navigation.speedOverGround',       // 2: own SOG for CPA calculation
  ];

  @override
  State<AISPolarChartTool> createState() => _AISPolarChartToolState();
}

class _AISPolarChartToolState extends State<AISPolarChartTool> {
  CpaAlertService? _cpaAlertService;

  @override
  void initState() {
    super.initState();
    _configureCpaAlerts();
  }

  void _configureCpaAlerts() {
    final props = widget.config.style.customProperties ?? {};
    final enabled = props['cpaAlertsEnabled'] as bool? ?? true;

    // Get messaging service from Provider (nullable, like anchor alarm)
    MessagingService? messagingService;
    try {
      messagingService = Provider.of<MessagingService>(context, listen: false);
    } catch (_) {}

    // Get storage service for notification filter settings
    StorageService? storageService;
    try {
      storageService = Provider.of<StorageService>(context, listen: false);
    } catch (_) {}

    // Get alert coordinator from provider if available (reserved for future use)
    try {
      Provider.of<AlertCoordinator>(context, listen: false);
    } catch (_) {}

    // Always create the service so the modal can enable/disable it
    _cpaAlertService = CpaAlertService(
      signalKService: widget.signalKService,
      notificationService: NotificationService(),
      messagingService: messagingService,
      storageService: storageService,
      // alertCoordinator: alertCoordinator, // TEMP: bypass to test freeze
    );

    _cpaAlertService!.onAlertTriggered = _onCpaAlertTriggered;
    _cpaAlertService!.onAlertDismissed = _onCpaAlertDismissed;

    _cpaAlertService!.applyConfig(CpaAlertConfig(
      enabled: enabled,
      warnThresholdMeters: ((props['cpaWarnNm'] as num?)?.toDouble() ?? 1.0) * 1852.0,
      alarmThresholdMeters: ((props['cpaAlarmNm'] as num?)?.toDouble() ?? 0.5) * 1852.0,
      tcpaThresholdSeconds: ((props['cpaTcpaMinutes'] as num?)?.toDouble() ?? 30.0) * 60.0,
      alarmSound: props['cpaAlarmSound'] as String? ?? 'foghorn',
      cooldownSeconds: ((props['cpaCooldownMinutes'] as int?) ?? 5) * 60,
      sendCrewAlert: props['cpaSendCrewAlert'] as bool? ?? true,
      maxRangeMeters: ((props['maxRangeNm'] as num?)?.toDouble() ?? 100.0) * 1852.0,
    ));
  }

  void _onCpaAlertDismissed(String vesselId) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _onCpaAlertTriggered(CpaVesselAlert alert, String message) {
    if (!mounted) return;

    final isAlarm = alert.level.isAlarming;
    final backgroundColor =
        isAlarm ? Colors.red.shade700 : Colors.orange.shade700;
    final icon = isAlarm ? Icons.warning : Icons.info;
    final duration =
        isAlarm ? const Duration(seconds: 10) : const Duration(seconds: 5);

    // Build navigation target
    const payload = NotificationPayload(
      type: 'signalk',
      toolTypeId: 'ais_polar_chart',
    );

    DashboardService? dashboardService;
    try {
      dashboardService =
          Provider.of<DashboardService>(context, listen: false);
    } catch (_) {}

    (VoidCallback navigate, String screenName)? navResult;
    if (dashboardService != null) {
      final navService = NotificationNavigationService(dashboardService);
      navResult = navService.getNavigation(payload);
    }

    final String? hintText =
        navResult != null ? 'TAP: ${navResult.$2}' : null;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: navResult != null
              ? () {
                  navResult!.$1();
                  _cpaAlertService?.requestHighlight(alert.vesselId);
                  _cpaAlertService?.acknowledgeAlarm();
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                }
              : null,
          behavior: navResult != null
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    if (hintText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        hintText,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            _cpaAlertService?.acknowledgeAlarm();
            _cpaAlertService?.dismissAlert(alert.vesselId);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _onCpaConfigChanged(Map<String, dynamic> updatedCpaProps) {
    final toolId = widget.config.style.customProperties?['_toolId'] as String?;
    if (toolId == null) return;

    final toolService = Provider.of<ToolService>(context, listen: false);
    final tool = toolService.getTool(toolId);
    if (tool == null) return;

    final updatedProps = {
      ...?tool.config.style.customProperties,
      ...updatedCpaProps,
    };
    final updatedTool = tool.copyWith(
      config: ToolConfig(
        vesselId: tool.config.vesselId,
        dataSources: tool.config.dataSources,
        style: StyleConfig(
          minValue: tool.config.style.minValue,
          maxValue: tool.config.style.maxValue,
          unit: tool.config.style.unit,
          primaryColor: tool.config.style.primaryColor,
          secondaryColor: tool.config.style.secondaryColor,
          showLabel: tool.config.style.showLabel,
          showValue: tool.config.style.showValue,
          showUnit: tool.config.style.showUnit,
          ttlSeconds: tool.config.style.ttlSeconds,
          customProperties: updatedProps,
        ),
      ),
    );
    toolService.saveTool(updatedTool);
  }

  @override
  void dispose() {
    _cpaAlertService?.dispose();
    super.dispose();
  }

  /// Get path at index, using default if not configured
  String _getPath(int index) {
    if (widget.config.dataSources.length > index && widget.config.dataSources[index].path.isNotEmpty) {
      return widget.config.dataSources[index].path;
    }
    return AISPolarChartTool._defaultPaths[index];
  }

  @override
  Widget build(BuildContext context) {
    // Get configuration from custom properties
    final showLabels = widget.config.style.customProperties?['showLabels'] as bool? ?? true;
    final showGrid = widget.config.style.customProperties?['showGrid'] as bool? ?? true;
    final pruneMinutes = widget.config.style.customProperties?['pruneMinutes'] as int? ?? 15;
    final colorByShipType = widget.config.style.customProperties?['colorByShipType'] as bool? ?? true;
    final showProjectedPositions = widget.config.style.customProperties?['showProjectedPositions'] as bool? ?? true;
    final maxRangeNm = (widget.config.style.customProperties?['maxRangeNm'] as num?)?.toDouble() ?? 100.0;
    final vesselLookupService = widget.config.style.customProperties?['vesselLookupService'] as String? ?? 'vesselfinder';

    // Get paths from data sources (with defaults)
    final positionPath = _getPath(0);
    final cogPath = _getPath(1);
    final sogPath = _getPath(2);

    // Parse vessel color
    final vesselColor = widget.config.style.primaryColor?.toColor();

    // Generate title
    final title = widget.config.style.customProperties?['title'] as String? ?? 'AIS Vessels';

    return Stack(
      children: [
        AISPolarChart(
          key: ValueKey('ais_chart_$positionPath'),
          signalKService: widget.signalKService,
          positionPath: positionPath,
          cogPath: cogPath,
          sogPath: sogPath,
          title: title,
          vesselColor: vesselColor,
          showLabels: showLabels,
          showGrid: showGrid,
          pruneMinutes: pruneMinutes,
          colorByShipType: colorByShipType,
          showProjectedPositions: showProjectedPositions,
          maxRangeNm: maxRangeNm,
          vesselLookupService: vesselLookupService,
          cpaAlertService: _cpaAlertService,
          onCpaConfigChanged: _onCpaConfigChanged,
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: ToolInfoButton(
              toolId: 'ais_polar_chart',
              signalKService: widget.signalKService,
              iconSize: 20,
              iconColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Builder for AIS polar chart tools
class AISPolarChartBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'ais_polar_chart',
      name: 'AIS Polar Chart',
      description: 'Display nearby AIS vessels on polar chart with CPA/TCPA calculations',
      category: ToolCategory.ais,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 3,
        styleOptions: const [
          'primaryColor',      // Vessel color
          'title',             // Chart title
          'showLabel',         // Show compass labels (N, NE, E, etc.)
          'showGrid',          // Show grid lines
          'pruneMinutes',      // Minutes before vessel is removed from display
        ],
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AISPolarChartTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.position', label: 'Own Position'),
        DataSource(path: 'navigation.courseOverGroundTrue', label: 'Own COG'),
        DataSource(path: 'navigation.speedOverGround', label: 'Own SOG'),
      ],
      style: StyleConfig(
        customProperties: {
          'showLabels': true,
          'showGrid': true,
          'title': 'AIS Vessels',
          'pruneMinutes': 15,
          'colorByShipType': true,
          'showProjectedPositions': true,
          'maxRangeNm': 100.0,
          'cpaAlertsEnabled': true,
          'cpaWarnNm': 1.0,
          'cpaAlarmNm': 0.5,
          'cpaTcpaMinutes': 30.0,
          'cpaAlarmSound': 'foghorn',
          'cpaSendCrewAlert': true,
          'cpaCooldownMinutes': 5,
        },
      ),
    );
  }
}
