import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tool_config.dart';
import '../services/signalk_service.dart';

/// Service for handling tool configuration operations including
/// JSON building, SignalK webapp loading, and config serialization
class ToolConfigService {
  /// Build customProperties map for a specific tool type
  /// This centralizes the complex JSON building logic that was duplicated
  /// between the save and preview methods
  static Map<String, dynamic>? buildCustomProperties({
    required String toolTypeId,
    required String chartDuration,
    required int? chartResolution,
    required bool chartShowLegend,
    required bool chartShowGrid,
    required bool chartAutoRefresh,
    required int chartRefreshInterval,
    required String chartStyle,
    required bool chartShowMovingAverage,
    required int chartMovingAverageWindow,
    required String chartTitle,
    required int polarHistorySeconds,
    required double aisMaxRangeNm,
    required int aisUpdateInterval,
    required int sliderDecimalPlaces,
    required double dropdownStepSize,
    required bool showAWANumbers,
    required bool enableVMG,
    required bool headingTrue,
    required bool invertRudder,
    required int fadeDelaySeconds,
    required String webViewUrl,
    required int divisions,
    required String orientation,
    required bool showTickLabels,
    required bool pointerOnly,
    required String gaugeStyle,
    required String linearGaugeStyle,
    required String compassStyle,
  }) {
    switch (toolTypeId) {
      case 'historical_chart':
        return {
          'duration': chartDuration,
          'resolution': chartResolution,
          'showLegend': chartShowLegend,
          'showGrid': chartShowGrid,
          'autoRefresh': chartAutoRefresh,
          'refreshInterval': chartRefreshInterval,
          'chartStyle': chartStyle,
          'showMovingAverage': chartShowMovingAverage,
          'movingAverageWindow': chartMovingAverageWindow,
        };

      case 'realtime_chart':
        return {
          'title': chartTitle,
          'showMovingAverage': chartShowMovingAverage,
          'movingAverageWindow': chartMovingAverageWindow,
        };

      case 'polar_radar_chart':
        return {
          'historySeconds': polarHistorySeconds,
          'showLabels': true,
          'showGrid': true,
        };

      case 'ais_polar_chart':
        return {
          'maxRangeNm': aisMaxRangeNm,
          'updateInterval': aisUpdateInterval * 1000, // Convert to milliseconds
          'showLabels': true,
          'showGrid': true,
        };

      case 'slider':
      case 'knob':
        return {
          'decimalPlaces': sliderDecimalPlaces,
        };

      case 'dropdown':
        return {
          'decimalPlaces': sliderDecimalPlaces,
          'stepSize': dropdownStepSize,
        };

      case 'wind_compass':
        return {
          'showAWANumbers': showAWANumbers,
          'enableVMG': enableVMG,
        };

      case 'autopilot':
        return {
          'headingTrue': headingTrue,
          'invertRudder': invertRudder,
          'fadeDelaySeconds': fadeDelaySeconds,
          'enableVMG': enableVMG,
        };

      case 'webview':
        return {
          'url': webViewUrl,
        };

      default:
        // Gauge-specific properties (radial_gauge, linear_gauge, compass, etc.)
        final properties = {
          'divisions': divisions,
          'orientation': orientation,
          'showTickLabels': showTickLabels,
          'pointerOnly': pointerOnly,
        };

        // Add style variant based on tool type
        if (toolTypeId == 'radial_gauge') {
          properties['gaugeStyle'] = gaugeStyle;
        } else if (toolTypeId == 'linear_gauge') {
          properties['gaugeStyle'] = linearGaugeStyle;
        } else if (toolTypeId == 'compass') {
          properties['compassStyle'] = compassStyle;
        }

        return properties;
    }
  }

