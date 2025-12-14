import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Position Display Tool - Shows latitude and longitude
///
/// Displays vessel position in configurable formats:
/// - Decimal Degrees (DD): 47.605867°
/// - Degrees Decimal Minutes (DDM): 47° 36.352'
/// - Degrees Minutes Seconds (DMS): 47° 36' 21.12"
class PositionDisplayTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const PositionDisplayTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<PositionDisplayTool> createState() => _PositionDisplayToolState();
}

class _PositionDisplayToolState extends State<PositionDisplayTool> {
  // Default path
  static const _defaultPath = 'navigation.position';

  String get _positionPath {
    if (widget.config.dataSources.isNotEmpty &&
        widget.config.dataSources[0].path.isNotEmpty) {
      return widget.config.dataSources[0].path;
    }
    return _defaultPath;
  }

  String get _format {
    return widget.config.style.customProperties?['format'] as String? ?? 'ddm';
  }

  bool get _showLabels {
    return widget.config.style.customProperties?['showLabels'] as bool? ?? true;
  }

  bool get _compactMode {
    return widget.config.style.customProperties?['compactMode'] as bool? ?? false;
  }

  @override
  void initState() {
    super.initState();
    widget.signalKService.addListener(_onDataUpdate);
  }

  @override
  void dispose() {
    widget.signalKService.removeListener(_onDataUpdate);
    super.dispose();
  }

  void _onDataUpdate() {
    if (mounted) setState(() {});
  }

  (double?, double?) _getPosition() {
    final posData = widget.signalKService.getValue(_positionPath);
    if (posData?.value is Map) {
      final posMap = posData!.value as Map;
      final lat = posMap['latitude'];
      final lon = posMap['longitude'];
      if (lat is num && lon is num) {
        return (lat.toDouble(), lon.toDouble());
      }
    }
    return (null, null);
  }

  String _formatLatitude(double lat) {
    final hemisphere = lat >= 0 ? 'N' : 'S';
    final absLat = lat.abs();

    switch (_format) {
      case 'dd':
        return '${absLat.toStringAsFixed(6)}° $hemisphere';
      case 'dms':
        return '${_toDMS(absLat)} $hemisphere';
      case 'ddm':
      default:
        return '${_toDDM(absLat)} $hemisphere';
    }
  }

  String _formatLongitude(double lon) {
    final hemisphere = lon >= 0 ? 'E' : 'W';
    final absLon = lon.abs();

    switch (_format) {
      case 'dd':
        return '${absLon.toStringAsFixed(6)}° $hemisphere';
      case 'dms':
        return '${_toDMS(absLon)} $hemisphere';
      case 'ddm':
      default:
        return '${_toDDM(absLon)} $hemisphere';
    }
  }

  /// Convert to Degrees Decimal Minutes (DDM): 47° 36.352'
  String _toDDM(double decimal) {
    final degrees = decimal.floor();
    final minutes = (decimal - degrees) * 60;
    return "$degrees° ${minutes.toStringAsFixed(3)}'";
  }

  /// Convert to Degrees Minutes Seconds (DMS): 47° 36' 21.12"
  String _toDMS(double decimal) {
    final degrees = decimal.floor();
    final minutesDecimal = (decimal - degrees) * 60;
    final minutes = minutesDecimal.floor();
    final seconds = (minutesDecimal - minutes) * 60;
    return "$degrees° $minutes' ${seconds.toStringAsFixed(2)}\"";
  }

  @override
  Widget build(BuildContext context) {
    final (lat, lon) = _getPosition();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white60 : Colors.black54;

    // Get primary color from config
    Color primaryColor = Colors.blue;
    final colorStr = widget.config.style.primaryColor;
    if (colorStr != null && colorStr.startsWith('#')) {
      try {
        primaryColor = Color(int.parse(colorStr.substring(1), radix: 16) | 0xFF000000);
      } catch (_) {}
    }

    if (lat == null || lon == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 32, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'No position data',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final latText = _formatLatitude(lat);
    final lonText = _formatLongitude(lon);

    if (_compactMode) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                latText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                lonText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 300;
        final fontSize = constraints.maxHeight > 100 ? 20.0 : 16.0;

        if (isWide) {
          // Horizontal layout
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCoordinate(
                  label: 'LAT',
                  value: latText,
                  icon: Icons.north,
                  color: primaryColor,
                  textColor: textColor,
                  labelColor: labelColor,
                  fontSize: fontSize,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: labelColor.withValues(alpha: 0.3),
                ),
                _buildCoordinate(
                  label: 'LON',
                  value: lonText,
                  icon: Icons.east,
                  color: primaryColor,
                  textColor: textColor,
                  labelColor: labelColor,
                  fontSize: fontSize,
                ),
              ],
            ),
          );
        } else {
          // Vertical layout
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCoordinate(
                  label: 'LAT',
                  value: latText,
                  icon: Icons.north,
                  color: primaryColor,
                  textColor: textColor,
                  labelColor: labelColor,
                  fontSize: fontSize,
                  horizontal: true,
                ),
                const SizedBox(height: 8),
                _buildCoordinate(
                  label: 'LON',
                  value: lonText,
                  icon: Icons.east,
                  color: primaryColor,
                  textColor: textColor,
                  labelColor: labelColor,
                  fontSize: fontSize,
                  horizontal: true,
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildCoordinate({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color textColor,
    required Color labelColor,
    required double fontSize,
    bool horizontal = false,
  }) {
    if (!_showLabels) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: textColor,
          ),
        ),
      );
    }

    if (horizontal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Builder for Position Display Tool
class PositionDisplayToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'position_display',
      name: 'Position Display',
      description: 'Display vessel position (latitude/longitude) in various formats',
      category: ToolCategory.display,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 1,
        styleOptions: const [],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.position', label: 'Position'),
      ],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'format': 'ddm', // dd, ddm, dms
          'showLabels': true,
          'compactMode': false,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return PositionDisplayTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
