import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for historical chart tool
class ChartConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'historical_chart';

  @override
  Size get defaultSize => const Size(4, 3);

  // Chart-specific state variables (10 total)
  String chartStyle = 'area'; // area, line, column, stepLine
  String chartDuration = '1h';
  int? chartResolution; // null means auto
  bool chartShowLegend = true;
  bool chartShowGrid = true;
  bool chartAutoRefresh = false;
  int chartRefreshInterval = 60;
  bool chartShowMovingAverage = false;
  int chartMovingAverageWindow = 5;
  String chartTitle = '';

  @override
  void reset() {
    chartStyle = 'area';
    chartDuration = '1h';
    chartResolution = null;
    chartShowLegend = true;
    chartShowGrid = true;
    chartAutoRefresh = false;
    chartRefreshInterval = 60;
    chartShowMovingAverage = false;
    chartMovingAverageWindow = 5;
    chartTitle = '';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    // Use default values (already set in field declarations)
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      chartStyle = style.customProperties!['chartStyle'] as String? ?? 'area';
      chartDuration = style.customProperties!['duration'] as String? ?? '1h';
      chartResolution = style.customProperties!['resolution'] as int?;
      chartShowLegend = style.customProperties!['showLegend'] as bool? ?? true;
      chartShowGrid = style.customProperties!['showGrid'] as bool? ?? true;
      chartAutoRefresh = style.customProperties!['autoRefresh'] as bool? ?? false;
      chartRefreshInterval = style.customProperties!['refreshInterval'] as int? ?? 60;
      chartShowMovingAverage = style.customProperties!['showMovingAverage'] as bool? ?? false;
      chartMovingAverageWindow = style.customProperties!['movingAverageWindow'] as int? ?? 5;
      chartTitle = style.customProperties!['title'] as String? ?? '';
    }
  }

  @override
  ToolConfig getConfig() {
    // Will implement this after we see how ToolConfig is structured
    throw UnimplementedError('getConfig() will be implemented after UI');
  }

  @override
  String? validate() {
    if (chartRefreshInterval < 1) {
      return 'Refresh interval must be at least 1 second';
    }
    if (chartMovingAverageWindow < 2) {
      return 'Moving average window must be at least 2';
    }
    return null;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    // Will implement UI in next step
    return const Center(child: Text('Chart Config UI - Coming next'));
  }
}