  /// Build a complete ToolConfig from UI state
  static ToolConfig buildToolConfig({
    required List<DataSource> dataSources,
    required String toolTypeId,
    required double? minValue,
    required double? maxValue,
    required String? unit,
    required String? primaryColor,
    required double? fontSize,
    required bool showLabel,
    required bool showValue,
    required bool showUnit,
    required int? ttlSeconds,
    required double? laylineAngle,
    required double? targetTolerance,
    required String chartDuration,
    required int? chartResolution,
    required bool chartShowLegend,
    required bool chartShowGrid,
    required bool chartAutoRefresh,
    required int chartRefreshInterval,
    required String chartStyle,
    required bool chartShowMovingAverage,
    required int chartMovingAverageWindow,
    required String chartTitle,
    required int polarHistorySeconds,
    required double aisMaxRangeNm,
    required int aisUpdateInterval,
    required int sliderDecimalPlaces,
    required double dropdownStepSize,
    required bool showAWANumbers,
    required bool enableVMG,
    required bool headingTrue,
    required bool invertRudder,
    required int fadeDelaySeconds,
    required String webViewUrl,
    required int divisions,
    required String orientation,
    required bool showTickLabels,
    required bool pointerOnly,
    required String gaugeStyle,
    required String linearGaugeStyle,
    required String compassStyle,
  }) {
    final customProperties = buildCustomProperties(
      toolTypeId: toolTypeId,
      chartDuration: chartDuration,
      chartResolution: chartResolution,
      chartShowLegend: chartShowLegend,
      chartShowGrid: chartShowGrid,
      chartAutoRefresh: chartAutoRefresh,
      chartRefreshInterval: chartRefreshInterval,
      chartStyle: chartStyle,
      chartShowMovingAverage: chartShowMovingAverage,
      chartMovingAverageWindow: chartMovingAverageWindow,
      chartTitle: chartTitle,
      polarHistorySeconds: polarHistorySeconds,
      aisMaxRangeNm: aisMaxRangeNm,
      aisUpdateInterval: aisUpdateInterval,
      sliderDecimalPlaces: sliderDecimalPlaces,
      dropdownStepSize: dropdownStepSize,
      showAWANumbers: showAWANumbers,
      enableVMG: enableVMG,
      headingTrue: headingTrue,
      invertRudder: invertRudder,
      fadeDelaySeconds: fadeDelaySeconds,
      webViewUrl: webViewUrl,
      divisions: divisions,
      orientation: orientation,
      showTickLabels: showTickLabels,
      pointerOnly: pointerOnly,
      gaugeStyle: gaugeStyle,
      linearGaugeStyle: linearGaugeStyle,
      compassStyle: compassStyle,
    );

    return ToolConfig(
      dataSources: dataSources,
      style: StyleConfig(
        minValue: minValue,
        maxValue: maxValue,
        unit: unit?.trim().isEmpty == true ? null : unit,
        primaryColor: primaryColor,
        fontSize: fontSize,
        showLabel: showLabel,
        showValue: showValue,
        showUnit: showUnit,
        ttlSeconds: ttlSeconds,
        laylineAngle: (toolTypeId == 'wind_compass' || toolTypeId == 'autopilot')
            ? laylineAngle
            : null,
        targetTolerance: (toolTypeId == 'wind_compass' || toolTypeId == 'autopilot')
            ? targetTolerance
            : null,
        customProperties: customProperties,
      ),
    );
  }

  /// Load SignalK webapps from the server
  /// Returns a list of webapp metadata maps
  static Future<List<Map<String, String>>> loadSignalKWebApps(
    SignalKService signalKService,
  ) async {
    final serverUrl = signalKService.serverUrl;
    final useSecure = signalKService.useSecureConnection;

    if (serverUrl.isEmpty) {
      throw Exception('Not connected to SignalK server');
    }

    final protocol = useSecure ? 'https' : 'http';
    final url = Uri.parse('$protocol://$serverUrl/webapps');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> webapps = json.decode(response.body);

      return webapps.map((app) {
        final name = app['name'] as String? ?? 'Unknown';
        final version = app['version'] as String? ?? '';
        final description = app['description'] as String?;
        final location = app['location'] as String? ?? '';

        // Build full URL
        final webappUrl = '$protocol://$serverUrl$location';

        return {
          'name': name,
          'version': version,
          'description': description ?? 'Version $version',
          'url': webappUrl,
        };
      }).toList();
    } else {
      throw Exception('Failed to load webapps: ${response.statusCode}');
    }
  }
}
