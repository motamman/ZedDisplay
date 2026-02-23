import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/conversion_utils.dart';
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
    // 8: navigation.courseGreatCircle.nextPoint.bearingTrue (optional) - waypoint bearing in RADIANS
    // 9: navigation.courseGreatCircle.nextPoint.distance (optional) - waypoint distance in meters

    // Get heading true (optional) - need raw radians for rotation, converted for display
    double? headingTrueRadians;
    double? headingTrueDegrees;
    if (config.dataSources.isNotEmpty) {
      headingTrueRadians = ConversionUtils.getRawValue(signalKService, config.dataSources[0].path);
      headingTrueDegrees = ConversionUtils.getConvertedValue(signalKService, config.dataSources[0].path);
    }

    // Get heading magnetic (optional) - need raw radians for rotation, converted for display
    double? headingMagneticRadians;
    double? headingMagneticDegrees;
    if (config.dataSources.length > 1) {
      headingMagneticRadians = ConversionUtils.getRawValue(signalKService, config.dataSources[1].path);
      headingMagneticDegrees = ConversionUtils.getConvertedValue(signalKService, config.dataSources[1].path);
    }

    // Get wind direction true (optional) - need raw radians for rotation, converted for display
    double? windDirectionTrueRadians;
    double? windDirectionTrueDegrees;
    String? windDirectionTrueFormatted;
    if (config.dataSources.length > 2) {
      windDirectionTrueRadians = ConversionUtils.getRawValue(signalKService, config.dataSources[2].path);
      windDirectionTrueDegrees = ConversionUtils.getConvertedValue(signalKService, config.dataSources[2].path);
      if (windDirectionTrueRadians != null) {
        windDirectionTrueFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[2].path, windDirectionTrueRadians);
      }
    }

    // Get wind angle apparent (relative to boat) - need raw for calculations
    double? windDirectionApparentRadians;
    double? windDirectionApparentDegrees;
    double? windAngleApparent;
    String? windAngleApparentFormatted;
    String? windDirectionApparentFormatted;
    if (config.dataSources.length > 3) {
      final angleApparentRadians = ConversionUtils.getRawValue(signalKService, config.dataSources[3].path);
      final angleApparentDegrees = ConversionUtils.getConvertedValue(signalKService, config.dataSources[3].path);

      windAngleApparent = angleApparentDegrees;
      if (angleApparentRadians != null) {
        windAngleApparentFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[3].path, angleApparentRadians);
      }

      // Convert relative angle to absolute direction
      if (angleApparentRadians != null && (headingTrueRadians != null || headingMagneticRadians != null)) {
        final heading = headingMagneticRadians ?? headingTrueRadians!;
        windDirectionApparentRadians = heading + angleApparentRadians;
      }
      if (angleApparentDegrees != null && (headingTrueDegrees != null || headingMagneticDegrees != null)) {
        final headingDeg = headingMagneticDegrees ?? headingTrueDegrees!;
        windDirectionApparentDegrees = (headingDeg + angleApparentDegrees) % 360;
        // Format the computed apparent direction
        windDirectionApparentFormatted = '${windDirectionApparentDegrees.toStringAsFixed(0)}°';
      }
    }

    // Get wind speed true (optional) - always use converted
    double? windSpeedTrue;
    String? windSpeedTrueFormatted;
    if (config.dataSources.length > 4) {
      windSpeedTrue = ConversionUtils.getConvertedValue(signalKService, config.dataSources[4].path);
      final rawSpeed = ConversionUtils.getRawValue(signalKService, config.dataSources[4].path);
      if (rawSpeed != null) {
        windSpeedTrueFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[4].path, rawSpeed);
      }
    }

    // Get wind speed apparent (optional) - always use converted
    double? windSpeedApparent;
    String? windSpeedApparentFormatted;
    if (config.dataSources.length > 5) {
      windSpeedApparent = ConversionUtils.getConvertedValue(signalKService, config.dataSources[5].path);
      final rawSpeed = ConversionUtils.getRawValue(signalKService, config.dataSources[5].path);
      if (rawSpeed != null) {
        windSpeedApparentFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[5].path, rawSpeed);
      }
    }

    // Get speed over ground (optional) - always use converted
    double? speedOverGround;
    String? sogFormatted;
    if (config.dataSources.length > 6) {
      speedOverGround = ConversionUtils.getConvertedValue(signalKService, config.dataSources[6].path);
      final rawSpeed = ConversionUtils.getRawValue(signalKService, config.dataSources[6].path);
      if (rawSpeed != null) {
        sogFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[6].path, rawSpeed);
      }
    }

    // Get course over ground (optional) - always use converted
    double? cogDegrees;
    String? cogFormatted;
    if (config.dataSources.length > 7) {
      cogDegrees = ConversionUtils.getConvertedValue(signalKService, config.dataSources[7].path);
      final rawCog = ConversionUtils.getRawValue(signalKService, config.dataSources[7].path);
      if (rawCog != null) {
        cogFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[7].path, rawCog);
      }
    }

    // Get waypoint bearing (optional) - always use converted
    double? waypointBearing;
    String? waypointBearingFormatted;
    if (config.dataSources.length > 8) {
      waypointBearing = ConversionUtils.getConvertedValue(signalKService, config.dataSources[8].path);
      final rawBearing = ConversionUtils.getRawValue(signalKService, config.dataSources[8].path);
      if (rawBearing != null) {
        waypointBearingFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[8].path, rawBearing);
      }
    }

    // Get waypoint distance (optional) - always use converted
    double? waypointDistance;
    String? waypointDistanceFormatted;
    if (config.dataSources.length > 9) {
      waypointDistance = ConversionUtils.getConvertedValue(signalKService, config.dataSources[9].path);
      final rawDistance = ConversionUtils.getRawValue(signalKService, config.dataSources[9].path);
      if (rawDistance != null) {
        waypointDistanceFormatted = ConversionUtils.formatValue(signalKService, config.dataSources[9].path, rawDistance);
      }
    }

    // Get style configuration
    final style = config.style;
    final targetAWA = style.laylineAngle ?? 40.0;
    final targetTolerance = style.targetTolerance ?? 3.0;
    final showAWANumbers = style.customProperties?['showAWANumbers'] as bool? ?? true;
    final enableVMG = style.customProperties?['enableVMG'] as bool? ?? false;

    // Vessel type detection for sail trim indicator
    bool isSailingVessel = true; // Default to true for wind compass
    final vesselTypeData = signalKService.getValue('design.aisShipType');
    if (vesselTypeData?.value != null) {
      final vesselType = vesselTypeData!.value;
      if (vesselType is Map) {
        final name = vesselType['name']?.toString().toLowerCase() ?? '';
        final id = vesselType['id'];
        isSailingVessel = name.contains('sail') || id == 36;
      } else if (vesselType is num) {
        isSailingVessel = vesselType == 36;
      }
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
      windDirectionTrueFormatted: windDirectionTrueFormatted,
      windDirectionApparentFormatted: windDirectionApparentFormatted,
      windAngleApparent: windAngleApparent,
      windAngleApparentFormatted: windAngleApparentFormatted,
      windSpeedTrue: windSpeedTrue,
      windSpeedTrueFormatted: windSpeedTrueFormatted,
      windSpeedApparent: windSpeedApparent,
      windSpeedApparentFormatted: windSpeedApparentFormatted,
      speedOverGround: speedOverGround,
      sogFormatted: sogFormatted,
      cogDegrees: cogDegrees,
      cogFormatted: cogFormatted,
      waypointBearing: waypointBearing,
      waypointBearingFormatted: waypointBearingFormatted,
      waypointDistance: waypointDistance,
      waypointDistanceFormatted: waypointDistanceFormatted,
      targetAWA: targetAWA,
      targetTolerance: targetTolerance,
      showAWANumbers: showAWANumbers,
      enableVMG: enableVMG,
      isSailingVessel: isSailingVessel,
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
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 10,
        styleOptions: const [
          'laylineAngle',                        // Target AWA angle in degrees (default: 40) - overridden by VMG if enabled
          'targetTolerance',                     // Acceptable deviation from target in degrees (default: 3)
          'customProperties.showAWANumbers',     // Show numeric AWA display with performance feedback (default: true)
          'customProperties.enableVMG',          // Enable VMG optimization with polar-based dynamic target AWA (default: false)
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
        DataSource(path: 'navigation.courseGreatCircle.nextPoint.bearingTrue', label: 'Waypoint Bearing'),
        DataSource(path: 'navigation.courseGreatCircle.nextPoint.distance', label: 'Waypoint Distance'),
      ],
      style: StyleConfig(
        laylineAngle: 40.0,
        targetTolerance: 3.0,
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
