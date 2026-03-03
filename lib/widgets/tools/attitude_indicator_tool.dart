import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../attitude_indicator.dart';

/// Config-driven attitude/heel indicator tool
class AttitudeIndicatorTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AttitudeIndicatorTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    // Expected data sources (in order):
    // 0: navigation.attitude.roll - roll angle in radians
    // 1: navigation.attitude.pitch - pitch angle in radians

    // Get configuration
    final style = config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.orange,
    ) ?? Colors.orange;

    // Get custom properties
    final showDigitalValues = style.customProperties?['showDigitalValues'] as bool? ?? true;
    final showGrid = style.customProperties?['showGrid'] as bool? ?? true;
    final maxPitch = (style.customProperties?['maxPitch'] as num?)?.toDouble() ?? 30.0;
    final maxRoll = (style.customProperties?['maxRoll'] as num?)?.toDouble() ?? 45.0;

    // Get attitude path - single object containing roll, pitch, yaw
    final attitudePath = config.dataSources.isNotEmpty
        ? config.dataSources[0].path
        : 'navigation.attitude';

    // Get attitude object and extract roll/pitch
    double? rollDegrees;
    double? pitchDegrees;

    final attitudeData = signalKService.getValue(attitudePath);
    if (attitudeData?.value is Map) {
      final attitude = attitudeData!.value as Map<String, dynamic>;

      // Roll is in radians, convert to degrees using MetadataStore (single source of truth)
      if (attitude['roll'] is num) {
        final rollRaw = (attitude['roll'] as num).toDouble();
        final rollMetadata = signalKService.metadataStore.get('$attitudePath.roll');
        rollDegrees = rollMetadata?.convert(rollRaw) ?? rollRaw * 180 / math.pi;
      }

      // Pitch is in radians, convert to degrees using MetadataStore (single source of truth)
      if (attitude['pitch'] is num) {
        final pitchRaw = (attitude['pitch'] as num).toDouble();
        final pitchMetadata = signalKService.metadataStore.get('$attitudePath.pitch');
        pitchDegrees = pitchMetadata?.convert(pitchRaw) ?? pitchRaw * 180 / math.pi;
      }
    }

    return AttitudeIndicator(
      rollDegrees: rollDegrees,
      pitchDegrees: pitchDegrees,
      showDigitalValues: showDigitalValues,
      showGrid: showGrid,
      primaryColor: primaryColor,
      maxPitch: maxPitch,
      maxRoll: maxRoll,
    );
  }
}

/// Builder for attitude indicator tool
class AttitudeIndicatorToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'attitude_indicator',
      name: 'Attitude Indicator',
      description: 'Artificial horizon showing roll (heel) and pitch with boat silhouette',
      category: ToolCategory.navigation,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',
          'showDigitalValues',
          'showGrid',
          'maxPitch',
          'maxRoll',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.attitude', label: 'Attitude'),
      ],
      style: StyleConfig(
        customProperties: {
          'showDigitalValues': true,
          'showGrid': true,
          'maxPitch': 30.0,
          'maxRoll': 45.0,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AttitudeIndicatorTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
