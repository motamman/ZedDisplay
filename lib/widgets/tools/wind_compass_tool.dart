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
    // 2: environment.wind.directionTrue (optional) - in RADIANS from SignalK
    // 3: environment.wind.angleApparent (optional) - in RADIANS from SignalK
    // 4: navigation.speedOverGround (optional)
    // 5: navigation.courseOverGroundTrue (optional) - in DEGREES

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

    // Get wind direction apparent (optional) - use original radians value
    double? windDirectionApparentRadians;
    double? windDirectionApparentDegrees;
    if (config.dataSources.length > 3) {
      final dataPoint = signalKService.getValue(config.dataSources[3].path);
      windDirectionApparentRadians = dataPoint?.original is num ? (dataPoint!.original as num).toDouble() : null;
      windDirectionApparentDegrees = signalKService.getConvertedValue(config.dataSources[3].path);
    }

    // Get speed over ground (optional)
    double? speedOverGround;
    String? sogFormatted;
    if (config.dataSources.length > 4) {
      speedOverGround = signalKService.getConvertedValue(config.dataSources[4].path);
      sogFormatted = signalKService.getValue(config.dataSources[4].path)?.formatted;
    }

    // Get course over ground (optional)
    double? cogDegrees;
    if (config.dataSources.length > 5) {
      cogDegrees = signalKService.getConvertedValue(config.dataSources[5].path);
    }

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
      speedOverGround: speedOverGround,
      sogFormatted: sogFormatted,
      cogDegrees: cogDegrees,
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
        maxPaths: 6,
        styleOptions: const [],
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
        DataSource(path: 'environment.wind.angleApparent', label: 'Wind Direction Apparent'),
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
