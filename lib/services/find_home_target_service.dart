import 'package:flutter/foundation.dart';

/// Lightweight ChangeNotifier that passes an AIS vessel target
/// from the AIS chart to the Find Home widget.
///
/// Pattern: same one-shot signal as [AISFavoritesService.requestHighlight].
class FindHomeTargetService extends ChangeNotifier {
  String? _aisVesselId;
  String? _aisVesselName;

  /// The requested AIS vessel ID (full URN or bare MMSI).
  String? get aisVesselId => _aisVesselId;

  /// Human-readable name for the vessel.
  String? get aisVesselName => _aisVesselName;

  /// Set a new AIS target. Find Home widget will consume and clear.
  void setAisTarget(String id, String name) {
    _aisVesselId = id;
    _aisVesselName = name;
    notifyListeners();
  }

  /// Called by the consumer (Find Home) after picking up the target.
  void clearTarget() {
    _aisVesselId = null;
    _aisVesselName = null;
  }
}
