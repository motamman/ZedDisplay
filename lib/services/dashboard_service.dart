import 'package:flutter/foundation.dart';
import '../models/dashboard_layout.dart';
import '../models/dashboard_screen.dart';
import '../models/tool_placement.dart';
import 'storage_service.dart';
import 'signalk_service.dart';
import 'tool_service.dart';

/// Service for managing dashboard layouts and screens
class DashboardService extends ChangeNotifier {
  final StorageService _storageService;
  final SignalKService? _signalKService;
  final ToolService? _toolService;

  DashboardLayout? _currentLayout;
  bool _initialized = false;

  DashboardService(
    this._storageService, [
    this._signalKService,
    this._toolService,
  ]);

  DashboardLayout? get currentLayout => _currentLayout;
  bool get initialized => _initialized;

  /// Initialize and load the active dashboard
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Try to load the active dashboard
      final activeDashboardId = _storageService.getActiveDashboardId();
      if (activeDashboardId != null) {
        _currentLayout = await _storageService.loadDashboard(activeDashboardId);
      }

      // If no active dashboard, try to load the default
      _currentLayout ??= await _storageService.getDefaultDashboard();

      // If still no dashboard, create a default one
      if (_currentLayout == null) {
        _currentLayout = DashboardLayout(
          id: 'layout_default',
          name: 'Default Dashboard',
          screens: [
            DashboardScreen(
              id: 'screen_main',
              name: 'Main',
              placements: [],
              order: 0,
            ),
          ],
          activeScreenIndex: 0,
        );

        await saveDashboard();

        if (kDebugMode) {
          print('Created default dashboard on first install');
        }
      }

      _initialized = true;
      notifyListeners();

      // Don't subscribe yet - SignalK isn't connected at this point
      // Subscription will happen after connection in ConnectionScreen

