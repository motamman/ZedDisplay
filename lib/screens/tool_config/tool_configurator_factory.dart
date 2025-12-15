import 'base_tool_configurator.dart';
import 'configurators/chart_configurator.dart';
import 'configurators/gauge_configurator.dart';
import 'configurators/compass_configurator.dart';
import 'configurators/control_configurator.dart';
import 'configurators/polar_chart_configurator.dart';
import 'configurators/webview_configurator.dart';
import 'configurators/system_configurator.dart';
import 'configurators/weather_api_spinner_configurator.dart';
import 'configurators/tanks_configurator.dart';
import 'configurators/weather_alerts_configurator.dart';
import 'configurators/clock_alarm_configurator.dart';
import 'configurators/anchor_alarm_configurator.dart';
import 'configurators/position_display_configurator.dart';
import 'configurators/victron_flow_configurator.dart';

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
      case 'realtime_chart':
        return ChartConfigurator();

      // Compasses and Instruments
      case 'wind_compass':
      case 'autopilot':
        return CompassConfigurator(toolTypeId);

      // Polar Charts
      case 'polar_radar_chart':
      case 'ais_polar_chart':
        return PolarChartConfigurator(toolTypeId);

      // Controls
      case 'slider':
      case 'knob':
      case 'dropdown':
      case 'switch':
      case 'button':
        return ControlConfigurator(toolTypeId);

      // System Tools
      case 'conversion_test':
      case 'rpi_monitor':
      case 'server_manager':
      case 'crew_messages':
      case 'crew_list':
      case 'intercom':
      case 'file_share':
        return SystemConfigurator(toolTypeId);

      // WebView
      case 'webview':
        return WebViewConfigurator();

      // Weather API Spinner
      case 'weather_api_spinner':
        return WeatherApiSpinnerConfigurator();

      // Tanks
      case 'tanks':
        return TanksConfigurator();

      // Weather Alerts
      case 'weather_alerts':
        return WeatherAlertsConfigurator();

      // Clock & Alarm
      case 'clock_alarm':
        return ClockAlarmConfigurator();

      // Anchor Alarm
      case 'anchor_alarm':
        return AnchorAlarmConfigurator();

      // Position Display
      case 'position_display':
        return PositionDisplayConfigurator();

      // Victron Power Flow
      case 'victron_flow':
        return VictronFlowConfigurator();

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
      'realtime_chart',
      'wind_compass',
      'autopilot',
      'polar_radar_chart',
      'ais_polar_chart',
      'slider',
      'knob',
      'dropdown',
      'switch',
      'button',
      'conversion_test',
      'rpi_monitor',
      'server_manager',
      'crew_messages',
      'crew_list',
      'intercom',
      'file_share',
      'webview',
      'weather_api_spinner',
      'tanks',
      'weather_alerts',
      'clock_alarm',
      'anchor_alarm',
      'position_display',
      'victron_flow',
    ];
  }
}
