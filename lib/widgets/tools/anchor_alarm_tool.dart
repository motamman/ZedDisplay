import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/anchor_alarm_service.dart';
import '../../services/messaging_service.dart';
import '../../models/anchor_state.dart';
import '../../services/tool_registry.dart';
import '../../utils/conversion_utils.dart';

/// Anchor Alarm Tool - Single unified widget with map and controls
///
/// Shows:
/// - Interactive map with anchor position and vessel
/// - Status panel with distance/bearing info
/// - Control panel with drop/raise anchor and rode adjustment
class AnchorAlarmTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const AnchorAlarmTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<AnchorAlarmTool> createState() => _AnchorAlarmToolState();
}

class _AnchorAlarmToolState extends State<AnchorAlarmTool> {
  late AnchorAlarmService _alarmService;
  final MapController _mapController = MapController();
  bool _mapAutoFollow = true;
  double _rodeSliderValue = 30.0;

  @override
  void initState() {
    super.initState();

    // Get messaging service from provider if available
    MessagingService? messagingService;
    try {
      messagingService = Provider.of<MessagingService>(context, listen: false);
    } catch (_) {
      // Messaging service not available
    }

    _alarmService = AnchorAlarmService(
      signalKService: widget.signalKService,
      messagingService: messagingService,
    );
    _alarmService.initialize();
    _alarmService.addListener(_onStateChanged);

    // Configure from tool settings
    _configureFromSettings();
  }

  void _configureFromSettings() {
    final customProps = widget.config.style.customProperties ?? {};

    // Alarm sound
    final alarmSound = customProps['alarmSound'] as String? ?? 'foghorn';
    _alarmService.setAlarmSound(alarmSound);

    // Check-in config
    final checkInEnabled = customProps['checkInEnabled'] as bool? ?? false;
    final intervalMinutes = customProps['checkInIntervalMinutes'] as int? ?? 30;
    final gracePeriodSeconds = customProps['checkInGracePeriodSeconds'] as int? ?? 60;

    _alarmService.setCheckInConfig(CheckInConfig(
      enabled: checkInEnabled,
      interval: Duration(minutes: intervalMinutes),
      gracePeriod: Duration(seconds: gracePeriodSeconds),
    ));
  }

