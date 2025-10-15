import 'package:json_annotation/json_annotation.dart';

part 'tool_config.g.dart';

/// Data source configuration for a tool
@JsonSerializable()
class DataSource {
  final String path;            // e.g., "navigation.speedOverGround"
  final String? source;         // Optional: specific source (e.g., "signalk-mqtt-import.GP")
  final String? label;          // Display label override
  final String? color;          // For multi-path tools (hex color string)

  DataSource({
    required this.path,
    this.source,
    this.label,
    this.color,
  });

  factory DataSource.fromJson(Map<String, dynamic> json) =>
      _$DataSourceFromJson(json);

  Map<String, dynamic> toJson() => _$DataSourceToJson(this);
}

/// Style configuration for a tool
@JsonSerializable()
class StyleConfig {
  final double? minValue;
  final double? maxValue;
  final String? unit;            // Unit override (use server's unit if null)
  final String? primaryColor;    // Hex color string (e.g., "#0000FF")
  final String? secondaryColor;
  final double? fontSize;
  final double? strokeWidth;
  final bool? showLabel;
  final bool? showValue;
  final bool? showUnit;

  // Windsteer-specific options
  final double? laylineAngle;    // Close-hauled layline angle (degrees)
  final bool? showLaylines;      // Show laylines
  final bool? showTrueWind;      // Show true wind indicator
  final bool? showCOG;           // Show course over ground
  final bool? showAWS;           // Show apparent wind speed
  final bool? showTWS;           // Show true wind speed

  // Additional style properties for specific tools
  final Map<String, dynamic>? customProperties;

  StyleConfig({
    this.minValue,
    this.maxValue,
    this.unit,
    this.primaryColor,
    this.secondaryColor,
    this.fontSize,
    this.strokeWidth,
    this.showLabel = true,
    this.showValue = true,
    this.showUnit = true,
    this.laylineAngle,
    this.showLaylines,
    this.showTrueWind,
    this.showCOG,
    this.showAWS,
    this.showTWS,
    this.customProperties,
  });

  factory StyleConfig.fromJson(Map<String, dynamic> json) =>
      _$StyleConfigFromJson(json);

  Map<String, dynamic> toJson() => _$StyleConfigToJson(this);
}

/// Grid position for layout
@JsonSerializable()
class GridPosition {
  final int row;
  final int col;
  final int width;   // Columns to span
  final int height;  // Rows to span

  GridPosition({
    required this.row,
    required this.col,
    this.width = 1,
    this.height = 1,
  });

  factory GridPosition.fromJson(Map<String, dynamic> json) =>
      _$GridPositionFromJson(json);

  Map<String, dynamic> toJson() => _$GridPositionToJson(this);
}

/// Configuration for a tool instance
@JsonSerializable()
class ToolConfig {
  final String? vesselId;       // Optional: specific vessel (null = self)
  final List<DataSource> dataSources;
  final StyleConfig style;

  ToolConfig({
    this.vesselId,
    required this.dataSources,
    required this.style,
  });

  factory ToolConfig.fromJson(Map<String, dynamic> json) =>
      _$ToolConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ToolConfigToJson(this);
}
