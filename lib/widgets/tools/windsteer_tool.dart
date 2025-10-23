import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../windsteer_gauge.dart';

/// Config-driven windsteer tool with comprehensive features
class WindsteerTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WindsteerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Expected data sources (in order):
    // 0: navigation.headingMagnetic or navigation.headingTrue (REQUIRED)
    // 1: environment.wind.angleApparent (optional)
    // 2: environment.wind.angleTrueWater (optional)
    // 3: environment.wind.speedApparent (optional)
    // 4: environment.wind.speedTrue (optional)
    // 5: navigation.courseOverGroundTrue (optional)
    // 6: navigation.course.nextPoint.bearingTrue (optional - waypoint bearing)
    // 7: environment.current.setTrue (optional - current direction/set)
    // 8: environment.current.drift (optional - current speed/flow)
    // 9-11: Historical wind data for wind sectors (optional)

    if (config.dataSources.isEmpty) {
      return const Center(child: Text('No heading source configured'));
    }

    // Get heading (required)
    final headingPath = config.dataSources[0].path;
    final heading = signalKService.getConvertedValue(headingPath) ?? 0.0;

    // Get apparent wind angle (optional)
    double? apparentWindAngle;
    if (config.dataSources.length > 1) {
      apparentWindAngle = signalKService.getConvertedValue(config.dataSources[1].path);
    }

    // Get true wind angle (optional)
    double? trueWindAngle;
    if (config.dataSources.length > 2) {
      trueWindAngle = signalKService.getConvertedValue(config.dataSources[2].path);
    }

    // Get apparent wind speed (optional)
    double? apparentWindSpeed;
    String? awsFormatted;
    if (config.dataSources.length > 3) {
      apparentWindSpeed = signalKService.getConvertedValue(config.dataSources[3].path);
      awsFormatted = signalKService.getValue(config.dataSources[3].path)?.formatted;
    }

    // Get true wind speed (optional)
    double? trueWindSpeed;
    String? twsFormatted;
    if (config.dataSources.length > 4) {
      trueWindSpeed = signalKService.getConvertedValue(config.dataSources[4].path);
      twsFormatted = signalKService.getValue(config.dataSources[4].path)?.formatted;
    }

    // Get course over ground (optional)
    double? courseOverGround;
    if (config.dataSources.length > 5) {
      courseOverGround = signalKService.getConvertedValue(config.dataSources[5].path);
    }

    // Get waypoint bearing (optional)
    double? waypointBearing;
    if (config.dataSources.length > 6) {
      waypointBearing = signalKService.getConvertedValue(config.dataSources[6].path);
    }

    // Get drift set - current direction (optional)
    double? driftSet;
    if (config.dataSources.length > 7) {
      driftSet = signalKService.getConvertedValue(config.dataSources[7].path);
    }

    // Get drift flow - current speed (optional)
    double? driftFlow;
    String? driftFormatted;
    if (config.dataSources.length > 8) {
      driftFlow = signalKService.getConvertedValue(config.dataSources[8].path);
      driftFormatted = signalKService.getValue(config.dataSources[8].path)?.formatted;
    }

    // Get historical wind data for wind sectors (optional)
    double? trueWindMinHistoric;
    double? trueWindMidHistoric;
    double? trueWindMaxHistoric;
    if (config.dataSources.length > 9) {
      trueWindMinHistoric = signalKService.getConvertedValue(config.dataSources[9].path);
    }
    if (config.dataSources.length > 10) {
      trueWindMidHistoric = signalKService.getConvertedValue(config.dataSources[10].path);
    }
    if (config.dataSources.length > 11) {
      trueWindMaxHistoric = signalKService.getConvertedValue(config.dataSources[11].path);
    }

    // Get style configuration
    final style = config.style;
    final laylineAngle = style.laylineAngle ?? 40.0;
    final targetTolerance = style.targetTolerance ?? 3.0;
    final showLaylines = style.showLaylines ?? true;
    final showTrueWind = style.showTrueWind ?? true;
    final showCOG = style.showCOG ?? false;
    final showAWS = style.showAWS ?? true;
    final showTWS = style.showTWS ?? true;

    // Additional style options from customProperties
    final showDrift = style.customProperties?['showDrift'] as bool? ?? false;
    final showWaypoint = style.customProperties?['showWaypoint'] as bool? ?? false;
    final showWindSectors = style.customProperties?['showWindSectors'] as bool? ?? false;

    // Parse colors from hex string
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue
    ) ?? Colors.blue;

    final secondaryColor = style.secondaryColor?.toColor(
      fallback: Colors.green
    ) ?? Colors.green;

    return WindsteerGauge(
      heading: heading,
      apparentWindAngle: apparentWindAngle,
      apparentWindSpeed: apparentWindSpeed,
      trueWindAngle: trueWindAngle,
      trueWindSpeed: trueWindSpeed,
      courseOverGround: courseOverGround,
      waypointBearing: waypointBearing,
      driftSet: driftSet,
      driftFlow: driftFlow,
      trueWindMinHistoric: trueWindMinHistoric,
      trueWindMidHistoric: trueWindMidHistoric,
      trueWindMaxHistoric: trueWindMaxHistoric,
      laylineAngle: laylineAngle,
      showLaylines: showLaylines,
      showTrueWind: showTrueWind,
      showCOG: showCOG,
      showAWS: showAWS,
      showTWS: showTWS,
      showDrift: showDrift,
      showWaypoint: showWaypoint,
      showWindSectors: showWindSectors,
      awsFormatted: awsFormatted,
      twsFormatted: twsFormatted,
      driftFormatted: driftFormatted,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
  }
}

/// Builder for windsteer tools
class WindsteerToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'windsteer',
      name: 'Windsteer',
      description: 'Comprehensive wind steering gauge with compass, wind angles, laylines, COG, drift, and waypoints',
      category: ToolCategory.compass,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 12,
        styleOptions: const [
          'primaryColor',      // Apparent wind color (default: blue)
          'secondaryColor',    // True wind color (default: green)
          'laylineAngle',      // Target AWA angle in degrees (default: 40)
          'targetTolerance',   // Acceptable deviation from target in degrees (default: 3)
          'showLaylines',      // Show target AWA lines (default: true)
          'showTrueWind',      // Show true wind indicator (default: true)
          'showCOG',           // Show course over ground (default: false)
          'showAWS',           // Show apparent wind speed (default: true)
          'showTWS',           // Show true wind speed (default: true)
          'customProperties.showDrift',      // Show drift/set indicator (default: false)
          'customProperties.showWaypoint',   // Show waypoint bearing (default: false)
          'customProperties.showWindSectors', // Show wind shift sectors (default: false)
        ],
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WindsteerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
