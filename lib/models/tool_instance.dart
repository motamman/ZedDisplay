import 'package:json_annotation/json_annotation.dart';
import 'tool_config.dart';

part 'tool_instance.g.dart';

/// An instance of a tool on a dashboard
@JsonSerializable()
class ToolInstance {
  final String id;              // Unique instance ID (UUID)
  final String toolTypeId;      // References ToolDefinition (e.g., "radial_gauge")
  final ToolConfig config;      // User's configuration
  final String screenId;        // Which screen it's on
  final GridPosition position;  // Where on screen

  ToolInstance({
    required this.id,
    required this.toolTypeId,
    required this.config,
    required this.screenId,
    required this.position,
  });

  factory ToolInstance.fromJson(Map<String, dynamic> json) =>
      _$ToolInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$ToolInstanceToJson(this);

  /// Create a copy with modified fields
  ToolInstance copyWith({
    String? id,
    String? toolTypeId,
    ToolConfig? config,
    String? screenId,
    GridPosition? position,
  }) {
    return ToolInstance(
      id: id ?? this.id,
      toolTypeId: toolTypeId ?? this.toolTypeId,
      config: config ?? this.config,
      screenId: screenId ?? this.screenId,
      position: position ?? this.position,
    );
  }
}
