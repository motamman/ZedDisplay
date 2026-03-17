import 'package:flutter/material.dart';
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

/// Extension to provide display properties for categories
extension ToolCategoryExtension on ToolCategory {
  String get displayName {
    switch (this) {
      case ToolCategory.navigation:
        return 'Navigation';
      case ToolCategory.instruments:
        return 'Instruments';
      case ToolCategory.charts:
        return 'Charts';
      case ToolCategory.weather:
        return 'Weather';
      case ToolCategory.electrical:
        return 'Electrical';
      case ToolCategory.ais:
        return 'AIS';
      case ToolCategory.controls:
        return 'Controls';
      case ToolCategory.communication:
        return 'Communication';
      case ToolCategory.system:
        return 'System';
    }
  }

  IconData get icon {
    switch (this) {
      case ToolCategory.navigation:
        return Icons.explore;
      case ToolCategory.instruments:
        return Icons.speed;
      case ToolCategory.charts:
        return Icons.show_chart;
      case ToolCategory.weather:
        return Icons.cloud;
      case ToolCategory.electrical:
        return Icons.bolt;
      case ToolCategory.ais:
        return Icons.radar;
      case ToolCategory.controls:
        return Icons.toggle_on;
      case ToolCategory.communication:
        return Icons.chat;
      case ToolCategory.system:
        return Icons.settings;
    }
  }

  Color get color {
    switch (this) {
      case ToolCategory.navigation:
        return Colors.blue;
      case ToolCategory.instruments:
        return Colors.teal;
      case ToolCategory.charts:
        return Colors.purple;
      case ToolCategory.weather:
        return Colors.lightBlue;
      case ToolCategory.electrical:
        return Colors.amber;
      case ToolCategory.ais:
        return Colors.red;
      case ToolCategory.controls:
        return Colors.green;
      case ToolCategory.communication:
        return Colors.indigo;
      case ToolCategory.system:
        return Colors.grey;
    }
  }
}

/// Defines a fixed data-source slot for tools with positional indexing.
/// When a tool's ConfigSchema has slotDefinitions, the config screen enters
/// "slot mode": fixed-length list, no add/delete, path editing enabled.
class SlotDefinition {
  final String roleLabel;     // e.g. "Speed Over Ground"
  final String? defaultPath;  // e.g. "navigation.speedOverGround"
  final bool required;        // false = user can clear the slot

  const SlotDefinition({
    required this.roleLabel,
    this.defaultPath,
    this.required = false,
  });
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

  /// When non-null, the config screen uses fixed slots instead of add/delete.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<SlotDefinition>? slotDefinitions;

  /// Whether the tool shows the Data Sources configuration card.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsDataSources;

  /// Whether the tool shows the Style configuration card.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsStyleConfig;

  /// Whether the tool shows the Unit text field in style options.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsUnitSelection;

  /// Whether the tool shows the secondary color picker.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsSecondaryColor;

  /// Whether the tool shows Show Label/Value/Unit toggles.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsVisibilityToggles;

  /// Whether the tool shows the TTL dropdown.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool allowsTTL;

  ConfigSchema({
    this.allowsMinMax = true,
    this.allowsColorCustomization = true,
    this.allowsMultiplePaths = false,
    this.minPaths = 1,
    this.maxPaths = 1,
    this.styleOptions = const [],
    this.slotDefinitions,
    this.allowsDataSources = true,
    this.allowsStyleConfig = true,
    this.allowsUnitSelection = true,
    this.allowsSecondaryColor = false,
    this.allowsVisibilityToggles = true,
    this.allowsTTL = true,
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
  final int defaultWidth;       // Default grid width
  final int defaultHeight;      // Default grid height

  ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.configSchema,
    this.defaultWidth = 20,
    this.defaultHeight = 20,
  });

  factory ToolDefinition.fromJson(Map<String, dynamic> json) =>
      _$ToolDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ToolDefinitionToJson(this);
}
