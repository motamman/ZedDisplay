import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'signalk_service.dart';
import 'bundled_dashboard_service.dart';

/// Info about a dashboard stored on the SignalK server.
class ServerDashboardInfo {
  final String id;
  final String name;
  final String description;
  final String? category;
  final int screenCount;
  final int toolCount;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  final String zedjson;

  ServerDashboardInfo({
    required this.id,
    required this.name,
    required this.description,
    this.category,
    this.screenCount = 0,
    this.toolCount = 0,
    this.uploadedBy,
    this.uploadedAt,
    required this.zedjson,
  });
}

/// Service for storing/fetching dashboards on the SignalK server
/// via the Resources API. Follows the FileShareService pattern.
class DashboardStoreService extends ChangeNotifier {
  final SignalKService _signalKService;

  static const resourceType = 'zeddisplay-dashboards';

  bool _resourceTypeEnsured = false;
  List<ServerDashboardInfo> _serverDashboards = [];
  List<ServerDashboardInfo> get serverDashboards =>
      List.unmodifiable(_serverDashboards);

  bool _isFetching = false;
  bool get isFetching => _isFetching;

  DashboardStoreService(this._signalKService);

  /// Ensure the resource type exists on the server.
  Future<void> _ensureResourceType() async {
    if (_resourceTypeEnsured) return;
    await _signalKService.ensureResourceTypeExists(
      resourceType,
      description: 'ZedDisplay shared dashboards',
    );
    _resourceTypeEnsured = true;
  }

  /// Fetch all dashboards from the server.
  Future<List<ServerDashboardInfo>> fetchFromServer() async {
    if (!_signalKService.isConnected) return [];

    _isFetching = true;
    notifyListeners();

    try {
      await _ensureResourceType();
      final resources = await _signalKService.getResources(resourceType);
      final dashboards = <ServerDashboardInfo>[];

      for (final entry in resources.entries) {
        try {
          final resourceData = entry.value as Map<String, dynamic>;
          final descriptionJson = resourceData['description'] as String?;
          if (descriptionJson == null) continue;

          final meta = jsonDecode(descriptionJson) as Map<String, dynamic>;
          dashboards.add(ServerDashboardInfo(
            id: entry.key,
            name: meta['name'] as String? ?? 'Unnamed',
            description: meta['description'] as String? ?? '',
            category: meta['category'] as String?,
            screenCount: meta['screenCount'] as int? ?? 0,
            toolCount: meta['toolCount'] as int? ?? 0,
            uploadedBy: meta['uploadedBy'] as String?,
            uploadedAt: meta['uploadedAt'] != null
                ? DateTime.tryParse(meta['uploadedAt'] as String)
                : null,
            zedjson: meta['zedjson'] as String? ?? '',
          ));
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing server dashboard ${entry.key}: $e');
          }
        }
      }

      _serverDashboards = dashboards;
      return dashboards;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching server dashboards: $e');
      }
      return [];
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  /// Push a dashboard to the server.
  Future<bool> pushToServer({
    required String name,
    required String description,
    required String zedjsonContent,
    String? category,
    String? uploadedBy,
  }) async {
    if (!_signalKService.isConnected) return false;

    try {
      await _ensureResourceType();

      final id = const Uuid().v4();

      // Parse zedjson to extract screen/tool counts
      int screenCount = 0;
      int toolCount = 0;
      try {
        final parsed = jsonDecode(zedjsonContent) as Map<String, dynamic>;
        final layout = parsed['layout'] as Map<String, dynamic>?;
        if (layout != null) {
          final screens = layout['screens'] as List<dynamic>?;
          screenCount = screens?.length ?? 0;
        }
        final tools = parsed['tools'] as List<dynamic>?;
        toolCount = tools?.length ?? 0;
      } catch (_) {}

      final meta = {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'screenCount': screenCount,
        'toolCount': toolCount,
        'uploadedBy': uploadedBy ?? 'admin',
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
        'zedjson': zedjsonContent,
      };

      final resourceData = {
        'name': name,
        'description': jsonEncode(meta),
        'position': {'latitude': 0.0, 'longitude': 0.0},
      };

      final success = await _signalKService.putResource(
        resourceType,
        id,
        resourceData,
      );

      if (success) {
        // Refresh the cache
        await fetchFromServer();
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error pushing dashboard to server: $e');
      }
      return false;
    }
  }

  /// Delete a dashboard from the server.
  Future<bool> deleteFromServer(String dashboardId) async {
    if (!_signalKService.isConnected) return false;

    try {
      final success = await _signalKService.deleteResource(
        resourceType,
        dashboardId,
      );

      if (success) {
        _serverDashboards.removeWhere((d) => d.id == dashboardId);
        notifyListeners();
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting server dashboard: $e');
      }
      return false;
    }
  }

  /// Push all bundled dashboards to the server (admin action).
  /// Skips dashboards already on the server (by name match).
  /// Returns count of new dashboards pushed.
  Future<int> syncBundledToServer({String? uploadedBy}) async {
    if (!_signalKService.isConnected) return 0;

    try {
      // Refresh server list first
      await fetchFromServer();
      final existingNames =
          _serverDashboards.map((d) => d.name.toLowerCase()).toSet();

      final bundled = await BundledDashboardService.getAvailableDashboards();
      int pushed = 0;

      for (final info in bundled) {
        if (existingNames.contains(info.name.toLowerCase())) {
          if (kDebugMode) {
            print('Skipping "${info.name}" — already on server');
          }
          continue;
        }

        try {
          final zedjson =
              await BundledDashboardService.loadDashboardJson(info);
          final success = await pushToServer(
            name: info.name,
            description: info.description,
            zedjsonContent: zedjson,
            category: info.categoryId,
            uploadedBy: uploadedBy ?? 'admin',
          );
          if (success) pushed++;
        } catch (e) {
          if (kDebugMode) {
            print('Error syncing "${info.name}": $e');
          }
        }
      }

      return pushed;
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing bundled dashboards: $e');
      }
      return 0;
    }
  }
}
