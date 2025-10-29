import 'base_tool_configurator.dart';
import 'configurators/chart_configurator.dart';
import 'configurators/gauge_configurator.dart';

/// Factory for creating tool-specific configurators
///
/// Returns null for tool types that don't have custom configurators
/// (they will use the default configuration UI)
class ToolConfiguratorFactory {
  /// Create a configurator for the given tool type
  /// Returns null if no custom configurator exists for this tool type
  static ToolConfigurator? create(String toolTypeId) {
    switch (toolTypeId) {
      // Gauges
      case 'radial_gauge':
      case 'linear_gauge':
        return GaugeConfigurator(toolTypeId);

      // Charts
      case 'historical_chart':
        return ChartConfigurator();

      // Compasses and Instruments
      case 'wind_compass':
      case 'autopilot':
        // TODO: return CompassConfigurator(toolTypeId);
        return null;

      // Polar Charts
      case 'polar_radar_chart':
      case 'ais_polar_chart':
        // TODO: return PolarChartConfigurator(toolTypeId);
        return null;

      // Controls
      case 'slider':
      case 'dropdown':
      case 'switch':
      case 'button':
        // TODO: return ControlConfigurator(toolTypeId);
        return null;

      // System Tools
      case 'conversion_test':
      case 'rpi_monitor':
      case 'server_manager':
        // TODO: return SystemConfigurator(toolTypeId);
        return null;

      // WebView
      case 'webview':
        // TODO: return WebViewConfigurator();
        return null;

      // No custom configurator - use default UI
      default:
        return null;
    }
  }

  /// Get list of all tool types that have custom configurators
  static List<String> getConfiguratorToolTypes() {
    return [
      'radial_gauge',
      'linear_gauge',
      'historical_chart',
      'wind_compass',
      'autopilot',
      'polar_radar_chart',
      'ais_polar_chart',
      'slider',
      'dropdown',
      'switch',
      'button',
      'conversion_test',
      'rpi_monitor',
      'server_manager',
      'webview',
    ];
  }
}
