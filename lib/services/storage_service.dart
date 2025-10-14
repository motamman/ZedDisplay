import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/dashboard_layout.dart';

/// Service for local storage of dashboards, templates, and configurations
class StorageService extends ChangeNotifier {
  static const String _dashboardsBoxName = 'dashboards';
  static const String _templatesBoxName = 'templates';
  static const String _settingsBoxName = 'settings';

  late Box<String> _dashboardsBox;
  late Box<String> _templatesBox;
  late Box<String> _settingsBox;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Initialize Hive and open boxes
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Hive.initFlutter();

      _dashboardsBox = await Hive.openBox<String>(_dashboardsBoxName);
      _templatesBox = await Hive.openBox<String>(_templatesBoxName);
      _settingsBox = await Hive.openBox<String>(_settingsBoxName);

      _initialized = true;
      notifyListeners();

      if (kDebugMode) {
        print('StorageService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing StorageService: $e');
      }
      rethrow;
    }
  }

  /// Close all boxes
  @override
  Future<void> dispose() async {
    await _dashboardsBox.close();
    await _templatesBox.close();
    await _settingsBox.close();
    super.dispose();
  }

  // ===== Dashboard Management =====

  /// Save a dashboard layout
  Future<void> saveDashboard(DashboardLayout layout) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(layout.toJson());
      await _dashboardsBox.put(layout.id, json);
      notifyListeners();

      if (kDebugMode) {
        print('Dashboard saved: ${layout.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving dashboard: $e');
      }
      rethrow;
    }
  }

  /// Load a specific dashboard by ID
  Future<DashboardLayout?> loadDashboard(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _dashboardsBox.get(id);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return DashboardLayout.fromJson(map);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading dashboard $id: $e');
      }
    }
    return null;
  }

  /// Load all dashboards
  Future<List<DashboardLayout>> loadAllDashboards() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    final dashboards = <DashboardLayout>[];

    for (final json in _dashboardsBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        dashboards.add(DashboardLayout.fromJson(map));
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing dashboard: $e');
        }
      }
    }

    return dashboards;
  }

  /// Delete a dashboard
  Future<void> deleteDashboard(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _dashboardsBox.delete(id);
    notifyListeners();

    if (kDebugMode) {
      print('Dashboard deleted: $id');
    }
  }

  /// Get the default dashboard (first one, or null if none exist)
  Future<DashboardLayout?> getDefaultDashboard() async {
    final dashboards = await loadAllDashboards();
    return dashboards.isNotEmpty ? dashboards.first : null;
  }

  /// Save the active dashboard ID
  Future<void> saveActiveDashboardId(String id) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put('active_dashboard_id', id);
  }

  /// Get the active dashboard ID
  String? getActiveDashboardId() {
    if (!_initialized) return null;
    return _settingsBox.get('active_dashboard_id');
  }

  // ===== Template Management =====

  /// Save a template (stored as JSON string)
  Future<void> saveTemplate(String templateId, Map<String, dynamic> templateData) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = jsonEncode(templateData);
      await _templatesBox.put(templateId, json);
      notifyListeners();

      if (kDebugMode) {
        print('Template saved: $templateId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving template: $e');
      }
      rethrow;
    }
  }

  /// Load a specific template by ID
  Future<Map<String, dynamic>?> loadTemplate(String templateId) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    try {
      final json = _templatesBox.get(templateId);
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading template $templateId: $e');
      }
    }
    return null;
  }

  /// Load all templates
  Future<List<Map<String, dynamic>>> loadAllTemplates() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    final templates = <Map<String, dynamic>>[];

    for (final json in _templatesBox.values) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        templates.add(map);
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing template: $e');
        }
      }
    }

    return templates;
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _templatesBox.delete(templateId);
    notifyListeners();

    if (kDebugMode) {
      print('Template deleted: $templateId');
    }
  }

  /// Check if a template exists
  bool templateExists(String templateId) {
    if (!_initialized) return false;
    return _templatesBox.containsKey(templateId);
  }

  // ===== Settings Management =====

  /// Save a generic setting
  Future<void> saveSetting(String key, String value) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.put(key, value);
  }

  /// Get a generic setting
  String? getSetting(String key) {
    if (!_initialized) return null;
    return _settingsBox.get(key);
  }

  /// Delete a setting
  Future<void> deleteSetting(String key) async {
    if (!_initialized) throw Exception('StorageService not initialized');
    await _settingsBox.delete(key);
  }

  // ===== Utility Methods =====

  /// Clear all data (dangerous!)
  Future<void> clearAllData() async {
    if (!_initialized) throw Exception('StorageService not initialized');

    await _dashboardsBox.clear();
    await _templatesBox.clear();
    await _settingsBox.clear();
    notifyListeners();

    if (kDebugMode) {
      print('All data cleared');
    }
  }

  /// Get storage statistics
  Map<String, int> getStorageStats() {
    if (!_initialized) return {};

    return {
      'dashboards': _dashboardsBox.length,
      'templates': _templatesBox.length,
      'settings': _settingsBox.length,
    };
  }
}
