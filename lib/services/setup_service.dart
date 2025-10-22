import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/dashboard_setup.dart';
import '../models/tool.dart';
import 'storage_service.dart';
import 'tool_service.dart';
import 'dashboard_service.dart';

/// Service for managing dashboard setups (export, import, share, switch)
class SetupService extends ChangeNotifier {
  final StorageService _storageService;
  final ToolService _toolService;
  final DashboardService _dashboardService;

  String? _activeSetupId; // Track the currently active setup

  SetupService(
    this._storageService,
    this._toolService,
    this._dashboardService,
  ) {
    // Listen to dashboard changes and auto-save active setup
    _dashboardService.addListener(_onDashboardChanged);
  }

  /// Initialize and create default setup if needed
  Future<void> initialize() async {
    try {
      // Check if any setups exist
      final setups = _storageService.getSavedSetupReferences();

      // If no setups exist, create a default one from current dashboard
      if (setups.isEmpty && _dashboardService.currentLayout != null) {
        final layout = _dashboardService.currentLayout!;

        // Get all tools from the layout
        final toolIds = layout.getAllToolIds();
        final tools = <Tool>[];
        for (final toolId in toolIds) {
          final tool = _toolService.getTool(toolId);
          if (tool != null) {
            tools.add(tool);
          }
        }

        // Create default setup
        final metadata = SetupMetadata(
          name: 'Default Dashboard',
          description: 'Your first dashboard',
          author: 'System',
          createdAt: DateTime.now(),
          tags: ['default'],
        );

        final setup = DashboardSetup(
          metadata: metadata,
          layout: layout,
          tools: tools,
        );

        await _storageService.saveSetup(setup);

        // Set as active setup
        _activeSetupId = layout.id;

        if (kDebugMode) {
          print('Created default setup on first install');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing SetupService: $e');
      }
    }
  }

  String? get activeSetupId => _activeSetupId;

  /// Clear the active setup (when creating a new blank dashboard)
  void clearActiveSetup() {
    _activeSetupId = null;
    notifyListeners();
    if (kDebugMode) {
      print('Active setup cleared');
    }
  }

  /// Auto-save active setup when dashboard changes
  void _onDashboardChanged() {
    if (_activeSetupId != null) {
      _autoSaveActiveSetup();
    }
  }

  /// Automatically save the active setup with current dashboard state
  Future<void> _autoSaveActiveSetup() async {
    if (_activeSetupId == null) return;

    try {
      final setup = await _storageService.loadSetup(_activeSetupId!);
      if (setup == null) return;

      // Get current layout and tools
      final layout = _dashboardService.currentLayout;
      if (layout == null) return;

      final toolIds = layout.getAllToolIds();
      final tools = <Tool>[];
      for (final toolId in toolIds) {
        final tool = _toolService.getTool(toolId);
        if (tool != null) {
          tools.add(tool);
        }
      }

      // Update the setup with current state
      final updatedSetup = setup.copyWith(
        layout: layout,
        tools: tools,
        metadata: setup.metadata.copyWith(updatedAt: DateTime.now()),
      );

      await _storageService.saveSetup(updatedSetup);

      if (kDebugMode) {
        print('Auto-saved active setup: ${setup.metadata.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error auto-saving setup: $e');
      }
    }
  }

  @override
  void dispose() {
    _dashboardService.removeListener(_onDashboardChanged);
    super.dispose();
  }

  /// Export current dashboard layout as a shareable setup
  DashboardSetup exportCurrentSetup({
    required String name,
    String description = '',
    String author = 'User',
    List<String> tags = const [],
  }) {
    final layout = _dashboardService.currentLayout;
    if (layout == null) {
      throw Exception('No active dashboard layout to export');
    }

    // Get all tool IDs referenced in the layout
    final toolIds = layout.getAllToolIds();

    // Collect all tools
    final tools = <Tool>[];
    for (final toolId in toolIds) {
      final tool = _toolService.getTool(toolId);
      if (tool != null) {
        tools.add(tool);
      } else {
        if (kDebugMode) {
          print('Warning: Tool $toolId not found during export');
        }
      }
    }

    // Create metadata
    final metadata = SetupMetadata(
      name: name,
      description: description,
      author: author,
      createdAt: DateTime.now(),
      tags: tags,
    );

    // Create and return the setup
    return DashboardSetup(
      metadata: metadata,
      layout: layout,
      tools: tools,
    );
  }

  /// Export setup to JSON string (for sharing)
  String exportToJson(DashboardSetup setup) {
    try {
      final json = setup.toJson();
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (e) {
      throw Exception('Error exporting setup to JSON: $e');
    }
  }

  /// Import setup from JSON string
  DashboardSetup importFromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final setup = DashboardSetup.fromJson(json);

      // Validate the setup
      if (!setup.isValid()) {
        final missingIds = setup.getMissingToolIds();
        throw Exception(
          'Invalid setup: Missing tools with IDs: ${missingIds.join(", ")}',
        );
      }

      return setup;
    } catch (e) {
      throw Exception('Error importing setup from JSON: $e');
    }
  }

