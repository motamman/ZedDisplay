import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../models/tool.dart';
import '../../services/signalk_service.dart';

/// Base class for tool-specific configuration
/// Each tool type can implement this to provide custom configuration UI
abstract class ToolConfigurator {
  /// The tool type ID this configurator handles
  String get toolTypeId;

  /// Default size (width, height in grid units) for this tool type
  Size get defaultSize => const Size(1, 1);

  /// Build the tool-specific configuration UI
  Widget buildConfigUI(
    BuildContext context,
    SignalKService signalKService,
  );

  /// Get the current configuration as a ToolConfig object
  ToolConfig getConfig();

  /// Load configuration from an existing tool
  void loadFromTool(Tool tool);

  /// Load default values for this tool type
  void loadDefaults(SignalKService signalKService);

  /// Reset all fields to defaults
  void reset();

  /// Validate the configuration
  /// Returns null if valid, error message if invalid
  String? validate();
}
