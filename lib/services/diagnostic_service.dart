import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'signalk_service.dart';

/// Diagnostic service that logs per-minute memory snapshots, path counts,
/// and REST/WS call stats back to the connected SignalK server via the
/// resources API (zeddisplay-diagnostics resource type).
///
/// Resource key: {deviceId}
/// Value: session header + array of snapshots (JSONL-style entries)
class DiagnosticService {
  // Singleton
  static DiagnosticService? _instance;
  static DiagnosticService? get instance => _instance;

  // Dependencies
  final SignalKService _signalKService;
  final String _deviceId;

  // State
  Timer? _snapshotTimer;
  DateTime? _startTime;
  Map<String, dynamic>? _sessionHeader;
  final List<Map<String, dynamic>> _snapshots = [];
  bool _uploading = false;

  // REST call counters (cumulative since start)
  final Map<String, int> _restCallCounts = {
    'GET': 0,
    'PUT': 0,
    'POST': 0,
    'DELETE': 0,
  };
  final Map<String, int> _restCallLastMemDelta = {
    'GET': 0,
    'PUT': 0,
    'POST': 0,
    'DELETE': 0,
  };

  // WS message counters (reset each snapshot)
  int _wsDeltaCount = 0;
  int _wsMetaCount = 0;
  int _wsNotificationCount = 0;

  DiagnosticService._({
    required SignalKService signalKService,
    required String deviceId,
  })  : _signalKService = signalKService,
        _deviceId = deviceId;

  /// Initialize the singleton diagnostic service.
  static Future<DiagnosticService> initialize({
    required SignalKService signalKService,
    required String deviceId,
  }) async {
    _instance = DiagnosticService._(
      signalKService: signalKService,
      deviceId: deviceId,
    );
    return _instance!;
  }

  /// Record a REST call with memory delta.
  void instrumentRestCall(String method, int memBeforeKB, int memAfterKB) {
    final m = method.toUpperCase();
    _restCallCounts[m] = (_restCallCounts[m] ?? 0) + 1;
    _restCallLastMemDelta[m] = memAfterKB - memBeforeKB;
  }

  /// Record a WebSocket message by type: 'delta', 'meta', 'notification'.
  void instrumentWsMessage(String type) {
    switch (type) {
      case 'delta':
        _wsDeltaCount++;
        break;
      case 'meta':
        _wsMetaCount++;
        break;
      case 'notification':
        _wsNotificationCount++;
        break;
    }
  }

  /// Start the diagnostic logger: build session header and begin snapshots.
  Future<void> start() async {
    if (_snapshotTimer != null) return; // already running

    try {
      _startTime = DateTime.now();
      _snapshots.clear();

      if (kDebugMode) {
        print('DiagnosticService starting for device $_deviceId ...');
      }

      // Collect device info and app version
      final deviceInfo = await _collectDeviceInfo();
      final packageInfo = await PackageInfo.fromPlatform();
      _sessionHeader = {
        'type': 'session_start',
        'deviceId': _deviceId,
        'deviceModel': deviceInfo['model'] ?? 'unknown',
        'os': deviceInfo['os'] ?? Platform.operatingSystem,
        'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
        'startTime': _startTime!.toUtc().toIso8601String(),
        'startRssKB': _getRssKB(),
      };

      // Ensure the resource type exists on the server
      if (_signalKService.isConnected) {
        await _signalKService.ensureResourceTypeExists(
          'zeddisplay-diagnostics',
          description: 'ZedDisplay memory diagnostics',
        );
      }

      // Listen for connection changes to upload when connected
      _signalKService.addListener(_onConnectionChanged);

      // Start snapshot timer (every 60 seconds)
      _snapshotTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _takeSnapshot();
      });

