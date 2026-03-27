import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/ais_favorite.dart';
import '../models/alert_event.dart';
import '../models/auth_token.dart';
import 'signalk_service.dart';
import 'storage_service.dart';
import 'alert_coordinator.dart';

/// Manages AIS vessel favorites — persistence, detection, and alerts.
///
/// Monitors the AIS vessel registry directly (like CpaAlertService) so
/// detection works even when the AIS chart widget is off-screen or the
/// app is backgrounded.
class AISFavoritesService extends ChangeNotifier {
  static const _storageKey = 'ais_favorites';
  static const String _resourceType = 'zeddisplay-favorites';
  static const Duration _pollInterval = Duration(seconds: 60);
  static const String _deviceIdKey = 'crew_device_id';

  StorageService? _storageService;
  SignalKService? _signalKService;
  AlertCoordinator? _alertCoordinator;

  final List<AISFavorite> _favorites = [];
  final Set<String> _mmsiIndex = {}; // O(1) lookup

  // Detection state: MMSIs we've already alerted for in this encounter
  final Set<String> _inRangeNotified = {};

  // Sync state
  Timer? _pollTimer;
  bool _resourcesApiAvailable = true;
  bool _isSyncing = false;
  bool _wasConnected = false;
  String? _cachedDeviceId;

  /// Vessel ID (URN) requested to be highlighted by a snackbar tap.
  /// The AIS chart reads this in its listener and clears it after use.
  String? _highlightRequestedVesselId;
  String? get highlightRequestedVesselId => _highlightRequestedVesselId;
  void clearHighlightRequest() => _highlightRequestedVesselId = null;

  List<AISFavorite> get favorites => List.unmodifiable(_favorites);

  bool isFavorite(String mmsi) => _mmsiIndex.contains(mmsi);

