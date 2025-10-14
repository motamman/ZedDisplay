import 'package:flutter/foundation.dart';
import '../models/dashboard_layout.dart';
import '../models/dashboard_screen.dart';
import '../models/tool_instance.dart';
import 'storage_service.dart';

/// Service for managing dashboard layouts and screens
class DashboardService extends ChangeNotifier {
  final StorageService _storageService;

  DashboardLayout? _currentLayout;
  bool _initialized = false;

  DashboardService(this._storageService);

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
      if (_currentLayout == null) {
        _currentLayout = await _storageService.getDefaultDashboard();
      }

      // If still no dashboard, create a default one
      if (_currentLayout == null) {
        _currentLayout = DashboardLayout(
          id: 'layout_default',
          name: 'Default Layout',
          screens: [
            DashboardScreen(
              id: 'screen_main',
              name: 'Main',
              tools: [],
              order: 0,
            ),
          ],
          activeScreenIndex: 0,
        );

        await saveDashboard();
      }

      _initialized = true;
      notifyListeners();

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

  /// Save the current dashboard layout
  Future<void> saveDashboard() async {
    if (_currentLayout == null) return;

    try {
      await _storageService.saveDashboard(_currentLayout!);
      await _storageService.saveActiveDashboardId(_currentLayout!.id);

      if (kDebugMode) {
        print('Dashboard saved: ${_currentLayout!.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving dashboard: $e');
      }
      rethrow;
    }
  }

  /// Update the current layout
  void updateLayout(DashboardLayout layout) {
    _currentLayout = layout;
    notifyListeners();
    saveDashboard();
  }

  /// Add a screen to the current layout
  Future<void> addScreen({String? name}) async {
    if (_currentLayout == null) return;

    final screenName = name ?? 'Screen ${_currentLayout!.screens.length + 1}';
    final newScreen = DashboardScreen(
      id: 'screen_${DateTime.now().millisecondsSinceEpoch}',
      name: screenName,
      tools: [],
      order: _currentLayout!.screens.length,
    );

    _currentLayout = _currentLayout!.addScreen(newScreen);
    notifyListeners();
    await saveDashboard();
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

  /// Add a tool to the current active screen
  Future<void> addToolToActiveScreen(ToolInstance tool) async {
    if (_currentLayout == null || _currentLayout!.activeScreen == null) return;

    final activeScreen = _currentLayout!.activeScreen!;
    final updatedScreen = activeScreen.addTool(tool);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Remove a tool from a screen
  Future<void> removeTool(String screenId, String toolId) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    final updatedScreen = screen.removeTool(toolId);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Update a tool on a screen
  Future<void> updateTool(String screenId, ToolInstance tool) async {
    if (_currentLayout == null) return;

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    final updatedScreen = screen.updateTool(tool);
    _currentLayout = _currentLayout!.updateScreen(updatedScreen);
    notifyListeners();
    await saveDashboard();
  }

  /// Get all tools from all screens
  List<ToolInstance> getAllTools() {
    if (_currentLayout == null) return [];

    return _currentLayout!.screens
        .expand((screen) => screen.tools)
        .toList();
  }

  /// Get tools for a specific screen
  List<ToolInstance> getToolsForScreen(String screenId) {
    if (_currentLayout == null) return [];

    final screen = _currentLayout!.screens.firstWhere(
      (s) => s.id == screenId,
      orElse: () => throw Exception('Screen not found'),
    );

    return screen.tools;
  }
}