      if (kDebugMode) {
        print('DashboardService initialized with ${_currentLayout!.screens.length} screens');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing DashboardService: $e');
      }
      rethrow;
    }
  }

  /// Update SignalK subscriptions based on current dashboard
  Future<void> _updateSignalKSubscriptions() async {
    if (_currentLayout == null || _signalKService == null || _toolService == null) return;

    // Get all tool IDs from the dashboard
    final toolIds = _currentLayout!.getAllToolIds();

    // Resolve tool IDs to required paths
    final requiredPaths = _toolService.getRequiredPathsForTools(toolIds);

    if (requiredPaths.isNotEmpty) {
      await _signalKService.setActiveTemplatePaths(requiredPaths);

      if (kDebugMode) {
        print('Updated SignalK subscriptions: ${requiredPaths.length} paths from ${toolIds.length} tools');
      }
    }
  }

  /// Save the current dashboard layout
  Future<void> saveDashboard() async {
    if (_currentLayout == null) return;

    try {
      await _storageService.saveDashboard(_currentLayout!);
      await _storageService.saveActiveDashboardId(_currentLayout!.id);

    } catch (e) {
      if (kDebugMode) {
        print('Error saving dashboard: $e');
      }
      rethrow;
    }
  }

  /// Update the current layout
  Future<void> updateLayout(DashboardLayout layout) async {
    _currentLayout = layout;
    notifyListeners();
    await _updateSignalKSubscriptions();
    await saveDashboard();
  }

  /// Add a screen to the current layout
  Future<void> addScreen({String? name}) async {
    if (_currentLayout == null) return;

    final screenName = name ?? 'Screen ${_currentLayout!.screens.length + 1}';
    final newScreen = DashboardScreen(
      id: 'screen_${DateTime.now().millisecondsSinceEpoch}',
      name: screenName,
      placements: [],
      order: _currentLayout!.screens.length,
    );

    _currentLayout = _currentLayout!.addScreen(newScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Create a new blank dashboard
  Future<void> createNewDashboard() async {
    _currentLayout = DashboardLayout(
      id: 'layout_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Dashboard',
      screens: [
        DashboardScreen(
          id: 'screen_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Main',
          placements: [],
          order: 0,
        ),
      ],
      activeScreenIndex: 0,
    );

    notifyListeners();
    await saveDashboard();

    if (kDebugMode) {
      print('Created new blank dashboard');
    }
  }

  /// Remove a screen from the current layout
  Future<void> removeScreen(String screenId) async {
    if (_currentLayout == null) return;
    if (_currentLayout!.screens.length <= 1) {
      // Can't remove the last screen
      return;
    }

    _currentLayout = _currentLayout!.removeScreen(screenId);
    notifyListeners();
    await saveDashboard();
  }

  /// Rename a screen
  Future<void> renameScreen(String screenId, String newName) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    final updatedScreen = screen.copyWith(name: newName);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Set the active screen by index
  void setActiveScreen(int index) {
    if (_currentLayout == null) return;

    _currentLayout = _currentLayout!.setActiveScreen(index);
    notifyListeners();
  }

  /// Add a tool placement to the screen specified in the placement
  /// Note: Uses the placement's screenId to determine which screen to add to
  Future<void> addPlacementToActiveScreen(ToolPlacement placement) async {
    if (_currentLayout == null) {
      print('❌ addPlacementToActiveScreen: No current layout');
      return;
    }

    print('📍 addPlacementToActiveScreen: Adding placement ${placement.toolId} to screen ${placement.screenId}');

    // Find the screen specified in the placement (not necessarily the active screen)
    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == placement.screenId,
      orElse: () => throw Exception('Screen not found: ${placement.screenId}'),
    );

    print('📍 addPlacementToActiveScreen: Found screen ${screen.id}, current placements: portrait=${screen.portraitPlacements.length}, landscape=${screen.landscapePlacements.length}');

    final updatedScreen = screen.addPlacement(placement);

    print('📍 addPlacementToActiveScreen: Updated screen placements: portrait=${updatedScreen.portraitPlacements.length}, landscape=${updatedScreen.landscapePlacements.length}');

    _currentLayout = _currentLayout!.updateScreen(updatedScreen);

    print('📍 addPlacementToActiveScreen: Calling notifyListeners()');
    notifyListeners();

    await _updateSignalKSubscriptions();
    await saveDashboard();

    print('✅ addPlacementToActiveScreen: Complete');

    // Increment tool usage count
    if (_toolService != null) {
      await _toolService.incrementUsage(placement.toolId);
    }
  }

  /// Remove a tool placement from a screen
  Future<void> removePlacement(String screenId, String toolId) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    final updatedScreen = screen.removePlacement(toolId);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _updateSignalKSubscriptions();
    await saveDashboard();
  }

  /// Update a tool placement on a screen
  Future<void> updatePlacement(String screenId, ToolPlacement placement) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    final updatedScreen = screen.updatePlacement(placement);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await _updateSignalKSubscriptions();
    await saveDashboard();
  }

  /// Update a screen directly (for orientation-specific edits)
  Future<void> updateScreen(DashboardScreen updatedScreen) async {
    if (_currentLayout == null) return;

    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Update just the size of a placement
  Future<void> updatePlacementSize(
    String screenId,
    String toolId,
    int width,
    int height,
  ) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    // Try to find in portrait placements first
    final placements = screen.portraitPlacements.isNotEmpty
        ? screen.portraitPlacements
        : screen.landscapePlacements;

    final placement = placements.firstWhere(
      (p) => p.toolId == toolId,
      orElse: () => throw Exception('Placement not found'),
    );

    final updatedPlacement = placement.copyWith(
      position: placement.position.copyWith(
        width: width,
        height: height,
      ),
    );

    await updatePlacement(screenId, updatedPlacement);
  }

  /// Reorder placements on a screen
  Future<void> reorderPlacements(
    String screenId,
    int oldIndex,
    int newIndex,
  ) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    // Reorder in both orientations
    final portraitPlacements = List<ToolPlacement>.from(screen.portraitPlacements);
    final landscapePlacements = List<ToolPlacement>.from(screen.landscapePlacements);

    if (oldIndex < portraitPlacements.length) {
      final item = portraitPlacements.removeAt(oldIndex);
      portraitPlacements.insert(newIndex, item);
    }

    if (oldIndex < landscapePlacements.length) {
      final item = landscapePlacements.removeAt(oldIndex);
      landscapePlacements.insert(newIndex, item);
    }

    final updatedScreen = screen.copyWith(
      portraitPlacements: portraitPlacements,
      landscapePlacements: landscapePlacements,
    );

    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Get all placements from all screens (portrait + landscape, deduplicated)
  List<ToolPlacement> getAllPlacements() {
    if (_currentLayout == null) return [];

    return _currentLayout!.screens
        .expand((screen) => [...screen.portraitPlacements, ...screen.landscapePlacements])
        .toList();
  }

  /// Get placements for a specific screen (returns portrait placements by default)
  List<ToolPlacement> getPlacementsForScreen(String screenId) {
    if (_currentLayout == null) return [];

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    // Return portrait placements, or landscape if portrait is empty
    return screen.portraitPlacements.isNotEmpty
        ? screen.portraitPlacements
        : screen.landscapePlacements;
  }
}
