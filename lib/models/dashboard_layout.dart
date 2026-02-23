import 'package:json_annotation/json_annotation.dart';
import 'dashboard_screen.dart';

part 'dashboard_layout.g.dart';

/// Complete dashboard layout with multiple screens
@JsonSerializable()
class DashboardLayout {
  final String id;              // Unique layout ID
  final String name;            // Display name (e.g., "Default", "Sailing", "Motorsailing")
  final String? intendedUse;    // Optional: "Phone", "Tablet", "Desktop", or custom string
  final List<DashboardScreen> screens;
  final int activeScreenIndex;  // Currently active screen (0-based)

  DashboardLayout({
    required this.id,
    required this.name,
    this.intendedUse,
    required this.screens,
    this.activeScreenIndex = 0,
  });

  factory DashboardLayout.fromJson(Map<String, dynamic> json) =>
      _$DashboardLayoutFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardLayoutToJson(this);

  /// Create a copy with modified fields
  DashboardLayout copyWith({
    String? id,
    String? name,
    String? intendedUse,
    bool clearIntendedUse = false,
    List<DashboardScreen>? screens,
    int? activeScreenIndex,
  }) {
    return DashboardLayout(
      id: id ?? this.id,
      name: name ?? this.name,
      intendedUse: clearIntendedUse ? null : (intendedUse ?? this.intendedUse),
      screens: screens ?? this.screens,
      activeScreenIndex: activeScreenIndex ?? this.activeScreenIndex,
    );
  }

  /// Get the currently active screen
  DashboardScreen? get activeScreen {
    if (activeScreenIndex >= 0 && activeScreenIndex < screens.length) {
      return screens[activeScreenIndex];
    }
    return null;
  }

  /// Add a screen to this layout
  DashboardLayout addScreen(DashboardScreen screen) {
    return copyWith(screens: [...screens, screen]);
  }

  /// Remove a screen from this layout
  DashboardLayout removeScreen(String screenId) {
    return copyWith(
      screens: screens.where((s) => s.id != screenId).toList(),
    );
  }

  /// Update a screen in this layout
  DashboardLayout updateScreen(DashboardScreen updatedScreen) {
    return copyWith(
      screens: screens.map((s) => s.id == updatedScreen.id ? updatedScreen : s).toList(),
    );
  }

  /// Set the active screen by index
  DashboardLayout setActiveScreen(int index) {
    if (index >= 0 && index < screens.length) {
      return copyWith(activeScreenIndex: index);
    }
    return this;
  }

  /// Set the active screen by ID
  DashboardLayout setActiveScreenById(String screenId) {
    final index = screens.indexWhere((s) => s.id == screenId);
    if (index >= 0) {
      return copyWith(activeScreenIndex: index);
    }
    return this;
  }

  /// Get all unique tool IDs referenced across all screens
  List<String> getAllToolIds() {
    final toolIds = <String>{};

    for (final screen in screens) {
      toolIds.addAll(screen.getToolIds());
    }

    return toolIds.toList();
  }

  /// Reorder screens by moving from oldIndex to newIndex
  /// Adjusts activeScreenIndex to follow the currently active screen
  DashboardLayout reorderScreens(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= screens.length ||
        newIndex < 0 || newIndex >= screens.length ||
        oldIndex == newIndex) {
      return this;
    }

    // Track active screen by ID so it follows the move
    final activeScreenId = activeScreen?.id;

    // Create mutable copy and reorder
    final newScreens = List<DashboardScreen>.from(screens);
    final movedScreen = newScreens.removeAt(oldIndex);
    newScreens.insert(newIndex, movedScreen);

    // Find new index of active screen
    int newActiveIndex = activeScreenIndex;
    if (activeScreenId != null) {
      newActiveIndex = newScreens.indexWhere((s) => s.id == activeScreenId);
      if (newActiveIndex < 0) newActiveIndex = 0;
    }

    return copyWith(screens: newScreens, activeScreenIndex: newActiveIndex);
  }
}
