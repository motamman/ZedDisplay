import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Info about a bundled dashboard from the manifest.
class BundledDashboardInfo {
  final String filename;
  final String name;
  final String description;
  final String assetPath;
  final bool isDefault;
  final String categoryId;
  final String categoryName;

  BundledDashboardInfo({
    required this.filename,
    required this.name,
    required this.description,
    required this.assetPath,
    required this.isDefault,
    required this.categoryId,
    required this.categoryName,
  });
}

/// Stateless utility that reads the bundled dashboard manifest
/// and loads dashboard JSON from assets.
class BundledDashboardService {
  static const _manifestPath = 'assets/dashboard/dashboard_manifest.json';

  /// Parse the manifest and return all available bundled dashboards.
  static Future<List<BundledDashboardInfo>> getAvailableDashboards() async {
    try {
      final manifestJson = await rootBundle.loadString(_manifestPath);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      final categories = manifest['categories'] as List<dynamic>;

      final dashboards = <BundledDashboardInfo>[];

      for (final category in categories) {
        final catMap = category as Map<String, dynamic>;
        final basePath = catMap['path'] as String;
        final catId = catMap['id'] as String;
        final catName = catMap['name'] as String;
        final items = catMap['dashboards'] as List<dynamic>;

        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          dashboards.add(BundledDashboardInfo(
            filename: itemMap['filename'] as String,
            name: itemMap['name'] as String,
            description: itemMap['description'] as String? ?? '',
            assetPath: '$basePath${itemMap['filename']}',
            isDefault: itemMap['isDefault'] as bool? ?? false,
            categoryId: catId,
            categoryName: catName,
          ));
        }
      }

      return dashboards;
    } catch (e) {
      if (kDebugMode) {
        print('Error reading dashboard manifest: $e');
      }
      return [];
    }
  }

  /// Return the dashboard marked as `isDefault`, or null if none found.
  static Future<BundledDashboardInfo?> getDefaultDashboard() async {
    final dashboards = await getAvailableDashboards();
    try {
      return dashboards.firstWhere((d) => d.isDefault);
    } on StateError {
      return null;
    }
  }

  /// Load the raw .zedjson string for a given bundled dashboard.
  static Future<String> loadDashboardJson(BundledDashboardInfo info) async {
    return rootBundle.loadString(info.assetPath);
  }
}
