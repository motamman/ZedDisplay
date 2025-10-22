/// Mixin for gauge tools that fetch and display zones
library;

import 'package:flutter/material.dart';
import '../../../models/zone_data.dart';
import '../../../services/signalk_service.dart';

/// Mixin for gauge tools (radial, linear) that display zones
///
/// Provides shared functionality for:
/// - Fetching zones from the zones cache service
/// - Managing zone data state
/// - Listening to connection changes
mixin ZonesMixin<T extends StatefulWidget> on State<T> {
  List<ZoneDefinition>? _zones;
  bool _zonesRequested = false;
  bool _listenerAdded = false;

  /// The current zones for this gauge
  List<ZoneDefinition>? get zones => _zones;

  /// Initializes zone fetching for the given path
  ///
  /// Should be called from initState() with the SignalK path
  /// that needs zones.
  void initializeZones(SignalKService signalKService, String path) {
    if (!_listenerAdded) {
      signalKService.addListener(() => _onConnectionChanged(signalKService, path));
      _listenerAdded = true;
    }
    _fetchZonesIfReady(signalKService, path);
  }

  void _onConnectionChanged(SignalKService signalKService, String path) {
    if (signalKService.isConnected && !_zonesRequested) {
      _fetchZonesIfReady(signalKService, path);
    }
  }

  void _fetchZonesIfReady(SignalKService signalKService, String path) {
    if (signalKService.zonesCache == null) return;
    if (_zonesRequested) return;

    _zonesRequested = true;

    signalKService.zonesCache!.getZones(path).then((zones) {
      if (mounted && zones != null) {
        setState(() {
          _zones = zones;
        });
      }
    });
  }

  /// Cleans up the zones listener
  ///
  /// Should be called from dispose()
  void cleanupZones(SignalKService signalKService) {
    if (_listenerAdded) {
      signalKService.removeListener(() {});
      _listenerAdded = false;
    }
  }
}
