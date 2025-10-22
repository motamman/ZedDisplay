/// Base class for all tool widgets
library;

import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/signalk_data.dart';
import '../../../services/signalk_service.dart';
import '../../../utils/string_extensions.dart';
import '../../../utils/color_extensions.dart';

/// Abstract base class for tool widgets
///
/// Provides common functionality that all tools can use:
/// - Access to primary data source
/// - Label generation from paths
/// - Color parsing helpers
/// - Empty state handling
///
/// Tools can extend this class to reduce boilerplate and
/// ensure consistent behavior.
abstract class BaseTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const BaseTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  /// Gets the primary (first) data source
  DataSource? get primaryDataSource =>
      config.dataSources.isNotEmpty ? config.dataSources.first : null;

  /// Gets the label for a data source
  ///
  /// Uses the configured label if available, otherwise derives
  /// a readable label from the path.
  String getLabel(DataSource dataSource) =>
      dataSource.label ?? dataSource.path.toReadableLabel();

  /// Gets the primary label (from first data source)
  String? get primaryLabel => primaryDataSource != null
      ? getLabel(primaryDataSource!)
      : null;

  /// Gets the data point for a data source
  SignalKDataPoint? getDataPoint(DataSource dataSource) =>
      signalKService.getValue(dataSource.path, source: dataSource.source);

  /// Gets the primary data point (from first data source)
  SignalKDataPoint? get primaryDataPoint => primaryDataSource != null
      ? getDataPoint(primaryDataSource!)
      : null;

  /// Parses primary color from config with fallback
  Color getPrimaryColor(BuildContext context, {Color? fallback}) {
    final defaultColor = fallback ?? Theme.of(context).colorScheme.primary;
    return config.style.primaryColor?.toColor(fallback: defaultColor) ?? defaultColor;
  }

  /// Parses secondary color from config with fallback
  Color getSecondaryColor(BuildContext context, {Color? fallback}) {
    final defaultColor = fallback ?? Theme.of(context).colorScheme.secondary;
    return config.style.secondaryColor?.toColor(fallback: defaultColor) ?? defaultColor;
  }

  /// Checks if the tool should show its label
  bool get shouldShowLabel => config.style.showLabel == true;

  /// Checks if the tool should show its value
  bool get shouldShowValue => config.style.showValue == true;

  /// Checks if the tool should show units
  bool get shouldShowUnit => config.style.showUnit == true;

  /// Gets a custom property from the config
  T? getCustomProperty<T>(String key, {T? defaultValue}) {
    final value = config.style.customProperties?[key];
    return value is T ? value : defaultValue;
  }

  @override
  Widget build(BuildContext context) {
    // Check for empty data sources
    if (config.dataSources.isEmpty) {
      return buildEmptyState(context);
    }

    return buildTool(context);
  }

  /// Builds the empty state widget when no data sources are configured
  Widget buildEmptyState(BuildContext context) {
    return const Center(
      child: Text('No data source configured'),
    );
  }

  /// Builds the actual tool widget
  ///
  /// Subclasses must implement this to define their specific UI.
  Widget buildTool(BuildContext context);
}
