import 'package:flutter/material.dart';
import '../services/signalk_service.dart';
import 'base_plugin_configurator.dart';

// Import generated configurators here:
// import 'configurators/signalk_autopilot_configurator.dart';

/// Factory function type for creating plugin configurators.
typedef PluginConfiguratorFactory = BasePluginConfigurator Function({
  Key? key,
  required SignalKService signalKService,
  required String pluginId,
  required Map<String, dynamic> initialConfig,
  VoidCallback? onSaved,
});

/// Registry that maps SignalK plugin IDs to their native Flutter configurators.
///
/// When a native configurator is available for a plugin, it provides a better
/// user experience than the WebView fallback. Native configurators:
/// - Load faster
/// - Follow the app's theme
/// - Can provide custom validation and help text
/// - Support offline editing
///
/// ## Adding a New Configurator
///
/// 1. Create a new file in `lib/plugin_configurators/configurators/`
/// 2. Extend [BasePluginConfigurator] and mix in [PluginConfigFormBuilders]
/// 3. Register it in [_configurators] below
///
/// ## Using the /build-plugin-config Skill
///
/// The Claude Code skill can generate configurator code automatically:
/// ```
/// /build-plugin-config signalk-autopilot
/// ```
///
/// This fetches the plugin's JSON schema and generates a tailored configurator.
class PluginConfiguratorRegistry {
  /// Private constructor - this class provides only static methods
  PluginConfiguratorRegistry._();

  /// Maps plugin IDs to their configurator factory functions.
  ///
  /// Add new configurators here after generating them with /build-plugin-config.
  /// Example entry:
  /// ```dart
  /// 'signalk-autopilot': ({
  ///   Key? key,
  ///   required SignalKService signalKService,
  ///   required String pluginId,
  ///   required Map<String, dynamic> initialConfig,
  ///   VoidCallback? onSaved,
  /// }) => SignalkAutopilotConfigurator(
  ///   key: key,
  ///   signalKService: signalKService,
  ///   pluginId: pluginId,
  ///   initialConfig: initialConfig,
  ///   onSaved: onSaved,
  /// ),
  /// ```
  static final Map<String, PluginConfiguratorFactory> _configurators = {
    // Generated configurators will be registered here
    // 'signalk-autopilot': SignalkAutopilotConfigurator.new,
  };

  /// Returns true if a native configurator exists for this plugin.
  static bool hasConfigurator(String pluginId) =>
      _configurators.containsKey(pluginId);

  /// Gets the native configurator for a plugin, if available.
  ///
  /// Returns null if no native configurator is registered - the caller
  /// should fall back to WebView in this case.
  static BasePluginConfigurator? getConfigurator({
    required String pluginId,
    required SignalKService signalKService,
    required Map<String, dynamic> initialConfig,
    VoidCallback? onSaved,
  }) {
    final factory = _configurators[pluginId];
    if (factory == null) return null;

    return factory(
      signalKService: signalKService,
      pluginId: pluginId,
      initialConfig: initialConfig,
      onSaved: onSaved,
    );
  }

  /// Returns a list of all plugin IDs that have native configurators.
  static List<String> get registeredPlugins => _configurators.keys.toList();

  /// Returns the number of registered native configurators.
  static int get count => _configurators.length;
}