      if (kDebugMode) {
        print('DiagnosticService started, timer running, connected=${_signalKService.isConnected}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('DiagnosticService start FAILED: $e');
      }
    }
  }

  bool _wasConnected = false;

  /// Called when SignalK notifies listeners. Only act on connection transitions.
  void _onConnectionChanged() {
    final isConnected = _signalKService.isConnected;
    if (isConnected && !_wasConnected && _snapshots.isNotEmpty) {
      _wasConnected = true;
      if (kDebugMode) {
        print('DiagnosticService: connected, uploading ${_snapshots.length} pending snapshots');
      }
      _uploadToServer();
    } else if (!isConnected && _wasConnected) {
      _wasConnected = false;
    }
  }

  /// Stop the diagnostic logger: write final snapshot, cancel timer, upload.
  Future<void> stop() async {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _signalKService.removeListener(_onConnectionChanged);

    // Take a final snapshot and upload
    if (_startTime != null) {
      _takeSnapshot();
      await _uploadToServer();
    }
  }

  void _takeSnapshot() {
    if (_startTime == null) return;

    final now = DateTime.now();
    final uptimeMin = now.difference(_startTime!).inMinutes;

    // Snapshot field semantics:
    //   activePaths, subscribedPaths, metadataCount — point-in-time gauges
    //   wsCounts (delta/meta/notification) — per-interval counters, reset each snapshot (60s)
    //   restCalls.*.count — cumulative per-session, divide by uptimeMin for rate
    //   notifyCounts — cumulative per-session, divide by uptimeMin for rate
    final snapshot = {
      'ts': now.toUtc().toIso8601String(),
      'uptimeMin': uptimeMin,
      'rssKB': _getRssKB(),
      'peakRssKB': _getPeakRssKB(),
      'activePaths': _signalKService.latestData.length,
      'subscribedPaths': _signalKService.subscriptionRegistry.allPaths.length,
      'metadataCount': _signalKService.metadataStore.count,
      'notifyCounts': {
        'total': _signalKService.notifyCount,
        'throttled': _signalKService.notifyThrottledCount,
      },
      'restCalls': {
        'GET': {
          'count': _restCallCounts['GET'] ?? 0,
          'lastMemDeltaKB': _restCallLastMemDelta['GET'] ?? 0,
        },
        'PUT': {
          'count': _restCallCounts['PUT'] ?? 0,
          'lastMemDeltaKB': _restCallLastMemDelta['PUT'] ?? 0,
        },
        'POST': {
          'count': _restCallCounts['POST'] ?? 0,
          'lastMemDeltaKB': _restCallLastMemDelta['POST'] ?? 0,
        },
        'DELETE': {
          'count': _restCallCounts['DELETE'] ?? 0,
          'lastMemDeltaKB': _restCallLastMemDelta['DELETE'] ?? 0,
        },
      },
      'wsCounts': {
        'deltaMessages': _wsDeltaCount,
        'metaMessages': _wsMetaCount,
        'notificationMessages': _wsNotificationCount,
      },
      'cacheSizes': {
        'metadataStore': _signalKService.metadataStore.count,
        'displayUnitsCache': _signalKService.displayUnitsCacheCount,
        'latestData': _signalKService.latestData.length,
        'conversionsData': _signalKService.conversionsDataCount,
        'availablePaths': _signalKService.availablePathsCount,
        'aisVessels': _signalKService.aisVesselRegistry.count,
        'notificationState': _signalKService.notificationStateCount,
        'notificationTime': _signalKService.notificationTimeCount,
        'diagnosticSnapshots': _snapshots.length,
      },
    };

    _snapshots.add(snapshot);

    // Reset WS counters for next interval
    _wsDeltaCount = 0;
    _wsMetaCount = 0;
    _wsNotificationCount = 0;

    // Upload every 5 snapshots (every 5 minutes), or on the first snapshot
    if (_snapshots.length == 1 || _snapshots.length % 5 == 0) {
      _uploadToServer();
    }
  }

  /// Upload session data to SignalK server via resources API.
  Future<void> _uploadToServer() async {
    if (!_signalKService.isConnected || _uploading) return;
    if (_sessionHeader == null) return;

    _uploading = true;
    try {
      // Ensure resource type exists before first upload
      await _signalKService.ensureResourceTypeExists(
        'zeddisplay-diagnostics',
        description: 'ZedDisplay memory diagnostics',
      );

      final sessionId = '$_deviceId-${_formatTimestamp(_startTime!)}';
      final diagnosticData = {
        'session': _sessionHeader,
        'snapshots': List<Map<String, dynamic>>.from(_snapshots),
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      };

      // Wrap in SignalK notes resource format (name, description, position)
      final payload = {
        'name': 'diag-$_deviceId-${_formatTimestamp(_startTime!)}',
        'description': jsonEncode(diagnosticData),
        'position': {
          'latitude': 0.0,
          'longitude': 0.0,
        },
      };

      final success = await _signalKService.putResource(
        'zeddisplay-diagnostics',
        sessionId,
        payload,
      );

      if (kDebugMode) {
        if (success) {
          print('DiagnosticService uploaded ${_snapshots.length} snapshots to $sessionId');
        } else {
          print('DiagnosticService upload FAILED for $sessionId (${_snapshots.length} snapshots)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('DiagnosticService upload error: $e');
      }
    } finally {
      _uploading = false;
    }
  }

  int _getRssKB() {
    try {
      if (Platform.isAndroid) {
        final status = File('/proc/self/status');
        if (!status.existsSync()) return 0;
        final lines = status.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('VmRSS:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              return int.parse(parts[1]); // already in KB
            }
          }
        }
        return 0;
      }
      // iOS/macOS
      final rss = ProcessInfo.currentRss;
      return rss > 0 ? (rss / 1024).round() : 0;
    } catch (_) {
      return 0;
    }
  }

  int _getPeakRssKB() {
    try {
      if (Platform.isAndroid) {
        final status = File('/proc/self/status');
        if (!status.existsSync()) return 0;
        final lines = status.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('VmHWM:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              return int.parse(parts[1]);
            }
          }
        }
        return 0;
      }
      // iOS/macOS
      final peak = ProcessInfo.maxRss;
      return peak > 0 ? (peak / 1024).round() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, String>> _collectDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return {
          'model': '${info.manufacturer} ${info.model}',
          'os': 'Android ${info.version.release}',
        };
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return {
          'model': info.modelName,
          'os': 'iOS ${info.systemVersion}',
        };
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        return {
          'model': info.modelName,
          'os': 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion}',
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('DiagnosticService device info error: $e');
      }
    }
    return {};
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
