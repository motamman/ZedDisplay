import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/cpa_alert_state.dart';
import '../../services/signalk_service.dart';
import '../../services/cpa_alert_service.dart';
import '../../services/notification_service.dart';
import '../../services/messaging_service.dart';
import '../../services/tool_registry.dart';
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

    if (!enabled) return;

    // Get messaging service from Provider (nullable, like anchor alarm)
    MessagingService? messagingService;
    try {
      messagingService = Provider.of<MessagingService>(context, listen: false);
    } catch (_) {}

    _cpaAlertService = CpaAlertService(
      signalKService: widget.signalKService,
      notificationService: NotificationService(),
      messagingService: messagingService,
    );

    _cpaAlertService!.applyConfig(CpaAlertConfig(
      enabled: true,
      warnThresholdMeters: ((props['cpaWarnNm'] as num?)?.toDouble() ?? 1.0) * 1852.0,
      alarmThresholdMeters: ((props['cpaAlarmNm'] as num?)?.toDouble() ?? 0.5) * 1852.0,
      tcpaThresholdSeconds: ((props['cpaTcpaMinutes'] as num?)?.toDouble() ?? 30.0) * 60.0,
      alarmSound: props['cpaAlarmSound'] as String? ?? 'foghorn',
      cooldownSeconds: ((props['cpaCooldownMinutes'] as int?) ?? 5) * 60,
      sendCrewAlert: props['cpaSendCrewAlert'] as bool? ?? true,
    ));
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
