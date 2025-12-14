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

/// Anchor Alarm Tool - Compact dashboard widget with full-screen dialog
///
/// Shows:
/// - Mini map with anchor position and vessel
/// - Distance to anchor and alarm state
/// - Tap to open full controls
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

  void _openFullDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AnchorAlarmDialog(
        alarmService: _alarmService,
        signalKService: widget.signalKService,
        primaryColor: _getPrimaryColor(),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final state = _alarmService.state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _openFullDialog,
      child: Card(
        child: Stack(
          children: [
            // Mini map background
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildMiniMap(state, isDark),
              ),
            ),

            // Status overlay at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: _buildStatusBar(state),
              ),
            ),

            // Alarm indicator at top right
            if (state.alarmState.isWarning)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getAlarmColor(state.alarmState),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.alarmState.name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Check-in indicator
            if (_alarmService.awaitingCheckIn)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'CHECK-IN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Tap hint when inactive
            if (!state.isActive)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.anchor, size: 32, color: Colors.white70),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap to set anchor',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap(AnchorState state, bool isDark) {
    final vesselPos = state.vesselPosition;
    final anchorPos = state.anchorPosition;

    // Default center
    LatLng center = LatLng(0, 0);
    double zoom = 16;

    if (anchorPos != null) {
      center = LatLng(anchorPos.latitude, anchorPos.longitude);
    } else if (vesselPos != null) {
      center = LatLng(vesselPos.latitude, vesselPos.longitude);
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none, // Disable all interactions on mini map
        ),
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
        // Alarm radius circle
        if (anchorPos != null && state.maxRadius != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(anchorPos.latitude, anchorPos.longitude),
                radius: state.maxRadius!,
                useRadiusInMeter: true,
                color: Colors.red.withValues(alpha: 0.1),
                borderColor: Colors.red,
                borderStrokeWidth: 2,
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
                width: 24,
                height: 24,
                child: const Icon(Icons.anchor, color: Colors.brown, size: 20),
              ),
            // Vessel position
            if (vesselPos != null)
              Marker(
                point: LatLng(vesselPos.latitude, vesselPos.longitude),
                width: 24,
                height: 24,
                child: Transform.rotate(
                  angle: (state.vesselHeading ?? 0) * math.pi / 180,
                  child: const Icon(Icons.navigation, color: Colors.green, size: 20),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBar(AnchorState state) {
    // Format distance with user's preferred units
    String formatDistance(double? meters) {
      if (meters == null) return '--';
      return ConversionUtils.formatValue(
        widget.signalKService,
        'navigation.anchor.currentRadius',
        meters,
        decimalPlaces: 0,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Status/distance
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.isActive ? 'ANCHORED' : 'NOT SET',
              style: TextStyle(
                color: state.isActive ? Colors.green : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (state.currentRadius != null)
              Text(
                formatDistance(state.currentRadius),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        // Limit
        if (state.maxRadius != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LIMIT',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                ),
              ),
              Text(
                formatDistance(state.maxRadius),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Color _getAlarmColor(AnchorAlarmState state) {
    switch (state) {
      case AnchorAlarmState.emergency:
        return Colors.red.shade900;
      case AnchorAlarmState.alarm:
        return Colors.red.shade700;
      case AnchorAlarmState.warn:
        return Colors.orange.shade700;
      case AnchorAlarmState.normal:
        return Colors.green;
    }
  }
}

/// Full-screen anchor alarm dialog with all controls
class _AnchorAlarmDialog extends StatefulWidget {
  final AnchorAlarmService alarmService;
  final SignalKService signalKService;
  final Color primaryColor;

  const _AnchorAlarmDialog({
    required this.alarmService,
    required this.signalKService,
    required this.primaryColor,
  });

  @override
  State<_AnchorAlarmDialog> createState() => _AnchorAlarmDialogState();
}

class _AnchorAlarmDialogState extends State<_AnchorAlarmDialog> {
  final MapController _mapController = MapController();
  bool _mapAutoFollow = true;
  double _rodeSliderValue = 30.0;

  @override
  void initState() {
    super.initState();
    widget.alarmService.addListener(_onStateChanged);

    // Initialize slider from current rode length
    final rodeLength = widget.alarmService.state.rodeLength;
    if (rodeLength != null) {
      _rodeSliderValue = rodeLength.clamp(5.0, 100.0);
    }
  }

  @override
  void dispose() {
    widget.alarmService.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});

      // Auto-follow vessel
      if (_mapAutoFollow && widget.alarmService.state.vesselPosition != null) {
        final pos = widget.alarmService.state.vesselPosition!;
        try {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            _mapController.camera.zoom,
          );
        } catch (_) {}
      }
    }
  }

  void _centerOnAnchor() {
    final anchorPos = widget.alarmService.state.anchorPosition;
    if (anchorPos != null) {
      _mapController.move(
        LatLng(anchorPos.latitude, anchorPos.longitude),
        _mapController.camera.zoom,
      );
      setState(() => _mapAutoFollow = false);
    }
  }

  void _centerOnVessel() {
    final vesselPos = widget.alarmService.state.vesselPosition;
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
    final success = await widget.alarmService.dropAnchor();
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
      final success = await widget.alarmService.raiseAnchor();
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
    await widget.alarmService.setRodeLength(length);
  }

  Future<void> _setRadiusFromPosition() async {
    final success = await widget.alarmService.setRadius();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Radius set from current position'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.alarmService.state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Anchor Alarm'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: const [],
        ),
        body: Stack(
          children: [
            // Full map
            Positioned.fill(
              child: _buildFullMap(state, isDark),
            ),

            // Map controls (top right)
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  _buildMapButton(
                    icon: Icons.add,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMapButton(
                    icon: Icons.remove,
                    onPressed: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMapButton(
                    icon: Icons.anchor,
                    onPressed: _centerOnAnchor,
                    tooltip: 'Center on anchor',
                  ),
                  const SizedBox(height: 8),
                  _buildMapButton(
                    icon: _mapAutoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
                    onPressed: _toggleAutoFollow,
                    color: _mapAutoFollow ? widget.primaryColor : null,
                    tooltip: 'Auto-follow vessel',
                  ),
                ],
              ),
            ),

            // Status panel (top left)
            Positioned(
              top: 16,
              left: 16,
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
            if (widget.alarmService.awaitingCheckIn)
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
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    String? tooltip,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(icon, color: color ?? Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildFullMap(AnchorState state, bool isDark) {
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
        if (widget.alarmService.trackHistory.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.alarmService.trackHistory
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
                width: 40,
                height: 40,
                child: const Icon(Icons.anchor, color: Colors.brown, size: 32),
              ),
            // Vessel position
            if (vesselPos != null)
              Marker(
                point: LatLng(vesselPos.latitude, vesselPos.longitude),
                width: 32,
                height: 32,
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
    // Format distance with user's preferred units
    String formatDistance(double? meters, String path) {
      if (meters == null) return '--';
      return ConversionUtils.formatValue(
        widget.signalKService,
        path,
        meters,
        decimalPlaces: 0,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                state.isActive ? Icons.anchor : Icons.anchor_outlined,
                color: state.isActive ? Colors.orange : Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                state.isActive ? 'ANCHORED' : 'NOT SET',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: state.isActive ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          if (state.isActive) ...[
            const Divider(height: 20, color: Colors.white24),
            _buildStatusRow('From Anchor', formatDistance(state.currentRadius, 'navigation.anchor.currentRadius')),
            _buildStatusRow('Alarm At', formatDistance(state.maxRadius, 'navigation.anchor.maxRadius')),
            _buildStatusRow('Rode Out', formatDistance(state.rodeLength, 'navigation.anchor.rodeLength')),
            if (state.bearingDegrees != null)
              _buildStatusRow('To Anchor', '${state.bearingDegrees!.toStringAsFixed(0)}°'),
            if (widget.alarmService.gpsFromBow != null)
              _buildStatusRow('GPS→Bow', formatDistance(widget.alarmService.gpsFromBow, 'sensors.gps.fromBow')),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
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
                  icon: const Icon(Icons.anchor),
                  label: const Text('Drop Anchor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isActive ? _raiseAnchor : null,
                  icon: const Icon(Icons.eject),
                  label: const Text('Raise Anchor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          // Rode length slider (only when active)
          if (state.isActive) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Rode Out:', style: TextStyle(color: Colors.black87, fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  '${displayValue.toStringAsFixed(0)} $unitSymbol',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 18),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Colors.blue,
                inactiveTrackColor: Colors.blue.shade100,
                thumbColor: Colors.blue,
                overlayColor: Colors.blue.withValues(alpha: 0.2),
                valueIndicatorColor: Colors.blue,
              ),
              child: Slider(
                value: _rodeSliderValue,
                min: 5,
                max: 100,
                divisions: 19,
                label: '${displayValue.toStringAsFixed(0)} $unitSymbol',
                onChanged: (value) => setState(() => _rodeSliderValue = value),
                onChangeEnd: _setRodeLength,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _setRadiusFromPosition,
              icon: const Icon(Icons.gps_fixed, color: Colors.blue),
              label: const Text('Set alarm radius from anchor drop', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInOverlay() {
    final deadline = widget.alarmService.checkInDeadline;
    final remaining = deadline != null
        ? deadline.difference(DateTime.now())
        : Duration.zero;

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'ANCHOR WATCH CHECK-IN',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Time remaining: ${_formatDuration(remaining)}',
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => widget.alarmService.acknowledgeCheckIn(),
              icon: const Icon(Icons.check),
              label: const Text("I'm Watching"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmOverlay(AnchorState state) {
    // Format distance with user's preferred units
    final distanceDisplay = state.currentRadius != null
        ? ConversionUtils.formatValue(
            widget.signalKService,
            'navigation.anchor.currentRadius',
            state.currentRadius!,
            decimalPlaces: 0,
          )
        : '--';

    return Container(
      color: Colors.red.shade900.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, size: 100, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              state.alarmMessage ?? 'ANCHOR ALARM',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Distance: $distanceDisplay',
              style: const TextStyle(fontSize: 24, color: Colors.white),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => widget.alarmService.acknowledgeAlarm(),
              icon: const Icon(Icons.check),
              label: const Text('Acknowledge'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
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
