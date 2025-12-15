import 'package:json_annotation/json_annotation.dart';

part 'tool_definition.g.dart';

/// Categories for tool types
enum ToolCategory {
  navigation,    // Helm instruments: compass, autopilot, wind, anchor, position
  instruments,   // Data display: gauges, tanks, text
  charts,        // Time-series: historical, realtime
  weather,       // Forecasts and alerts
  electrical,    // Power systems: Victron flow
  ais,           // AIS and radar
  controls,      // Interactive: switches, sliders, knobs
  communication, // Crew: messages, intercom, file share
  system,        // Admin: server, monitoring, clock
}

/// Configuration schema defining what can be configured
@JsonSerializable()
class ConfigSchema {
  final bool allowsMinMax;        // Can set min/max values
  final bool allowsColorCustomization;
  final bool allowsMultiplePaths; // Can show multiple data sources
  final int minPaths;             // Minimum required paths
  final int maxPaths;             // Maximum allowed paths
  final List<String> styleOptions; // Available style properties

  ConfigSchema({
    this.allowsMinMax = true,
    this.allowsColorCustomization = true,
    this.allowsMultiplePaths = false,
    this.minPaths = 1,
    this.maxPaths = 1,
    this.styleOptions = const [],
  });

  factory ConfigSchema.fromJson(Map<String, dynamic> json) =>
      _$ConfigSchemaFromJson(json);

  Map<String, dynamic> toJson() => _$ConfigSchemaToJson(this);
}

/// Definition of a tool type (e.g., "radial_gauge")
@JsonSerializable()
class ToolDefinition {
  final String id;              // e.g., "radial_gauge"
  final String name;            // e.g., "Radial Gauge"
  final String description;
  final ToolCategory category;
  final ConfigSchema configSchema;

  ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.configSchema,
  });

  factory ToolDefinition.fromJson(Map<String, dynamic> json) =>
      _$ToolDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ToolDefinitionToJson(this);
}
