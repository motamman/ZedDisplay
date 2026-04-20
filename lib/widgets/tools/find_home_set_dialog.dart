import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Format lat/lon as degrees decimal minutes: "47°36.352'N 122°19.876'W"
String formatDDM(double lat, double lon) {
  String fmt(double v, String pos, String neg) {
    final h = v >= 0 ? pos : neg;
    final a = v.abs();
    final d = a.floor();
    final m = (a - d) * 60;
    return '$d\u00B0${m.toStringAsFixed(3)}\'$h';
  }
  return '${fmt(lat, 'N', 'S')} ${fmt(lon, 'E', 'W')}';
}

/// Map-based dialog for choosing or editing the home position.
/// Returns `(lat, lon)` on confirm, `(double.infinity, double.infinity)`
/// on reset, or `null` on cancel.
class FindHomeSetDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final Position? devicePosition;

  const FindHomeSetDialog({
    super.key,
    this.initialLat,
    this.initialLon,
    this.devicePosition,
  });

  @override
  State<FindHomeSetDialog> createState() => _FindHomeSetDialogState();
}

class _FindHomeSetDialogState extends State<FindHomeSetDialog> {
  late TextEditingController _latController;
  late TextEditingController _lonController;
  final MapController _mapController = MapController();
  double? _selectedLat;
  double? _selectedLon;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLat;
    _selectedLon = widget.initialLon;

    _latController = TextEditingController(
      text: _selectedLat != null ? _formatCoordForEdit(_selectedLat!, true) : '',
    );
    _lonController = TextEditingController(
      text: _selectedLon != null ? _formatCoordForEdit(_selectedLon!, false) : '',
    );
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Format a coordinate for the text field: "47 36.352 N"
  String _formatCoordForEdit(double value, bool isLat) {
    final h = isLat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final a = value.abs();
    final d = a.floor();
    final m = (a - d) * 60;
    return '$d ${m.toStringAsFixed(3)} $h';
  }

  /// Parse a coordinate string into decimal degrees.
  /// Accepts: "47.605867", "-47.605867", "47 36.352", "47 36.352 N"
  double? _parseCoordinate(String input) {
    final cleaned = input.trim().replaceAll(RegExp('[°\'"\\u00B0]'), ' ').trim();
    if (cleaned.isEmpty) return null;

    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    // Determine sign from hemisphere letter. When a hemisphere letter is
    // present it overrides the numeric sign (so "-47.6 N" resolves to
    // +47.6, not -47.6). Without a hemisphere, fall back to the numeric
    // sign as typed.
    double sign = 1.0;
    bool hasHemisphere = false;
    final lastToken = tokens.last.toUpperCase();
    if (lastToken == 'S' || lastToken == 'W') {
      sign = -1.0;
      hasHemisphere = true;
      tokens.removeLast();
    } else if (lastToken == 'N' || lastToken == 'E') {
      hasHemisphere = true;
      tokens.removeLast();
    }

    if (tokens.isEmpty) return null;

    if (tokens.length == 1) {
      final dd = double.tryParse(tokens[0]);
      if (dd == null) return null;
      return hasHemisphere ? sign * dd.abs() : dd;
    }

    if (tokens.length == 2) {
      // Degrees + decimal minutes
      final deg = double.tryParse(tokens[0]);
      final min = double.tryParse(tokens[1]);
      if (deg == null || min == null) return null;
      return sign * (deg.abs() + min / 60);
    }

    return null;
  }

  void _onLatLonTextChanged() {
    final lat = _parseCoordinate(_latController.text);
    final lon = _parseCoordinate(_lonController.text);
    if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180) {
      setState(() {
        _selectedLat = lat;
        _selectedLon = lon;
      });
      if (_mapReady) {
        _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
      }
    }
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _selectedLat = point.latitude;
      _selectedLon = point.longitude;
      _latController.text = _formatCoordForEdit(point.latitude, true);
      _lonController.text = _formatCoordForEdit(point.longitude, false);
    });
  }

  void _useCurrentGps() {
    final pos = widget.devicePosition;
    if (pos == null) return;
    setState(() {
      _selectedLat = pos.latitude;
      _selectedLon = pos.longitude;
      _latController.text = _formatCoordForEdit(pos.latitude, true);
      _lonController.text = _formatCoordForEdit(pos.longitude, false);
    });
    if (_mapReady) {
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  LatLng get _mapCenter {
    if (_selectedLat != null && _selectedLon != null) {
      return LatLng(_selectedLat!, _selectedLon!);
    }
    if (widget.devicePosition != null) {
      return LatLng(widget.devicePosition!.latitude, widget.devicePosition!.longitude);
    }
    return const LatLng(0, 0);
  }

  /// Format preview as DDM
  String get _preview {
    if (_selectedLat == null || _selectedLon == null) return '';
    return formatDDM(_selectedLat!, _selectedLon!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = _selectedLat != null && _selectedLon != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Set Home Position',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lat/Lon text fields
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'Lat',
                        hintText: '47 36.352 N',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      onChanged: (_) => _onLatLonTextChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lonController,
                      decoration: const InputDecoration(
                        labelText: 'Lon',
                        hintText: '122 19.876 W',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      onChanged: (_) => _onLatLonTextChanged(),
                    ),
                  ),
                ],
              ),

              // Preview
              if (hasSelection) ...[
                const SizedBox(height: 4),
                Text(
                  _preview,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 12),

              // Map
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 12,
                      minZoom: 3,
                      maxZoom: 18,
                      onTap: _onMapTap,
                      onMapReady: () => _mapReady = true,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.zennora.signalk',
                      ),
                      TileLayer(
                        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.zennora.signalk',
                      ),
                      MarkerLayer(
                          markers: [
                            if (hasSelection)
                              Marker(
                                point: LatLng(_selectedLat!, _selectedLon!),
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 40,
                                ),
                              ),
                            if (widget.devicePosition != null)
                              Marker(
                                point: LatLng(
                                  widget.devicePosition!.latitude,
                                  widget.devicePosition!.longitude,
                                ),
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.devicePosition != null ? _useCurrentGps : null,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('GPS'),
                  ),
                  const SizedBox(width: 4),
                  if (widget.initialLat != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop((double.infinity, double.infinity)),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Reset'),
                      style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: hasSelection
                        ? () => Navigator.of(context).pop((_selectedLat!, _selectedLon!))
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Set Home'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
