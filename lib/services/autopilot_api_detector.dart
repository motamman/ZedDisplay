import 'package:flutter/foundation.dart';
import 'autopilot_v2_api.dart';
import '../models/autopilot_v2_models.dart';

/// Service to detect which autopilot API version is available
///
/// Tries V2 API first (modern, feature-rich), falls back to V1 (legacy plugin-based)
class AutopilotApiDetector {
  final String baseUrl;
  final String? authToken;

  AutopilotApiDetector({
    required this.baseUrl,
    this.authToken,
  });

  /// Detect which API version is available
  ///
  /// Returns [AutopilotApiVersion] with version info and V2 instances if available.
  ///
  /// Detection strategy:
  /// 1. Try V2 API discovery endpoint
  /// 2. If successful and instances found → V2
  /// 3. If 404 or no instances → V1
  /// 4. If network error → V1 (safe fallback)
  Future<AutopilotApiVersion> detectApiVersion() async {
    if (kDebugMode) {
      print('🔍 Detecting autopilot API version...');
    }

    // Try V2 first
    try {
      final v2Api = AutopilotV2Api(
        baseUrl: baseUrl,
        authToken: authToken,
      );

      final instances = await v2Api.discoverInstances();

      if (instances.isNotEmpty) {
        if (kDebugMode) {
          print('✅ V2 API detected with ${instances.length} instance(s)');
          for (final instance in instances) {
            print('   - ${instance.name} (${instance.provider})${instance.isDefault ? " [DEFAULT]" : ""}');
          }
        }
        return AutopilotApiVersion(
          version: 'v2',
          v2Instances: instances,
        );
      } else {
        if (kDebugMode) {
          print('⚠️ V2 API responded but no instances found, falling back to V1');
        }
      }
    } on AutopilotV2NotAvailableException {
      if (kDebugMode) {
        print('ℹ️ V2 API not available (404), using V1');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ V2 API detection failed: $e, falling back to V1');
      }
    }

    // Fall back to V1
    if (kDebugMode) {
      print('✅ Using V1 API (plugin-based)');
    }
    return AutopilotApiVersion(version: 'v1');
  }
}

/// Result of API version detection
class AutopilotApiVersion {
  final String version; // 'v1' or 'v2'
  final List<AutopilotInstance>? v2Instances;

  AutopilotApiVersion({
    required this.version,
    this.v2Instances,
  });

  bool get isV2 => version == 'v2';
  bool get isV1 => version == 'v1';

  /// Get the default instance (if V2)
  AutopilotInstance? get defaultInstance {
    if (v2Instances == null || v2Instances!.isEmpty) return null;

    // Try to find marked default
    try {
      return v2Instances!.firstWhere((i) => i.isDefault);
    } catch (_) {
      // No default marked, return first
      return v2Instances!.first;
    }
  }
}
