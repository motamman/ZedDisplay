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
  final int? ttlSeconds;         // Data staleness threshold in seconds (null = no check)

  // Windsteer-specific options
  final double? laylineAngle;    // Target AWA angle in degrees (default: 40)
  final double? targetTolerance; // Acceptable deviation from target AWA in degrees (default: 3)
  final bool? showLaylines;      // Show target AWA lines
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
    this.ttlSeconds,
    this.laylineAngle,
    this.targetTolerance,
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

/// Grid position for layout (DEPRECATED - kept for backward compatibility)
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

  GridPosition copyWith({
    int? row,
    int? col,
    int? width,
    int? height,
  }) {
    return GridPosition(
      row: row ?? this.row,
      col: col ?? this.col,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Pixel-based position for layout (replaces GridPosition)
@JsonSerializable()
class PixelPosition {
  final double x;        // X position in pixels
  final double y;        // Y position in pixels
  final double width;    // Width in pixels
  final double height;   // Height in pixels

  PixelPosition({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory PixelPosition.fromJson(Map<String, dynamic> json) =>
      _$PixelPositionFromJson(json);

  Map<String, dynamic> toJson() => _$PixelPositionToJson(this);

  PixelPosition copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return PixelPosition(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Check if position is within screen bounds
  bool fitsInBounds(double screenWidth, double screenHeight) {
    return x >= 0 &&
           y >= 0 &&
           (x + width) <= screenWidth &&
           (y + height) <= screenHeight;
  }

  /// Clamp position to fit within screen bounds
  PixelPosition clampToBounds(double screenWidth, double screenHeight) {
    final clampedWidth = width.clamp(0, screenWidth).toDouble();
    final clampedHeight = height.clamp(0, screenHeight).toDouble();
    final clampedX = x.clamp(0, screenWidth - clampedWidth).toDouble();
    final clampedY = y.clamp(0, screenHeight - clampedHeight).toDouble();

    return PixelPosition(
      x: clampedX,
      y: clampedY,
      width: clampedWidth,
      height: clampedHeight,
    );
  }
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
