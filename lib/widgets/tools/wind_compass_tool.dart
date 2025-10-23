import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../wind_compass.dart';

/// Config-driven wind compass tool showing heading and wind direction
class WindCompassTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WindCompassTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Expected data sources (in order):
    // 0: navigation.headingTrue (optional) - in RADIANS from SignalK
    // 1: navigation.headingMagnetic (optional) - in RADIANS from SignalK
    // 2: environment.wind.directionTrue (optional) - in RADIANS from SignalK (absolute)
    // 3: environment.wind.angleApparent (optional) - in RADIANS from SignalK (relative to boat, converted to absolute)
    // 4: environment.wind.speedTrue (optional)
    // 5: environment.wind.speedApparent (optional)
    // 6: navigation.speedOverGround (optional)
    // 7: navigation.courseOverGroundTrue (optional) - in DEGREES

    // Get heading true (optional) - use original radians value for rotation
    double? headingTrueRadians;
    double? headingTrueDegrees;
    if (config.dataSources.isNotEmpty) {
      final dataPoint = signalKService.getValue(config.dataSources[0].path);
      headingTrueRadians = dataPoint?.original is num ? (dataPoint!.original as num).toDouble() : null;
      headingTrueDegrees = signalKService.getConvertedValue(config.dataSources[0].path);
    }

    // Get heading magnetic (optional) - use original radians value for rotation
    double? headingMagneticRadians;
    double? headingMagneticDegrees;
    if (config.dataSources.length > 1) {
      final dataPoint = signalKService.getValue(config.dataSources[1].path);
      headingMagneticRadians = dataPoint?.original is num ? (dataPoint!.original as num).toDouble() : null;
      headingMagneticDegrees = signalKService.getConvertedValue(config.dataSources[1].path);
    }

    // Get wind direction true (optional) - use original radians value
    double? windDirectionTrueRadians;
    double? windDirectionTrueDegrees;
    if (config.dataSources.length > 2) {
      final dataPoint = signalKService.getValue(config.dataSources[2].path);
      windDirectionTrueRadians = dataPoint?.original is num ? (dataPoint!.original as num).toDouble() : null;
      windDirectionTrueDegrees = signalKService.getConvertedValue(config.dataSources[2].path);
    }

    // Get wind angle apparent (relative to boat) and convert to absolute direction
    double? windDirectionApparentRadians;
    double? windDirectionApparentDegrees;
    if (config.dataSources.length > 3) {
      final dataPoint = signalKService.getValue(config.dataSources[3].path);
      final angleApparentRadians = dataPoint?.original is num ? (dataPoint!.original as num).toDouble() : null;
      final angleApparentDegrees = signalKService.getConvertedValue(config.dataSources[3].path);

      // Convert relative angle to absolute direction by adding to heading
      if (angleApparentRadians != null && (headingTrueRadians != null || headingMagneticRadians != null)) {
        final heading = headingMagneticRadians ?? headingTrueRadians!;
        windDirectionApparentRadians = heading + angleApparentRadians;
      }
      if (angleApparentDegrees != null && (headingTrueDegrees != null || headingMagneticDegrees != null)) {
        final headingDeg = headingMagneticDegrees ?? headingTrueDegrees!;
        windDirectionApparentDegrees = (headingDeg + angleApparentDegrees) % 360;
      }
    }

    // Get wind speed true (optional)
    double? windSpeedTrue;
    String? windSpeedTrueFormatted;
    if (config.dataSources.length > 4) {
      windSpeedTrue = signalKService.getConvertedValue(config.dataSources[4].path);
      windSpeedTrueFormatted = signalKService.getValue(config.dataSources[4].path)?.formatted;
    }

    // Get wind speed apparent (optional)
    double? windSpeedApparent;
    String? windSpeedApparentFormatted;
    if (config.dataSources.length > 5) {
      windSpeedApparent = signalKService.getConvertedValue(config.dataSources[5].path);
      windSpeedApparentFormatted = signalKService.getValue(config.dataSources[5].path)?.formatted;
    }

    // Get speed over ground (optional)
    double? speedOverGround;
    String? sogFormatted;
    if (config.dataSources.length > 6) {
      speedOverGround = signalKService.getConvertedValue(config.dataSources[6].path);
      sogFormatted = signalKService.getValue(config.dataSources[6].path)?.formatted;
    }

    // Get course over ground (optional)
    double? cogDegrees;
    if (config.dataSources.length > 7) {
      cogDegrees = signalKService.getConvertedValue(config.dataSources[7].path);
    }

    // Get style configuration
    final style = config.style;
    final targetAWA = style.laylineAngle ?? 40.0;
    final targetTolerance = style.targetTolerance ?? 3.0;
    final showAWANumbers = style.customProperties?['showAWANumbers'] as bool? ?? true;

    // If no data available, show message
    if (headingTrueRadians == null && headingMagneticRadians == null) {
      return const Center(child: Text('No heading source configured'));
    }

    return WindCompass(
      headingTrueRadians: headingTrueRadians,
      headingMagneticRadians: headingMagneticRadians,
      headingTrueDegrees: headingTrueDegrees,
      headingMagneticDegrees: headingMagneticDegrees,
      windDirectionTrueRadians: windDirectionTrueRadians,
      windDirectionApparentRadians: windDirectionApparentRadians,
      windDirectionTrueDegrees: windDirectionTrueDegrees,
      windDirectionApparentDegrees: windDirectionApparentDegrees,
      windSpeedTrue: windSpeedTrue,
      windSpeedTrueFormatted: windSpeedTrueFormatted,
      windSpeedApparent: windSpeedApparent,
      windSpeedApparentFormatted: windSpeedApparentFormatted,
      speedOverGround: speedOverGround,
      sogFormatted: sogFormatted,
      cogDegrees: cogDegrees,
      targetAWA: targetAWA,
      targetTolerance: targetTolerance,
      showAWANumbers: showAWANumbers,
    );
  }
}

/// Builder for wind compass tools
class WindCompassToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'wind_compass',
      name: 'Wind Compass',
      description: 'Autopilot-style compass showing heading (true/magnetic), wind direction (true/apparent), and speed over ground',
      category: ToolCategory.compass,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 8,
        styleOptions: const [
          'laylineAngle',                        // Target AWA angle in degrees (default: 40)
          'targetTolerance',                     // Acceptable deviation from target in degrees (default: 3)
          'customProperties.showAWANumbers',     // Show numeric AWA display with performance feedback (default: true)
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.headingTrue', label: 'Heading True'),
        DataSource(path: 'navigation.headingMagnetic', label: 'Heading Magnetic'),
        DataSource(path: 'environment.wind.directionTrue', label: 'Wind Direction True'),
        DataSource(path: 'environment.wind.angleApparent', label: 'Wind Angle Apparent'),
        DataSource(path: 'environment.wind.speedTrue', label: 'Wind Speed True'),
        DataSource(path: 'environment.wind.speedApparent', label: 'Wind Speed Apparent'),
        DataSource(path: 'navigation.speedOverGround', label: 'Speed Over Ground'),
        DataSource(path: 'navigation.courseOverGroundTrue', label: 'Course Over Ground'),
      ],
      style: StyleConfig(
        customProperties: {},
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WindCompassTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
