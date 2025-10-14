import 'package:json_annotation/json_annotation.dart';
import 'tool_instance.dart';

part 'dashboard_screen.g.dart';

/// A single screen/page in the dashboard
@JsonSerializable()
class DashboardScreen {
  final String id;              // Unique screen ID
  final String name;            // Display name (e.g., "Main", "Navigation", "Engine")
  final List<ToolInstance> tools;
  final int order;              // Display order (0-based)

  DashboardScreen({
    required this.id,
    required this.name,
    required this.tools,
    this.order = 0,
  });

  factory DashboardScreen.fromJson(Map<String, dynamic> json) =>
      _$DashboardScreenFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardScreenToJson(this);

  /// Create a copy with modified fields
  DashboardScreen copyWith({
    String? id,
    String? name,
    List<ToolInstance>? tools,
    int? order,
  }) {
    return DashboardScreen(
      id: id ?? this.id,
      name: name ?? this.name,
      tools: tools ?? this.tools,
      order: order ?? this.order,
    );
  }

  /// Add a tool to this screen
  DashboardScreen addTool(ToolInstance tool) {
    return copyWith(tools: [...tools, tool]);
  }

  /// Remove a tool from this screen
  DashboardScreen removeTool(String toolId) {
    return copyWith(
      tools: tools.where((t) => t.id != toolId).toList(),
    );
  }

  /// Update a tool on this screen
  DashboardScreen updateTool(ToolInstance updatedTool) {
    return copyWith(
      tools: tools.map((t) => t.id == updatedTool.id ? updatedTool : t).toList(),
    );
  }
}
