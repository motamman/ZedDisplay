import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Position data class
class LatLon {
  final double latitude;
  final double longitude;

  const LatLon({required this.latitude, required this.longitude});

  factory LatLon.fromJson(Map<String, dynamic> json) {
    return LatLon(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Route navigation information panel
///
/// Displays next waypoint, distance, time, ETA, and cross-track error
/// for vessels in route/nav mode.
class RouteInfoPanel extends StatelessWidget {
  final LatLon? nextWaypoint;
  final DateTime? eta;
  final double? distanceToWaypoint;  // meters
  final Duration? timeToWaypoint;
  final double? crossTrackError;     // meters
  final bool onlyShowXTEWhenNear;

  const RouteInfoPanel({
    super.key,
    this.nextWaypoint,
    this.eta,
    this.distanceToWaypoint,
    this.timeToWaypoint,
    this.crossTrackError,
    this.onlyShowXTEWhenNear = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          const Text(
            'ROUTE NAVIGATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),

          // Next Waypoint
          _buildInfoRow(
            icon: Icons.location_on,
            label: 'Next WPT',
            value: nextWaypoint != null
                ? _formatLatLon(nextWaypoint!)
                : '--',
          ),

          // Distance to Waypoint
          _buildInfoRow(
            icon: Icons.straighten,
            label: 'DTW',
            value: distanceToWaypoint != null
                ? '${(distanceToWaypoint! / 1852).toStringAsFixed(2)} nm'
                : '--',
          ),

          // Time to Waypoint
          _buildInfoRow(
            icon: Icons.timer,
            label: 'TTW',
            value: timeToWaypoint != null
                ? _formatDuration(timeToWaypoint!)
                : '--',
          ),

          // ETA
          _buildInfoRow(
            icon: Icons.schedule,
            label: 'ETA',
            value: eta != null
                ? DateFormat('HH:mm').format(eta!)
                : '--',
          ),

          // Cross Track Error (only show if < 10nm when onlyShowXTEWhenNear is true)
          if (crossTrackError != null &&
              (!onlyShowXTEWhenNear || crossTrackError!.abs() < 18520)) // 10nm in meters
            _buildInfoRow(
              icon: Icons.compare_arrows,
              label: 'XTE',
              value: '${(crossTrackError! / 1852).toStringAsFixed(3)} nm',
              valueColor: crossTrackError! < 0 ? Colors.red : Colors.green,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white60),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLatLon(LatLon coord) {
    final lat = coord.latitude;
    final lon = coord.longitude;

    final latDeg = lat.abs().floor();
    final latMin = ((lat.abs() - latDeg) * 60).toStringAsFixed(2);
    final latDir = lat >= 0 ? 'N' : 'S';

    final lonDeg = lon.abs().floor();
    final lonMin = ((lon.abs() - lonDeg) * 60).toStringAsFixed(2);
    final lonDir = lon >= 0 ? 'E' : 'W';

    return '$latDeg°$latMin\'$latDir $lonDeg°$lonMin\'$lonDir';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
}
