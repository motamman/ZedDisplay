import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Individual satellite data
class SatelliteInfo {
  final int prn;
  final double? elevation; // radians
  final double? azimuth;   // radians
  final double? snr;       // dB

  SatelliteInfo({
    required this.prn,
    this.elevation,
    this.azimuth,
    this.snr,
  });

  /// Get color based on SNR strength
  Color get snrColor {
    if (snr == null) return Colors.grey;
    if (snr! >= 30) return Colors.green;        // Excellent
    if (snr! >= 20) return Colors.lightGreen;   // Good
    if (snr! >= 10) return Colors.orange;       // Weak
    return Colors.red;                           // Very weak
  }
}

/// GNSS Status widget showing satellite info, fix quality, and accuracy
class GnssStatus extends StatelessWidget {
  /// Detailed satellite list with positions and SNR
  final List<SatelliteInfo>? satellites;

  /// Number of satellites in view (fallback if satellites list not provided)
  final int? satellitesInView;

  /// Fix type (e.g., 'DGNSS', 'GPS', 'RTK', 'No Fix')
  final String? fixType;

  /// Horizontal Dilution of Precision
  final double? hdop;

  /// Vertical Dilution of Precision
  final double? vdop;

  /// Position Dilution of Precision
  final double? pdop;

  /// Horizontal accuracy in meters
  final double? horizontalAccuracy;

  /// Vertical accuracy in meters
  final double? verticalAccuracy;

  /// Current latitude
  final double? latitude;

  /// Current longitude
  final double? longitude;

  /// Whether to show the sky view visualization
  final bool showSkyView;

  /// Whether to show accuracy circle
  final bool showAccuracyCircle;

  /// Primary color for the widget
  final Color primaryColor;

