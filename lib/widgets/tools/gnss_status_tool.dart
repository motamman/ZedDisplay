import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../gnss_status.dart';

/// Config-driven GNSS status tool showing satellite info and fix quality
class GnssStatusTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const GnssStatusTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Default paths (only paths that commonly exist)
  // Optional paths (indexes 3-6) may not exist on all systems
  static const _defaultPaths = [
    'navigation.gnss.satellites',        // 0: satellite count
    'navigation.gnss.methodQuality',     // 1: fix type
    'navigation.gnss.horizontalDilution', // 2: HDOP
    '',  // 3: optional - verticalDilution (VDOP)
    '',  // 4: optional - positionDilution (PDOP)
    '',  // 5: optional - horizontalAccuracy
    '',  // 6: optional - verticalAccuracy
    'navigation.position',               // 7: position
    'navigation.gnss.satellitesInView',  // 8: detailed satellite list with positions/SNR
  ];

  /// Get path at index, using default if not configured
  /// Returns empty string if path is optional and not configured
  String _getPath(int index) {
    if (config.dataSources.length > index && config.dataSources[index].path.isNotEmpty) {
      return config.dataSources[index].path;
    }
    return _defaultPaths[index];
  }

  @override
  Widget build(BuildContext context) {
    // Expected data sources (in order):
    // 0: navigation.gnss.satellites - satellite count
    // 1: navigation.gnss.methodQuality - fix type string
    // 2: navigation.gnss.horizontalDilution - HDOP
    // 3: navigation.gnss.verticalDilution - VDOP
    // 4: navigation.gnss.positionDilution - PDOP
    // 5: navigation.gnss.horizontalAccuracy - horizontal accuracy in meters
    // 6: navigation.gnss.verticalAccuracy - vertical accuracy in meters
    // 7: navigation.position - position object with latitude/longitude

    // Get configuration
    final style = config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.green,
    ) ?? Colors.green;

    // Get custom properties
    final showSkyView = style.customProperties?['showSkyView'] as bool? ?? true;
    final showAccuracyCircle = style.customProperties?['showAccuracyCircle'] as bool? ?? true;

    // Get satellites (index 0)
    int? satellitesInView;
    final satData = signalKService.getValue(_getPath(0));
    if (satData?.value is num) {
      satellitesInView = (satData!.value as num).toInt();
    }

    // Get fix type / method quality (index 1)
    String? fixType;
    final methodData = signalKService.getValue(_getPath(1));
    if (methodData?.value is String) {
      fixType = methodData!.value as String;
    }

    // Get HDOP (index 2)
    double? hdop;
    final hdopData = signalKService.getValue(_getPath(2));
    if (hdopData?.value is num) {
      hdop = (hdopData!.value as num).toDouble();
    }

    // Get VDOP (index 3) - optional
    double? vdop;
    final vdopPath = _getPath(3);
    if (vdopPath.isNotEmpty) {
      final vdopData = signalKService.getValue(vdopPath);
      if (vdopData?.value is num) {
        vdop = (vdopData!.value as num).toDouble();
      }
    }

    // Get PDOP (index 4) - optional
    double? pdop;
    final pdopPath = _getPath(4);
    if (pdopPath.isNotEmpty) {
      final pdopData = signalKService.getValue(pdopPath);
      if (pdopData?.value is num) {
        pdop = (pdopData!.value as num).toDouble();
      }
    }

    // Get horizontal accuracy (index 5) - optional
    double? horizontalAccuracy;
    final hAccPath = _getPath(5);
    if (hAccPath.isNotEmpty) {
      final hAccData = signalKService.getValue(hAccPath);
      if (hAccData?.value is num) {
        horizontalAccuracy = (hAccData!.value as num).toDouble();
      }
    }

    // Get vertical accuracy (index 6) - optional
    double? verticalAccuracy;
    final vAccPath = _getPath(6);
    if (vAccPath.isNotEmpty) {
      final vAccData = signalKService.getValue(vAccPath);
      if (vAccData?.value is num) {
        verticalAccuracy = (vAccData!.value as num).toDouble();
      }
    }

    // Get position (index 7)
    double? latitude;
    double? longitude;
    DateTime? dataTimestamp;
    final posData = signalKService.getValue(_getPath(7));
    if (posData?.value is Map) {
      final pos = posData!.value as Map<String, dynamic>;
      if (pos['latitude'] is num) {
        latitude = (pos['latitude'] as num).toDouble();
      }
      if (pos['longitude'] is num) {
        longitude = (pos['longitude'] as num).toDouble();
      }
      // Use position timestamp as the data age indicator
      dataTimestamp = posData.timestamp;
    }

    // Get satellitesInView (index 8) - detailed satellite list
    List<SatelliteInfo>? satellites;
    final satInViewPath = _getPath(8);
    if (satInViewPath.isNotEmpty) {
      final satInViewData = signalKService.getValue(satInViewPath);
      if (satInViewData?.value != null) {
        satellites = _parseSatellitesInView(satInViewData!.value);
      }
    }

    return GnssStatus(
      satellites: satellites,
      satellitesInView: satellitesInView,
      fixType: fixType,
      hdop: hdop,
      vdop: vdop,
      pdop: pdop,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: verticalAccuracy,
      latitude: latitude,
      longitude: longitude,
      dataTimestamp: dataTimestamp,
      showSkyView: showSkyView,
      showAccuracyCircle: showAccuracyCircle,
      primaryColor: primaryColor,
    );
  }

  /// Parse satellitesInView from SignalK data
  /// Structure: { satellites: [...], count: N, ... }
  List<SatelliteInfo> _parseSatellitesInView(dynamic data) {
    final satellites = <SatelliteInfo>[];

    if (data is Map) {
      // Get satellites array from the value object
      final satList = data['satellites'];
      if (satList is List) {
        for (final sat in satList) {
          if (sat is Map) {
            final prn = (sat['id'] is num ? (sat['id'] as num).toInt() : null) ??
                        (sat['PRNnumber'] is num ? (sat['PRNnumber'] as num).toInt() : null) ?? 0;
            final elevation = sat['elevation'] is num ? (sat['elevation'] as num).toDouble() : null;
            final azimuth = sat['azimuth'] is num ? (sat['azimuth'] as num).toDouble() : null;
            final snr = sat['SNR'] is num ? (sat['SNR'] as num).toDouble() : null;

            if (prn > 0) {
              satellites.add(SatelliteInfo(
                prn: prn,
                elevation: elevation,
                azimuth: azimuth,
                snr: snr,
              ));
            }
          }
        }
      }
    } else if (data is List) {
      // Direct list format (fallback)
      for (final sat in data) {
        if (sat is Map) {
          final prn = sat['PRNnumber'] as int? ?? sat['id'] as int? ?? 0;
          final elevation = sat['elevation'] is num ? (sat['elevation'] as num).toDouble() : null;
          final azimuth = sat['azimuth'] is num ? (sat['azimuth'] as num).toDouble() : null;
          final snr = sat['SNRatio'] is num ? (sat['SNRatio'] as num).toDouble() : null;

          if (prn > 0) {
            satellites.add(SatelliteInfo(
              prn: prn,
              elevation: elevation,
              azimuth: azimuth,
              snr: snr,
            ));
          }
        }
      }
    }

    return satellites;
  }
}

/// Builder for GNSS status tool
class GnssStatusToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'gnss_status',
      name: 'GNSS Status',
      description: 'Satellite status, fix quality, DOP values, and position accuracy',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 9,
        styleOptions: const [
          'primaryColor',
          'showSkyView',
          'showAccuracyCircle',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'navigation.gnss.satellites', label: 'Sat Count'),
        DataSource(path: 'navigation.gnss.methodQuality', label: 'Fix Type'),
        DataSource(path: 'navigation.gnss.horizontalDilution', label: 'HDOP'),
        DataSource(path: '', label: 'VDOP (optional)'),
        DataSource(path: '', label: 'PDOP (optional)'),
        DataSource(path: '', label: 'H Accuracy (optional)'),
        DataSource(path: '', label: 'V Accuracy (optional)'),
        DataSource(path: 'navigation.position', label: 'Position'),
        DataSource(path: 'navigation.gnss.satellitesInView', label: 'Sat Details'),
      ],
      style: StyleConfig(
        customProperties: {
          'showSkyView': true,
          'showAccuracyCircle': true,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return GnssStatusTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
