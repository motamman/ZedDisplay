import 'package:json_annotation/json_annotation.dart';
import 'tool_placement.dart';

part 'dashboard_screen.g.dart';

/// A single screen/page in the dashboard
/// Stores lightweight references to tools (placements) rather than full tool data
@JsonSerializable()
class DashboardScreen {
  final String id;              // Unique screen ID
  final String name;            // Display name (e.g., "Main", "Navigation", "Engine")
  final List<ToolPlacement> placements;  // Tool placements on this screen
  final int order;              // Display order (0-based)

  DashboardScreen({
    required this.id,
    required this.name,
    required this.placements,
    this.order = 0,
  });

  factory DashboardScreen.fromJson(Map<String, dynamic> json) =>
      _$DashboardScreenFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardScreenToJson(this);

  /// Create a copy with modified fields
  DashboardScreen copyWith({
    String? id,
    String? name,
    List<ToolPlacement>? placements,
    int? order,
  }) {
    return DashboardScreen(
      id: id ?? this.id,
      name: name ?? this.name,
      placements: placements ?? this.placements,
      order: order ?? this.order,
    );
  }

  /// Add a tool placement to this screen
  DashboardScreen addPlacement(ToolPlacement placement) {
    return copyWith(placements: [...placements, placement]);
  }

  /// Remove a tool placement from this screen
  DashboardScreen removePlacement(String toolId) {
    return copyWith(
      placements: placements.where((p) => p.toolId != toolId).toList(),
    );
  }

  /// Update a tool placement on this screen
  DashboardScreen updatePlacement(ToolPlacement updatedPlacement) {
    return copyWith(
      placements: placements
          .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
          .toList(),
    );
  }

  /// Get all unique tool IDs referenced on this screen
  List<String> getToolIds() {
    return placements.map((p) => p.toolId).toSet().toList();
  }
}