  const GnssStatus({
    super.key,
    this.satellites,
    this.satellitesInView,
    this.fixType,
    this.hdop,
    this.vdop,
    this.pdop,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.latitude,
    this.longitude,
    this.showSkyView = true,
    this.showAccuracyCircle = true,
    this.primaryColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fixQuality = _getFixQuality();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with fix status
            _buildHeader(context, fixQuality, isDark),
            const SizedBox(height: 12),

            // Main content
            Expanded(
              child: Row(
                children: [
                  // Left side: Sky view or accuracy circle
                  if (showSkyView || showAccuracyCircle)
                    Expanded(
                      flex: 1,
                      child: _buildVisualization(isDark, fixQuality),
                    ),

                  const SizedBox(width: 12),

                  // Right side: Stats
                  Expanded(
                    flex: 1,
                    child: _buildStats(context, isDark, fixQuality),
                  ),
                ],
              ),
            ),

            // Position display
            if (latitude != null && longitude != null) ...[
              const Divider(),
              _buildPositionDisplay(context, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _FixQuality fixQuality, bool isDark) {
    return Row(
      children: [
        // Satellite icon with status color
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: fixQuality.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.satellite_alt,
            color: fixQuality.color,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),

        // Title and fix type
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GNSS Status',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: fixQuality.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fixType ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 12,
                      color: fixQuality.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Satellite count
        if (satellitesInView != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.satellite,
                  size: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  '$satellitesInView',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildVisualization(bool isDark, _FixQuality fixQuality) {
    if (showAccuracyCircle && horizontalAccuracy != null) {
      return _buildAccuracyCircle(isDark, fixQuality);
    } else if (showSkyView) {
      return _buildSkyView(isDark, fixQuality);
    }
    return const SizedBox.shrink();
  }

  Widget _buildSkyView(bool isDark, _FixQuality fixQuality) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _SkyViewPainter(
                satellites: satellites,
                satelliteCount: satellitesInView ?? satellites?.length ?? 0,
                fixColor: fixQuality.color,
                isDark: isDark,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccuracyCircle(bool isDark, _FixQuality fixQuality) {
    final accuracy = horizontalAccuracy ?? 0;

    // Scale accuracy to display (max 50m displayed)
    final displayRadius = (accuracy / 50.0).clamp(0.1, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring (reference)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.1),
                      width: 2,
                    ),
                  ),
                ),

                // Accuracy circle
                FractionallySizedBox(
                  widthFactor: displayRadius,
                  heightFactor: displayRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fixQuality.color.withValues(alpha: 0.2),
                      border: Border.all(
                        color: fixQuality.color,
                        width: 2,
                      ),
                    ),
                  ),
                ),

                // Center dot (position)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: fixQuality.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: fixQuality.color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

                // Accuracy label
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '±${accuracy.toStringAsFixed(1)}m',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: fixQuality.color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStats(BuildContext context, bool isDark, _FixQuality fixQuality) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // HDOP
        if (hdop != null)
          _buildStatRow(
            'HDOP',
            hdop!.toStringAsFixed(2),
            _getDopColor(hdop!),
            isDark,
          ),

        if (vdop != null) ...[
          const SizedBox(height: 8),
          _buildStatRow(
            'VDOP',
            vdop!.toStringAsFixed(2),
            _getDopColor(vdop!),
            isDark,
          ),
        ],

        if (pdop != null) ...[
          const SizedBox(height: 8),
          _buildStatRow(
            'PDOP',
            pdop!.toStringAsFixed(2),
            _getDopColor(pdop!),
            isDark,
          ),
        ],

        if (horizontalAccuracy != null) ...[
          const SizedBox(height: 8),
          _buildStatRow(
            'H Accuracy',
            '${horizontalAccuracy!.toStringAsFixed(1)}m',
            _getAccuracyColor(horizontalAccuracy!),
            isDark,
          ),
        ],

        if (verticalAccuracy != null) ...[
          const SizedBox(height: 8),
          _buildStatRow(
            'V Accuracy',
            '${verticalAccuracy!.toStringAsFixed(1)}m',
            _getAccuracyColor(verticalAccuracy!),
            isDark,
          ),
        ],

        // Quality indicator
        const SizedBox(height: 12),
        _buildQualityBar(fixQuality, isDark),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQualityBar(_FixQuality fixQuality, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signal Quality',
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fixQuality.quality,
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(fixQuality.color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          fixQuality.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: fixQuality.color,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionDisplay(BuildContext context, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCoordinate('LAT', latitude!, true, isDark),
        Container(
          width: 1,
          height: 30,
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.1),
        ),
        _buildCoordinate('LON', longitude!, false, isDark),
      ],
    );
  }

  Widget _buildCoordinate(String label, double value, bool isLatitude, bool isDark) {
    final formatted = _formatCoordinate(value, isLatitude);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        Text(
          formatted,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  String _formatCoordinate(double value, bool isLatitude) {
    final hemisphere = isLatitude
        ? (value >= 0 ? 'N' : 'S')
        : (value >= 0 ? 'E' : 'W');
    final absValue = value.abs();
    final degrees = absValue.floor();
    final minutes = ((absValue - degrees) * 60);

    return '$degrees° ${minutes.toStringAsFixed(3)}\' $hemisphere';
  }

  _FixQuality _getFixQuality() {
    if (fixType == null || fixType == 'No Fix' || fixType == 'none') {
      return _FixQuality(Colors.red, 0.0, 'No Fix');
    }

    final fix = fixType!.toLowerCase();

    if (fix.contains('rtk') && fix.contains('fixed')) {
      return _FixQuality(primaryColor, 1.0, 'Excellent');
    } else if (fix.contains('rtk')) {
      return _FixQuality(primaryColor.withOpacity(0.8), 0.9, 'Very Good');
    } else if (fix.contains('dgnss') || fix.contains('dgps')) {
      return _FixQuality(primaryColor, 0.8, 'Good');
    } else if (fix.contains('3d') || fix.contains('gps')) {
      return _FixQuality(Colors.orange, 0.6, 'Standard');
    } else if (fix.contains('2d')) {
      return _FixQuality(Colors.orange.shade300, 0.4, 'Fair');
    } else {
      // Calculate from HDOP if available
      if (hdop != null) {
        if (hdop! < 1) return _FixQuality(primaryColor, 0.9, 'Excellent');
        if (hdop! < 2) return _FixQuality(primaryColor, 0.7, 'Good');
        if (hdop! < 5) return _FixQuality(Colors.orange, 0.5, 'Moderate');
        return _FixQuality(Colors.red, 0.3, 'Poor');
      }
      return _FixQuality(Colors.grey, 0.5, 'Unknown');
    }
  }

  Color _getDopColor(double dop) {
    if (dop < 1) return primaryColor;
    if (dop < 2) return primaryColor.withOpacity(0.8);
    if (dop < 5) return Colors.orange;
    if (dop < 10) return Colors.orange.shade700;
    return Colors.red;
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy < 1) return primaryColor;
    if (accuracy < 3) return primaryColor.withOpacity(0.8);
    if (accuracy < 10) return Colors.orange;
    if (accuracy < 25) return Colors.orange.shade700;
    return Colors.red;
  }
}

class _FixQuality {
  final Color color;
  final double quality;
  final String label;

  _FixQuality(this.color, this.quality, this.label);
}

/// Painter for the satellite sky view
class _SkyViewPainter extends CustomPainter {
  final List<SatelliteInfo>? satellites;
  final int satelliteCount;
  final Color fixColor;
  final bool isDark;

  _SkyViewPainter({
    this.satellites,
    required this.satelliteCount,
    required this.fixColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;

    // Draw concentric circles (elevation rings at 0°, 30°, 60°, 90°)
    final ringPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15)
          : Colors.black.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, ringPaint);
    }

    // Draw outer ring (horizon)
    final horizonPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, horizonPaint);

    // Draw compass directions
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final directions = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 - math.pi / 2;
      final x = center.dx + (radius + 12) * math.cos(angle);
      final y = center.dy + (radius + 12) * math.sin(angle);

      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          color: isDark ? Colors.white60 : Colors.black54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Draw satellites with REAL positions and SNR color coding
    if (satellites != null && satellites!.isNotEmpty) {
      final satBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      for (final sat in satellites!) {
        // Skip satellites without position data
        if (sat.elevation == null || sat.azimuth == null) continue;

        // Convert elevation (radians, 0=horizon, pi/2=zenith) to radius
        // Zenith (90°) = center, Horizon (0°) = edge
        final elevationRatio = 1.0 - (sat.elevation! / (math.pi / 2));
        final satRadius = radius * elevationRatio.clamp(0.0, 1.0);

        // Azimuth: 0 = North, increases clockwise
        // Canvas: 0 = East, increases counter-clockwise
        // So we need: canvasAngle = -azimuth + pi/2 (rotate and flip)
        final canvasAngle = -sat.azimuth! + math.pi / 2;

        final x = center.dx + satRadius * math.cos(canvasAngle);
        final y = center.dy - satRadius * math.sin(canvasAngle);

        // Draw satellite dot with SNR-based color
        final satPaint = Paint()
          ..color = sat.snrColor
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(x, y), 5, satPaint);
        canvas.drawCircle(Offset(x, y), 5, satBorderPaint);
      }
    }

    // Center dot (your position)
    final centerPaint = Paint()
      ..color = isDark ? Colors.white : Colors.black87
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3, centerPaint);
  }

  @override
  bool shouldRepaint(_SkyViewPainter oldDelegate) {
    return satellites != oldDelegate.satellites ||
        satelliteCount != oldDelegate.satelliteCount ||
        fixColor != oldDelegate.fixColor ||
        isDark != oldDelegate.isDark;
  }
}
