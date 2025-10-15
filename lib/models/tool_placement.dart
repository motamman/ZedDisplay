import 'package:json_annotation/json_annotation.dart';
import 'tool_config.dart';

part 'tool_placement.g.dart';

/// A lightweight reference to a tool placed on a dashboard screen
/// This separates the reusable tool from where it's positioned
@JsonSerializable()
class ToolPlacement {
  final String toolId;          // References Tool.id
  final String screenId;        // Which screen it's on
  final GridPosition position;  // Where on screen

  ToolPlacement({
    required this.toolId,
    required this.screenId,
    required this.position,
  });

  factory ToolPlacement.fromJson(Map<String, dynamic> json) =>
      _$ToolPlacementFromJson(json);

  Map<String, dynamic> toJson() => _$ToolPlacementToJson(this);

  /// Create a copy with modified fields
  ToolPlacement copyWith({
    String? toolId,
    String? screenId,
    GridPosition? position,
  }) {
    return ToolPlacement(
      toolId: toolId ?? this.toolId,
      screenId: screenId ?? this.screenId,
      position: position ?? this.position,
    );
  }
}
