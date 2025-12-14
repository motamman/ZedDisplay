import 'package:flutter/widgets.dart';
import '../models/tool_definition.dart';
import '../models/tool_config.dart';
import '../services/signalk_service.dart';
import '../widgets/tools/radial_gauge_tool.dart';
import '../widgets/tools/compass_gauge_tool.dart';
import '../widgets/tools/text_display_tool.dart';
import '../widgets/tools/linear_gauge_tool.dart';
import '../widgets/tools/historical_chart_tool.dart';
import '../widgets/tools/switch_tool.dart';
import '../widgets/tools/slider_tool.dart';
import '../widgets/tools/knob_tool.dart';
import '../widgets/tools/checkbox_tool.dart';
import '../widgets/tools/dropdown_tool.dart';
import '../widgets/tools/realtime_chart_tool.dart';
import '../widgets/tools/radial_bar_chart_tool.dart';
import '../widgets/tools/autopilot_tool.dart';
import '../widgets/tools/autopilot_simple_tool.dart';
import '../widgets/tools/polar_radar_chart_tool.dart';
import '../widgets/tools/ais_polar_chart_tool.dart';
import '../widgets/tools/wind_compass_tool.dart';
import '../widgets/tools/conversion_test_tool.dart';
import '../widgets/tools/server_manager_tool.dart';
import '../widgets/tools/rpi_monitor_tool.dart';
import '../widgets/tools/system_monitor_tool.dart';
import '../widgets/tools/attitude_indicator_tool.dart';
import '../widgets/tools/gnss_status_tool.dart';
import '../widgets/tools/weatherflow_forecast_tool.dart';
import '../widgets/tools/forecast_spinner_tool.dart';
import '../widgets/tools/crew_messages_tool.dart';
import '../widgets/tools/crew_list_tool.dart';
import '../widgets/tools/intercom_tool.dart';
import '../widgets/tools/file_share_tool.dart';
import '../widgets/tools/weather_api_spinner_tool.dart';
import '../widgets/tools/tanks_tool.dart';
import '../widgets/tools/weather_alerts_tool.dart';
import '../widgets/tools/clock_alarm_tool.dart';
import '../widgets/tools/anchor_alarm_tool.dart';
import '../widgets/tools/position_display_tool.dart';

/// Abstract builder for tool widgets
abstract class ToolBuilder {
  /// Get the definition for this tool type
  ToolDefinition getDefinition();

  /// Build a widget instance with the given configuration
  Widget build(ToolConfig config, SignalKService signalKService);

  /// Get default config for this tool type (optional)
  /// Returns null if no defaults needed
  ToolConfig? getDefaultConfig(String vesselId) => null;
}

/// Registry for all available tool types
class ToolRegistry {
  static final ToolRegistry _instance = ToolRegistry._internal();
  factory ToolRegistry() => _instance;
  ToolRegistry._internal();

  final Map<String, ToolBuilder> _builders = {};

  /// Register a tool builder
  void register(String toolTypeId, ToolBuilder builder) {
    _builders[toolTypeId] = builder;
  }

  /// Build a tool widget from configuration
  Widget buildTool(String toolTypeId, ToolConfig config, SignalKService service) {
    final builder = _builders[toolTypeId];
    if (builder == null) {
      return Center(
        child: Text(
          'Unknown tool: $toolTypeId',
          style: const TextStyle(color: Color(0xFFFF0000)),
        ),
      );
    }
    return builder.build(config, service);
  }

  /// Get definition for a tool type
  ToolDefinition? getDefinition(String toolTypeId) {
    return _builders[toolTypeId]?.getDefinition();
  }

  /// Get all registered tool types
  List<ToolDefinition> getAllDefinitions() {
    return _builders.values.map((b) => b.getDefinition()).toList();
  }

  /// Get all tool type IDs
  List<String> getAllToolTypeIds() {
    return _builders.keys.toList();
  }

  /// Check if a tool type is registered
  bool isRegistered(String toolTypeId) {
    return _builders.containsKey(toolTypeId);
  }

  /// Get default config for a tool type
  ToolConfig? getDefaultConfig(String toolTypeId, String vesselId) {
    return _builders[toolTypeId]?.getDefaultConfig(vesselId);
  }

  /// Clear all registered tools (mainly for testing)
  void clear() {
    _builders.clear();
  }

  /// Register all default/built-in tools
  void registerDefaults() {
    register('radial_gauge', RadialGaugeBuilder());
    register('compass', CompassGaugeBuilder());
    register('text_display', TextDisplayBuilder());
    register('linear_gauge', LinearGaugeBuilder());
    register('historical_chart', HistoricalChartBuilder());
    register('realtime_chart', RealtimeChartBuilder());
    register('radial_bar_chart', RadialBarChartBuilder());
    register('switch', SwitchToolBuilder());
    register('slider', SliderToolBuilder());
    register('knob', KnobToolBuilder());
    register('checkbox', CheckboxToolBuilder());
    register('dropdown', DropdownToolBuilder());
    register('autopilot', AutopilotToolBuilder());
    register('autopilot_simple', AutopilotSimpleToolBuilder());
    register('polar_radar_chart', PolarRadarChartBuilder());
    register('ais_polar_chart', AISPolarChartBuilder());
    register('wind_compass', WindCompassToolBuilder());
    register('conversion_test', ConversionTestToolBuilder());
    register('server_manager', ServerManagerToolBuilder());
    register('rpi_monitor', RpiMonitorToolBuilder());
    register('system_monitor', SystemMonitorBuilder());
    register('attitude_indicator', AttitudeIndicatorToolBuilder());
    register('gnss_status', GnssStatusToolBuilder());
    register('weatherflow_forecast', WeatherFlowForecastToolBuilder());
    register('forecast_spinner', ForecastSpinnerToolBuilder());
    register('crew_messages', CrewMessagesToolBuilder());
    register('crew_list', CrewListToolBuilder());
    register('intercom', IntercomToolBuilder());
    register('file_share', FileShareToolBuilder());
    register('weather_api_spinner', WeatherApiSpinnerToolBuilder());
    register('tanks', TanksToolBuilder());
    register('weather_alerts', WeatherAlertsToolBuilder());
    register('clock_alarm', ClockAlarmToolBuilder());
    register('anchor_alarm', AnchorAlarmToolBuilder());
    register('position_display', PositionDisplayToolBuilder());
    // register('webview', WebViewToolBuilder()); // Hidden for now - uncomment to enable
  }
}