  /// Save current dashboard as a named setup
  Future<void> saveCurrentAsSetup({
    required String name,
    String description = '',
    String author = 'User',
    List<String> tags = const [],
  }) async {
    try {
      final currentLayout = _dashboardService.currentLayout;
      if (currentLayout == null) {
        throw Exception('No active dashboard layout to save');
      }

      // Check if we're updating an existing setup or creating a new one
      final existingSetup = await _storageService.loadSetup(currentLayout.id);

      if (existingSetup != null) {
        // Update existing setup - keep the same ID
        final setup = exportCurrentSetup(
          name: name.isNotEmpty ? name : existingSetup.metadata.name,
          description: description.isNotEmpty ? description : existingSetup.metadata.description,
          author: author,
          tags: tags.isNotEmpty ? tags : existingSetup.metadata.tags,
        );

        await _storageService.saveSetup(setup);

        // Set as active setup for auto-saving
        _activeSetupId = currentLayout.id;

        if (kDebugMode) {
          print('Setup updated: $name (now active for auto-save)');
        }
      } else {
        // Create new setup with a unique ID
        final newLayoutId = 'layout_${DateTime.now().millisecondsSinceEpoch}';
        final newLayout = currentLayout.copyWith(id: newLayoutId);

        // Get all tools
        final toolIds = newLayout.getAllToolIds();
        final tools = <Tool>[];
        for (final toolId in toolIds) {
          final tool = _toolService.getTool(toolId);
          if (tool != null) {
            tools.add(tool);
          }
        }

        // Create metadata
        final metadata = SetupMetadata(
          name: name,
          description: description,
          author: author,
          createdAt: DateTime.now(),
          tags: tags,
        );

        final setup = DashboardSetup(
          metadata: metadata,
          layout: newLayout,
          tools: tools,
        );

        await _storageService.saveSetup(setup);

        // Update the dashboard to use the new layout ID
        await _dashboardService.updateLayout(newLayout);

        // Set as active setup for auto-saving
        _activeSetupId = newLayoutId;

        if (kDebugMode) {
          print('New setup created: $name (now active for auto-save)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving current as setup: $e');
      }
      rethrow;
    }
  }

  /// Load and activate a saved setup
  Future<void> loadSetup(String setupId) async {
    try {
      // Load the setup
      final setup = await _storageService.loadSetup(setupId);
      if (setup == null) {
        throw Exception('Setup not found: $setupId');
      }

      // First, save all tools from the setup
      for (final tool in setup.tools) {
        await _toolService.saveTool(tool);
      }

      // Then update the dashboard layout
      await _dashboardService.updateLayout(setup.layout);

      // Set this as the active setup for auto-saving
      _activeSetupId = setupId;

      // Update the setup's last used timestamp
      final updatedMetadata = setup.metadata.copyWith(
        updatedAt: DateTime.now(),
      );
      final updatedSetup = setup.copyWith(metadata: updatedMetadata);
      await _storageService.saveSetup(updatedSetup);

      notifyListeners();

      if (kDebugMode) {
        print('Setup loaded: ${setup.metadata.name} (now active for auto-save)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading setup: $e');
      }
      rethrow;
    }
  }

  /// Import a setup from JSON and save it (without activating)
  Future<void> importSetup(String jsonString) async {
    try {
      // Import the setup
      final setup = importFromJson(jsonString);

      // Generate a new unique ID for the layout to avoid overwriting existing setups
      final newLayoutId = 'layout_${DateTime.now().millisecondsSinceEpoch}';
      final newLayout = setup.layout.copyWith(id: newLayoutId);

      // Create a new setup with the unique layout ID
      final newSetup = setup.copyWith(layout: newLayout);

      // Save all tools from the imported setup
      for (final tool in setup.tools) {
        await _toolService.saveTool(tool);
      }

      // Save as a setup for future switching (but don't activate it)
      await _storageService.saveSetup(newSetup);

      notifyListeners();

      if (kDebugMode) {
        print('Setup imported with new ID: ${newSetup.metadata.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error importing setup: $e');
      }
      rethrow;
    }
  }

  /// Import and immediately activate a setup from JSON
  Future<void> importAndLoadSetup(String jsonString) async {
    try {
      // Import the setup
      final setup = importFromJson(jsonString);

      // Save all tools
      for (final tool in setup.tools) {
        await _toolService.saveTool(tool);
      }

      // Update the dashboard layout (activate it)
      await _dashboardService.updateLayout(setup.layout);

      // Also save as a setup for future switching
      await _storageService.saveSetup(setup);

      notifyListeners();

      if (kDebugMode) {
        print('Setup imported and loaded: ${setup.metadata.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error importing and loading setup: $e');
      }
      rethrow;
    }
  }

  /// Delete a saved setup
  Future<void> deleteSetup(String setupId) async {
    try {
      await _storageService.deleteSetup(setupId);
      notifyListeners();

      if (kDebugMode) {
        print('Setup deleted: $setupId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting setup: $e');
      }
      rethrow;
    }
  }

  /// Get all saved setup references
  List<SavedSetup> getSavedSetups() {
    return _storageService.getSavedSetupReferences();
  }

  /// Rename a saved setup
  Future<void> renameSetup(String setupId, String newName) async {
    try {
      final setup = await _storageService.loadSetup(setupId);
      if (setup == null) {
        throw Exception('Setup not found: $setupId');
      }

      final updatedMetadata = setup.metadata.copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      final updatedSetup = setup.copyWith(metadata: updatedMetadata);

      await _storageService.saveSetup(updatedSetup);
      notifyListeners();

      if (kDebugMode) {
        print('Setup renamed to: $newName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error renaming setup: $e');
      }
      rethrow;
    }
  }

  /// Update a saved setup's description
  Future<void> updateSetupDescription(
    String setupId,
    String newDescription,
  ) async {
    try {
      final setup = await _storageService.loadSetup(setupId);
      if (setup == null) {
        throw Exception('Setup not found: $setupId');
      }

      final updatedMetadata = setup.metadata.copyWith(
        description: newDescription,
        updatedAt: DateTime.now(),
      );
      final updatedSetup = setup.copyWith(metadata: updatedMetadata);

      await _storageService.saveSetup(updatedSetup);
      notifyListeners();

      if (kDebugMode) {
        print('Setup description updated');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating setup description: $e');
      }
      rethrow;
    }
  }

  /// Check if a setup with given ID exists
  bool setupExists(String setupId) {
    return _storageService.setupExists(setupId);
  }

  /// Validate if current dashboard can be exported
  bool canExportCurrentSetup() {
    final layout = _dashboardService.currentLayout;
    if (layout == null) return false;

    // Check if all tools are available
    final toolIds = layout.getAllToolIds();
    for (final toolId in toolIds) {
      if (_toolService.getTool(toolId) == null) {
        return false;
      }
    }

    return true;
  }

  /// Get statistics about setups
  Map<String, dynamic> getStatistics() {
    final setups = getSavedSetups();

    return {
      'total': setups.length,
      'totalScreens': setups.fold<int>(0, (sum, s) => sum + s.screenCount),
      'totalTools': setups.fold<int>(0, (sum, s) => sum + s.toolCount),
      'averageScreensPerSetup': setups.isEmpty
          ? 0.0
          : setups.fold<int>(0, (sum, s) => sum + s.screenCount) /
              setups.length,
      'averageToolsPerSetup': setups.isEmpty
          ? 0.0
          : setups.fold<int>(0, (sum, s) => sum + s.toolCount) / setups.length,
    };
  }
}