  @override
  void dispose() {
    _alarmService.removeListener(_onStateChanged);
    _alarmService.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});

      // Update slider from current rode length
      final rodeLength = _alarmService.state.rodeLength;
      if (rodeLength != null && (_rodeSliderValue - rodeLength).abs() > 1) {
        _rodeSliderValue = rodeLength.clamp(5.0, 100.0);
      }

      // Auto-follow vessel if enabled
      if (_mapAutoFollow && _alarmService.state.vesselPosition != null) {
        final pos = _alarmService.state.vesselPosition!;
        try {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            _mapController.camera.zoom,
          );
        } catch (_) {
          // Map not ready yet
        }
      }
    }
  }

  Color _getPrimaryColor() {
    final colorStr = widget.config.style.primaryColor;
    if (colorStr != null && colorStr.startsWith('#')) {
      try {
        return Color(int.parse(colorStr.substring(1), radix: 16) | 0xFF000000);
      } catch (_) {}
    }
    return Colors.blue;
  }

  void _centerOnAnchor() {
    final anchorPos = _alarmService.state.anchorPosition;
    if (anchorPos != null) {
      _mapController.move(
        LatLng(anchorPos.latitude, anchorPos.longitude),
        _mapController.camera.zoom,
      );
      setState(() => _mapAutoFollow = false);
    }
  }

  void _centerOnVessel() {
    final vesselPos = _alarmService.state.vesselPosition;
    if (vesselPos != null) {
      _mapController.move(
        LatLng(vesselPos.latitude, vesselPos.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  void _toggleAutoFollow() {
    setState(() {
      _mapAutoFollow = !_mapAutoFollow;
      if (_mapAutoFollow) {
        _centerOnVessel();
      }
    });
  }

  Future<void> _dropAnchor() async {
    final success = await _alarmService.dropAnchor();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anchor dropped'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _raiseAnchor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raise Anchor'),
        content: const Text('Are you sure you want to raise the anchor and disable the alarm?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Raise Anchor'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _alarmService.raiseAnchor();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anchor raised'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _setRodeLength(double length) async {
    await _alarmService.setRodeLength(length);
  }

  // Format distance with user's preferred units
  String _formatDistance(double? meters, String path) {
    if (meters == null) return '--';
    return ConversionUtils.formatValue(
      widget.signalKService,
      path,
      meters,
      decimalPlaces: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _alarmService.state;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Full map background
          Positioned.fill(
            child: _buildMap(state),
          ),

          // Map controls (top right)
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                _buildMapButton(
                  icon: Icons.add,
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 4),
                _buildMapButton(
                  icon: Icons.remove,
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMapButton(
                  icon: Icons.anchor,
                  onPressed: _centerOnAnchor,
                ),
                const SizedBox(height: 4),
                _buildMapButton(
                  icon: _mapAutoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
                  onPressed: _toggleAutoFollow,
                  color: _mapAutoFollow ? _getPrimaryColor() : null,
                ),
              ],
            ),
          ),

          // Status panel (top left)
          Positioned(
            top: 8,
            left: 8,
            child: _buildStatusPanel(state),
          ),

          // Control panel (bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlPanel(state),
          ),

          // Check-in overlay
          if (_alarmService.awaitingCheckIn)
            Positioned.fill(
              child: _buildCheckInOverlay(),
            ),

          // Alarm overlay
          if (state.alarmState.isAlarming)
            Positioned.fill(
              child: _buildAlarmOverlay(state),
            ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black87, size: 18),
        ),
      ),
    );
  }

  Widget _buildMap(AnchorState state) {
    final vesselPos = state.vesselPosition;
    final anchorPos = state.anchorPosition;

    // Default center
    LatLng center = LatLng(0, 0);
    if (anchorPos != null) {
      center = LatLng(anchorPos.latitude, anchorPos.longitude);
    } else if (vesselPos != null) {
      center = LatLng(vesselPos.latitude, vesselPos.longitude);
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        minZoom: 5,
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture && _mapAutoFollow) {
            setState(() => _mapAutoFollow = false);
          }
        },
      ),
      children: [
        // Base map
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // OpenSeaMap overlay
        TileLayer(
          urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.zennora.signalk',
        ),
        // Track history
        if (_alarmService.trackHistory.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _alarmService.trackHistory
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList(),
                color: Colors.blue.withValues(alpha: 0.7),
                strokeWidth: 2,
              ),
            ],
          ),
        // Alarm radius circle
        if (anchorPos != null && state.maxRadius != null)
          CircleLayer(
            circles: [
              // Alarm radius (red)
              CircleMarker(
                point: LatLng(anchorPos.latitude, anchorPos.longitude),
                radius: state.maxRadius!,
                useRadiusInMeter: true,
                color: Colors.red.withValues(alpha: 0.1),
                borderColor: Colors.red,
                borderStrokeWidth: 2,
              ),
              // Current distance indicator
              if (state.currentRadius != null)
                CircleMarker(
                  point: LatLng(anchorPos.latitude, anchorPos.longitude),
                  radius: state.currentRadius!,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: _getDistanceColor(state),
                  borderStrokeWidth: 1,
                ),
            ],
          ),
        // Markers
        MarkerLayer(
          markers: [
            // Anchor position
            if (anchorPos != null)
              Marker(
                point: LatLng(anchorPos.latitude, anchorPos.longitude),
                width: 32,
                height: 32,
                child: const Icon(Icons.anchor, color: Colors.brown, size: 28),
              ),
            // Vessel position
            if (vesselPos != null)
              Marker(
                point: LatLng(vesselPos.latitude, vesselPos.longitude),
                width: 28,
                height: 28,
                child: Transform.rotate(
                  angle: (state.vesselHeading ?? 0) * math.pi / 180,
                  child: const Icon(Icons.navigation, color: Colors.green, size: 24),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Color _getDistanceColor(AnchorState state) {
    final percentage = state.radiusPercentage ?? 0;
    if (percentage >= 100) return Colors.red;
    if (percentage >= 80) return Colors.orange;
    if (percentage >= 60) return Colors.yellow;
    return Colors.green;
  }

  Widget _buildStatusPanel(AnchorState state) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isActive ? Icons.anchor : Icons.anchor_outlined,
                color: state.isActive ? Colors.orange : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                state.isActive ? 'ANCHORED' : 'NOT SET',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: state.isActive ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          if (state.isActive) ...[
            const SizedBox(height: 6),
            _buildStatusRow('Distance', _formatDistance(state.currentRadius, 'navigation.anchor.currentRadius')),
            _buildStatusRow('Alarm', _formatDistance(state.maxRadius, 'navigation.anchor.maxRadius')),
            _buildStatusRow('Rode', _formatDistance(state.rodeLength, 'navigation.anchor.rodeLength')),
            if (state.bearingDegrees != null)
              _buildStatusRow('Bearing', '${state.bearingDegrees!.toStringAsFixed(0)}°'),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(AnchorState state) {
    // Get unit info for rode length display
    final availableUnits = widget.signalKService.getAvailableUnits('navigation.anchor.rodeLength');
    final unitSymbol = availableUnits.isNotEmpty
        ? widget.signalKService.getConversionInfo('navigation.anchor.rodeLength', availableUnits.first)?.symbol ?? 'm'
        : 'm';

    // Convert current slider value to display units
    final displayValue = ConversionUtils.convertValue(
      widget.signalKService,
      'navigation.anchor.rodeLength',
      _rodeSliderValue,
    ) ?? _rodeSliderValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isActive ? null : _dropAnchor,
                  icon: const Icon(Icons.anchor, size: 18),
                  label: const Text('Drop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isActive ? _raiseAnchor : null,
                  icon: const Icon(Icons.eject, size: 18),
                  label: const Text('Raise'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),

          // Rode length slider (only when active)
          if (state.isActive) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Rode: ', style: TextStyle(color: Colors.black87, fontSize: 12)),
                Text(
                  '${displayValue.toStringAsFixed(0)} $unitSymbol',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.blue,
                      inactiveTrackColor: Colors.blue.shade100,
                      thumbColor: Colors.blue,
                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: _rodeSliderValue,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      onChanged: (value) => setState(() => _rodeSliderValue = value),
                      onChangeEnd: _setRodeLength,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInOverlay() {
    final deadline = _alarmService.checkInDeadline;
    final remaining = deadline != null
        ? deadline.difference(DateTime.now())
        : Duration.zero;

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, size: 60, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'ANCHOR WATCH CHECK-IN',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Time remaining: ${_formatDuration(remaining)}',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _alarmService.acknowledgeCheckIn(),
              icon: const Icon(Icons.check),
              label: const Text("I'm Watching"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmOverlay(AnchorState state) {
    final distanceDisplay = _formatDistance(state.currentRadius, 'navigation.anchor.currentRadius');

    return Container(
      color: Colors.red.shade900.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, size: 80, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              state.alarmMessage ?? 'ANCHOR ALARM',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Distance: $distanceDisplay',
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _alarmService.acknowledgeAlarm(),
              icon: const Icon(Icons.check),
              label: const Text('Acknowledge'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Builder for Anchor Alarm Tool
class AnchorAlarmToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'anchor_alarm',
      name: 'Anchor Alarm',
      description: 'Monitor anchor position with map display, alarms, and check-in system',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [
          'primaryColor',
          'alarmSound',
          'checkInEnabled',
          'checkInIntervalMinutes',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'alarmSound': 'foghorn',
          'checkInEnabled': false,
          'checkInIntervalMinutes': 30,
          'checkInGracePeriodSeconds': 60,
          'showTrackHistory': true,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return AnchorAlarmTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
