import 'package:json_annotation/json_annotation.dart';
import 'tool_placement.dart';

part 'dashboard_screen.g.dart';

/// A single screen/page in the dashboard
/// Stores lightweight references to tools (placements) rather than full tool data
@JsonSerializable()
class DashboardScreen {
  final String id;              // Unique screen ID
  final String name;            // Display name (e.g., "Main", "Navigation", "Engine")

  // NEW: Separate layouts for portrait and landscape
  final List<ToolPlacement> portraitPlacements;   // Tools in portrait mode
  final List<ToolPlacement> landscapePlacements;  // Tools in landscape mode

  // Allow widgets to extend beyond screen (enables vertical scrolling)
  final bool allowOverflow;

  // DEPRECATED: Old single placement list (kept for backward compatibility)
  final List<ToolPlacement>? placements;

  final int order;              // Display order (0-based)

  DashboardScreen({
    required this.id,
    required this.name,
    List<ToolPlacement>? portraitPlacements,
    List<ToolPlacement>? landscapePlacements,
    this.allowOverflow = false,
    this.placements,  // Deprecated
    this.order = 0,
  }) : portraitPlacements = portraitPlacements ?? placements ?? [],
       landscapePlacements = landscapePlacements ?? placements ?? [];

  factory DashboardScreen.fromJson(Map<String, dynamic> json) =>
      _$DashboardScreenFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardScreenToJson(this);

  /// Create a copy with modified fields
  DashboardScreen copyWith({
    String? id,
    String? name,
    List<ToolPlacement>? portraitPlacements,
    List<ToolPlacement>? landscapePlacements,
    bool? allowOverflow,
    int? order,
  }) {
    return DashboardScreen(
      id: id ?? this.id,
      name: name ?? this.name,
      portraitPlacements: portraitPlacements ?? this.portraitPlacements,
      landscapePlacements: landscapePlacements ?? this.landscapePlacements,
      allowOverflow: allowOverflow ?? this.allowOverflow,
      order: order ?? this.order,
    );
  }

  /// Add a tool placement to this screen (to both orientations by default)
  DashboardScreen addPlacement(ToolPlacement placement, {bool portrait = true, bool landscape = true}) {
    return copyWith(
      portraitPlacements: portrait ? [...portraitPlacements, placement] : portraitPlacements,
      landscapePlacements: landscape ? [...landscapePlacements, placement] : landscapePlacements,
    );
  }

  /// Remove a tool placement from this screen (from both orientations)
  DashboardScreen removePlacement(String toolId) {
    return copyWith(
      portraitPlacements: portraitPlacements.where((p) => p.toolId != toolId).toList(),
      landscapePlacements: landscapePlacements.where((p) => p.toolId != toolId).toList(),
    );
  }

  /// Update a tool placement on this screen (in both orientations)
  DashboardScreen updatePlacement(ToolPlacement updatedPlacement, {bool portrait = true, bool landscape = true}) {
    return copyWith(
      portraitPlacements: portrait
          ? portraitPlacements.map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p).toList()
          : portraitPlacements,
      landscapePlacements: landscape
          ? landscapePlacements.map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p).toList()
          : landscapePlacements,
    );
  }

  /// Get all unique tool IDs referenced on this screen (from both orientations)
  List<String> getToolIds() {
    final allIds = <String>{};
    allIds.addAll(portraitPlacements.map((p) => p.toolId));
    allIds.addAll(landscapePlacements.map((p) => p.toolId));
    return allIds.toList();
  }
}
