import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../windsteer_gauge.dart';

/// Simple windsteer demo with hardcoded common SignalK paths
/// This is a temporary tool to demonstrate windsteer functionality
class WindsteerDemoTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WindsteerDemoTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  /// Get converted value using MetadataStore
  double? _getConverted(String path) {
    final dataPoint = signalKService.getValue(path);
    final rawValue = (dataPoint?.value as num?)?.toDouble();
    if (rawValue == null) return null;
    final metadata = signalKService.metadataStore.get(path);
    return metadata?.convert(rawValue) ?? rawValue;
  }

  /// Get formatted value using MetadataStore
  String? _getFormatted(String path) {
    final dataPoint = signalKService.getValue(path);
    final rawValue = (dataPoint?.value as num?)?.toDouble();
    if (rawValue == null) return null;
    final metadata = signalKService.metadataStore.get(path);
    return metadata?.format(rawValue, decimals: 1);
  }

  @override
  Widget build(BuildContext context) {
    // Hardcoded common SignalK paths - using MetadataStore
    final heading = _getConverted('navigation.headingMagnetic') ??
                    _getConverted('navigation.headingTrue') ?? 0.0;

    final apparentWindAngle = _getConverted('environment.wind.angleApparent');
    final trueWindAngle = _getConverted('environment.wind.angleTrueWater');

    final apparentWindSpeed = _getConverted('environment.wind.speedApparent');
    final awsFormatted = _getFormatted('environment.wind.speedApparent');

    final trueWindSpeed = _getConverted('environment.wind.speedTrue');
    final twsFormatted = _getFormatted('environment.wind.speedTrue');

    final courseOverGround = _getConverted('navigation.courseOverGroundTrue');
    final waypointBearing = _getConverted('navigation.course.nextPoint.bearingTrue');

    final driftSet = _getConverted('environment.current.setTrue');
    final driftFlow = _getConverted('environment.current.drift');
    final driftFormatted = _getFormatted('environment.current.drift');

    // Get style configuration
    final style = config.style;
    final laylineAngle = style.laylineAngle ?? 45.0;
    final showLaylines = style.showLaylines ?? true;
    final showTrueWind = style.showTrueWind ?? true;
    final showCOG = style.showCOG ?? false;
    final showAWS = style.showAWS ?? true;
    final showTWS = style.showTWS ?? true;
    final showDrift = style.customProperties?['showDrift'] as bool? ?? false;
    final showWaypoint = style.customProperties?['showWaypoint'] as bool? ?? false;

    // Parse colors
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue
    ) ?? Colors.blue;

    final secondaryColor = style.secondaryColor?.toColor(
      fallback: Colors.green
    ) ?? Colors.green;

    return Column(
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.amber.withValues(alpha: 0.3),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Auto-configured with standard SignalK paths',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        // Windsteer gauge
        Expanded(
          child: WindsteerGauge(
            heading: heading,
            apparentWindAngle: apparentWindAngle,
            apparentWindSpeed: apparentWindSpeed,
            trueWindAngle: trueWindAngle,
            trueWindSpeed: trueWindSpeed,
            courseOverGround: courseOverGround,
            waypointBearing: waypointBearing,
            driftSet: driftSet,
            driftFlow: driftFlow,
            laylineAngle: laylineAngle,
            showLaylines: showLaylines,
            showTrueWind: showTrueWind,
            showCOG: showCOG,
            showAWS: showAWS,
            showTWS: showTWS,
            showDrift: showDrift,
            showWaypoint: showWaypoint,
            showWindSectors: false,
            awsFormatted: awsFormatted,
            twsFormatted: twsFormatted,
            driftFormatted: driftFormatted,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
          ),
        ),
      ],
    );
  }
}

/// Builder for windsteer demo tool
class WindsteerDemoToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'windsteer_demo',
      name: 'Windsteer (Auto)',
      description: 'Wind steering gauge with automatic path detection - perfect for quick setup!',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [
          'primaryColor',      // AWA color (default: blue)
          'secondaryColor',    // TWA color (default: green)
          'laylineAngle',      // Layline angle (default: 45°)
          'showLaylines',      // Show laylines (default: true)
          'showTrueWind',      // Show TWA (default: true)
          'showCOG',           // Show COG (default: false)
          'showAWS',           // Show AWS (default: true)
          'showTWS',           // Show TWS (default: true)
          'customProperties.showDrift',    // Show drift (default: false)
          'customProperties.showWaypoint', // Show waypoint (default: false)
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WindsteerDemoTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