  void loadFromStorage(StorageService storageService) {
    _storageService = storageService;
    final json = storageService.getSetting(_storageKey);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _favorites.clear();
        _mmsiIndex.clear();
        for (final item in list) {
          final fav = AISFavorite.fromJson(item as Map<String, dynamic>);
          _favorites.add(fav);
          _mmsiIndex.add(fav.mmsi);
        }
      } catch (e) {
        if (kDebugMode) {
          print('AISFavoritesService: failed to load favorites: $e');
        }
      }
    }
  }

  /// Start monitoring the AIS vessel registry for favorite detections.
  void startMonitoring(SignalKService signalKService, AlertCoordinator alertCoordinator) {
    _signalKService = signalKService;
    _alertCoordinator = alertCoordinator;
    // When user dismisses a favorites alert, clear from _inRangeNotified
    // so the vessel can re-trigger on next encounter
    alertCoordinator.registerResolveCallback(AlertSubsystem.aisFavorites, (alarmId) {
      if (alarmId != null) {
        _inRangeNotified.remove(alarmId);
      }
    });
    signalKService.aisVesselRegistry.addListener(_onAISUpdate);

    // Register for server sync
    signalKService.registerConnectionCallback(_onConnected);
    signalKService.addListener(_onSignalKChanged);

    // If already connected, kick off sync
    if (signalKService.isConnected) {
      _onConnected();
    }
  }

  /// Stop monitoring (call on dispose).
  void stopMonitoring() {
    _signalKService?.aisVesselRegistry.removeListener(_onAISUpdate);
    _signalKService?.unregisterConnectionCallback(_onConnected);
    _signalKService?.removeListener(_onSignalKChanged);
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _onAISUpdate() {
    if (_favorites.isEmpty || _signalKService == null) return;
    _checkForFavorites();
  }

  void _checkForFavorites() {
    final registry = _signalKService!.aisVesselRegistry;
    final vessels = registry.vessels;

    // Build set of visible bare MMSIs and a map to their vessel IDs (URNs)
    final visibleMMSIs = <String>{};
    final mmsiToVesselId = <String, String>{};
    for (final entry in vessels.entries) {
      final vesselId = entry.key;
      final bareMMSI = _extractMMSI(vesselId);
      visibleMMSIs.add(bareMMSI);
      mmsiToVesselId[bareMMSI] = vesselId;
    }

    // Detect newly-arrived favorites
    for (final fav in _favorites) {
      if (visibleMMSIs.contains(fav.mmsi) && !_inRangeNotified.contains(fav.mmsi)) {
        _inRangeNotified.add(fav.mmsi);
        final vesselId = mmsiToVesselId[fav.mmsi];
        _submitDetectionAlert(fav, vesselId);
      }
    }

    // Remove from notified set when vessel leaves range → can trigger again
    _inRangeNotified.removeWhere(
      (mmsi) => _mmsiIndex.contains(mmsi) && !visibleMMSIs.contains(mmsi),
    );
  }

  void _submitDetectionAlert(AISFavorite fav, String? vesselId) {
    _alertCoordinator?.submitAlert(AlertEvent(
      subsystem: AlertSubsystem.aisFavorites,
      severity: AlertSeverity.alert,
      title: fav.name,
      body: 'in range',
      wantsInAppSnackbar: true,
      wantsSystemNotification: true,
      alarmSource: 'ais_favorites',
      alarmId: fav.mmsi, // Per-vessel tracking in coordinator
      callbackData: vesselId, // URN for highlight-on-tap
    ));
  }

  /// Called from the snackbar "VIEW" action — stores the vessel ID for the
  /// AIS chart widget to pick up and highlight.
  void requestHighlight(String vesselId) {
    _highlightRequestedVesselId = vesselId;
    notifyListeners();
  }

  Future<void> addFavorite(AISFavorite favorite) async {
    if (_mmsiIndex.contains(favorite.mmsi)) return;
    _favorites.add(favorite);
    _mmsiIndex.add(favorite.mmsi);
    await _persist();
    notifyListeners();
    _pushAfterMutation();
  }

  Future<void> removeFavorite(String mmsi) async {
    _favorites.removeWhere((f) => f.mmsi == mmsi);
    _mmsiIndex.remove(mmsi);
    _inRangeNotified.remove(mmsi);
    await _persist();
    notifyListeners();
    _pushAfterMutation();
  }

  Future<void> updateFavorite(AISFavorite updated) async {
    final index = _favorites.indexWhere((f) => f.mmsi == updated.mmsi);
    if (index >= 0) {
      updated.lastModifiedAt = DateTime.now();
      _favorites[index] = updated;
      await _persist();
      notifyListeners();
      _pushAfterMutation();
    }
  }

  Future<void> clearAll() async {
    _favorites.clear();
    _mmsiIndex.clear();
    _inRangeNotified.clear();
    await _persist();
    notifyListeners();
    // Delete server resource for this profile
    _deleteServerResource();
  }

  /// Extract bare MMSI from URN format (e.g., "urn:mrn:imo:mmsi:368346080" → "368346080")
  String _extractMMSI(String vesselId) {
    if (vesselId.contains(':')) {
      return vesselId.split(':').last;
    }
    return vesselId;
  }

  // ── Sync engine ──────────────────────────────────────────────

  void _onSignalKChanged() {
    final isConnected = _signalKService?.isConnected ?? false;
    if (isConnected == _wasConnected) return;
    _wasConnected = isConnected;

    if (!isConnected) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _onConnected() async {
    final sk = _signalKService;
    if (sk == null) return;

    // Ensure resource type exists on server
    final ok = await sk.ensureResourceTypeExists(
      _resourceType,
      description: 'ZedDisplay AIS vessel favorites',
    );
    _resourcesApiAvailable = ok;
    if (!_resourcesApiAvailable) return;

    // Initial sync then start polling
    await _syncWithServer();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _syncWithServer();
    });
  }

  /// Fetch remote favorites, merge with local, persist merged set, push back.
  Future<void> _syncWithServer() async {
    final sk = _signalKService;
    if (sk == null || !sk.isConnected || !_resourcesApiAvailable || _isSyncing) {
      return;
    }
    _isSyncing = true;
    try {
      final profileId = await _getProfileIdentifier();
      final resources = await sk.getResources(_resourceType);

      // Find our resource (handle URL-encoded keys and server key stripping)
      // Server may strip prefix — e.g., PUT "user:maurice" stored as "maurice"
      final bareId = profileId.contains(':')
          ? profileId.split(':').last
          : profileId;
      Map<String, dynamic>? resourceData;
      for (final key in resources.keys) {
        final decodedKey = Uri.decodeComponent(key);
        if (key == profileId ||
            decodedKey == profileId ||
            key == bareId ||
            decodedKey == bareId) {
          resourceData = resources[key] as Map<String, dynamic>?;
          break;
        }
      }

      // Parse remote favorites from description JSON
      List<AISFavorite> remoteFavorites = [];
      if (resourceData != null) {
        final descriptionJson = resourceData['description'] as String?;
        if (descriptionJson != null) {
          try {
            final data = jsonDecode(descriptionJson) as Map<String, dynamic>;
            final list = data['favorites'] as List<dynamic>? ?? [];
            remoteFavorites = list
                .map((item) => AISFavorite.fromJson(item as Map<String, dynamic>))
                .toList();
          } catch (e) {
            if (kDebugMode) {
              print('AISFavoritesService: failed to parse remote favorites: $e');
            }
          }
        }
      }

      // Merge
      final merged = _merge(_favorites, remoteFavorites);

      // Update local state
      _favorites.clear();
      _mmsiIndex.clear();
      for (final fav in merged) {
        _favorites.add(fav);
        _mmsiIndex.add(fav.mmsi);
      }
      await _persist();
      notifyListeners();

      // Push merged set back to server
      await _pushToServer(profileId, merged);
    } catch (e) {
      if (kDebugMode) {
        print('AISFavoritesService: sync failed: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Union merge by MMSI. Same MMSI → latest lastModifiedAt wins name/notes,
  /// earliest addedAt is kept.
  List<AISFavorite> _merge(List<AISFavorite> local, List<AISFavorite> remote) {
    final Map<String, AISFavorite> byMmsi = {};

    for (final fav in local) {
      byMmsi[fav.mmsi] = fav;
    }

    for (final fav in remote) {
      final existing = byMmsi[fav.mmsi];
      if (existing == null) {
        byMmsi[fav.mmsi] = fav;
      } else {
        // Keep earliest addedAt, latest lastModifiedAt wins name/notes
        if (fav.lastModifiedAt.isAfter(existing.lastModifiedAt)) {
          byMmsi[fav.mmsi] = AISFavorite(
            mmsi: fav.mmsi,
            name: fav.name,
            notes: fav.notes,
            addedAt: existing.addedAt.isBefore(fav.addedAt)
                ? existing.addedAt
                : fav.addedAt,
            lastModifiedAt: fav.lastModifiedAt,
          );
        } else {
          // Keep existing but use earliest addedAt
          if (fav.addedAt.isBefore(existing.addedAt)) {
            byMmsi[fav.mmsi] = AISFavorite(
              mmsi: existing.mmsi,
              name: existing.name,
              notes: existing.notes,
              addedAt: fav.addedAt,
              lastModifiedAt: existing.lastModifiedAt,
            );
          }
        }
      }
    }

    return byMmsi.values.toList();
  }

  Future<void> _pushToServer(String profileId, List<AISFavorite> favorites) async {
    final sk = _signalKService;
    if (sk == null || !sk.isConnected || !_resourcesApiAvailable) return;

    final data = {
      'name': 'AIS Favorites ($profileId)',
      'description': jsonEncode({
        'favorites': favorites.map((f) => f.toJson()).toList(),
        'lastSyncedAt': DateTime.now().toIso8601String(),
      }),
    };

    final success = await sk.putResource(_resourceType, profileId, data);
    if (!success && kDebugMode) {
      print('AISFavoritesService: failed to push favorites to server');
    }
  }

  /// Fire-and-forget push after a local mutation.
  void _pushAfterMutation() {
    final sk = _signalKService;
    if (sk == null || !sk.isConnected || !_resourcesApiAvailable) return;

    () async {
      try {
        final profileId = await _getProfileIdentifier();
        await _pushToServer(profileId, _favorites);
      } catch (e) {
        if (kDebugMode) {
          print('AISFavoritesService: push after mutation failed: $e');
        }
      }
    }();
  }

  /// Delete the server resource for the current profile (used by clearAll).
  void _deleteServerResource() {
    final sk = _signalKService;
    if (sk == null || !sk.isConnected || !_resourcesApiAvailable) return;

    () async {
      try {
        final profileId = await _getProfileIdentifier();
        await sk.deleteResource(_resourceType, profileId);
      } catch (e) {
        if (kDebugMode) {
          print('AISFavoritesService: delete server resource failed: $e');
        }
      }
    }();
  }

  /// Get profile identifier: 'user:{username}' for user login, 'device:{uuid}' for device.
  Future<String> _getProfileIdentifier() async {
    final authToken = _signalKService?.authToken;
    if (authToken?.authType == AuthType.user && authToken?.username != null) {
      return 'user:${authToken!.username}';
    }
    final deviceId = await _getDeviceId();
    return 'device:$deviceId';
  }

  /// Get or generate a unique device ID (reuses crew_device_id key).
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    String? deviceId = _storageService?.getSetting(_deviceIdKey);
    if (deviceId == null && _storageService != null) {
      deviceId = const Uuid().v4();
      await _storageService!.saveSetting(_deviceIdKey, deviceId);
    }
    _cachedDeviceId = deviceId;
    return deviceId ?? const Uuid().v4();
  }

  // ── Persistence ─────────────────────────────────────────────

  Future<void> _persist() async {
    if (_storageService == null) return;
    final json = jsonEncode(_favorites.map((f) => f.toJson()).toList());
    await _storageService!.saveSetting(_storageKey, json);
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
