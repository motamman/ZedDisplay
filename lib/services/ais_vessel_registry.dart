import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/ais_vessel.dart';

/// Indexed vessel store with single-authority pruning.
/// Replaces scattered AIS data in flat cache with proper vessel objects.
class AISVesselRegistry extends ChangeNotifier {
  final Map<String, AISVessel> _vessels = {};
  int pruneMinutes = 15;
  Timer? _pruneTimer;
  String? _selfVesselId;

  String? _selfMMSI; // Extracted MMSI for robust matching

  /// Set the own-vessel ID so it can be excluded from the registry.
  /// Also evicts any self-vessel entry that arrived before the ID was known.
  void setSelfVesselId(String? id) {
    _selfVesselId = id;
    _selfMMSI = _extractMMSI(id);
    // Evict self if it snuck in during the race window
    if (id != null && _vessels.remove(id) != null) {
      notifyListeners();
    }
    if (_selfMMSI != null) {
      final before = _vessels.length;
      _vessels.removeWhere((key, _) => _extractMMSI(key) == _selfMMSI);
      if (_vessels.length != before) notifyListeners();
    }
  }

  String? get selfVesselId => _selfVesselId;

  /// Extract bare MMSI digits from any vessel ID format.
  /// e.g., "urn:mrn:imo:mmsi:368396230" → "368396230"
  static String? _extractMMSI(String? vesselId) {
    if (vesselId == null) return null;
    final match = RegExp(r'(\d{9})').firstMatch(vesselId);
    return match?.group(1);
  }

  /// Unmodifiable view of all vessels.
  Map<String, AISVessel> get vessels => UnmodifiableMapView(_vessels);

  int get count => _vessels.length;

  /// Update a single vessel field from a WebSocket delta.
  /// Creates the vessel entry if it doesn't exist.
  void updateVessel(String vesselId, String path, dynamic value, DateTime timestamp) {
    // Skip self vessel — match by exact ID or by extracted MMSI
    if (vesselId == _selfVesselId) return;
    if (_selfMMSI != null && _extractMMSI(vesselId) == _selfMMSI) return;

    var vessel = _vessels[vesselId];
    if (vessel == null) {
      vessel = AISVessel(vesselId: vesselId, lastSeen: timestamp);
      _vessels[vesselId] = vessel;
    }
    vessel.updateFromPath(path, value, timestamp);
  }

  /// Bulk update from REST response data.
  /// [restData] maps vesselId → nested vessel JSON from /signalk/v1/api/vessels.
  void updateFromREST(Map<String, Map<String, dynamic>> restData) {
    final now = DateTime.now();
    for (final entry in restData.entries) {
      final vesselId = entry.key;
      if (vesselId == _selfVesselId || vesselId == 'self') continue;
      if (_selfMMSI != null && _extractMMSI(vesselId) == _selfMMSI) continue;

      final data = entry.value;
      var vessel = _vessels[vesselId];
      if (vessel == null) {
        vessel = AISVessel(vesselId: vesselId, lastSeen: now, fromREST: true);
        _vessels[vesselId] = vessel;
      }

      // Apply each field
      for (final field in data.entries) {
        vessel.updateFromPath(field.key, field.value, now);
      }
      vessel.fromREST = true;
    }
  }

  /// Call once per delta batch (not per path) to notify listeners.
  void notifyChanged() => notifyListeners();

  /// Start periodic prune timer. Removes vessels older than [pruneMinutes].
  void startPruning() {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _pruneStale();
    });
  }

  void _pruneStale() {
    final before = _vessels.length;
    _vessels.removeWhere((_, vessel) => vessel.ageMinutes > pruneMinutes);
    if (_vessels.length != before) {
      notifyListeners();
    }
  }

  /// Clear all vessels (e.g., on disconnect).
  void clear() {
    if (_vessels.isNotEmpty) {
      _vessels.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _vessels.clear();
    super.dispose();
  }
}
