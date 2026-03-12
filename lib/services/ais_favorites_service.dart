import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ais_favorite.dart';
import '../models/alert_event.dart';
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

  StorageService? _storageService;
  SignalKService? _signalKService;
  AlertCoordinator? _alertCoordinator;

  final List<AISFavorite> _favorites = [];
  final Set<String> _mmsiIndex = {}; // O(1) lookup

  // Detection state: MMSIs we've already alerted for in this encounter
  final Set<String> _inRangeNotified = {};

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
    signalKService.aisVesselRegistry.addListener(_onAISUpdate);
  }

  /// Stop monitoring (call on dispose).
  void stopMonitoring() {
    _signalKService?.aisVesselRegistry.removeListener(_onAISUpdate);
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
      severity: AlertSeverity.normal,
      title: fav.name,
      body: 'in range',
      wantsInAppSnackbar: true,
      wantsSystemNotification: true,
      alarmSource: 'ais_favorites',
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
  }

  Future<void> removeFavorite(String mmsi) async {
    _favorites.removeWhere((f) => f.mmsi == mmsi);
    _mmsiIndex.remove(mmsi);
    _inRangeNotified.remove(mmsi);
    await _persist();
    notifyListeners();
  }

  Future<void> updateFavorite(AISFavorite updated) async {
    final index = _favorites.indexWhere((f) => f.mmsi == updated.mmsi);
    if (index >= 0) {
      _favorites[index] = updated;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    _favorites.clear();
    _mmsiIndex.clear();
    _inRangeNotified.clear();
    await _persist();
    notifyListeners();
  }

  /// Extract bare MMSI from URN format (e.g., "urn:mrn:imo:mmsi:368346080" → "368346080")
  String _extractMMSI(String vesselId) {
    if (vesselId.contains(':')) {
      return vesselId.split(':').last;
    }
    return vesselId;
  }

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
