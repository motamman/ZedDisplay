// Data models for tool information display.
// Used by ToolInfoButton to show tool descriptions, required plugins, and data sources.

/// Plugin installation status
enum PluginStatus {
  installed,    // Installed and enabled
  disabled,     // Installed but not enabled
  notInstalled, // Not installed on the server
}

/// Information about a tool for the info dialog
class ToolInfoData {
  final String id;
  final String name;
  final String description; // Markdown-formatted
  final List<PluginRequirement> requiredPlugins;
  final List<DataSourceInfo> dataSources;
  final List<FeatureInfo> features;

  const ToolInfoData({
    required this.id,
    required this.name,
    required this.description,
    this.requiredPlugins = const [],
    this.dataSources = const [],
    this.features = const [],
  });

  /// Create from YAML map
  factory ToolInfoData.fromYaml(String id, Map<String, dynamic> yaml, {
    Map<String, DataSourceInfo>? dataSourcesMap,
    Map<String, PluginInfo>? pluginsMap,
  }) {
    // Parse required plugins
    final requiredPluginIds = (yaml['required_plugins'] as List<dynamic>?)
        ?.cast<String>() ?? [];
    final requiredPlugins = requiredPluginIds.map((pluginId) {
      final pluginInfo = pluginsMap?[pluginId];
      return PluginRequirement(
        pluginId: pluginId,
        displayName: pluginInfo?.name ?? pluginId,
        description: pluginInfo?.description,
        required: true,
      );
    }).toList();

    // Parse optional plugins
    final optionalPluginIds = (yaml['optional_plugins'] as List<dynamic>?)
        ?.cast<String>() ?? [];
    requiredPlugins.addAll(optionalPluginIds.map((pluginId) {
      final pluginInfo = pluginsMap?[pluginId];
      return PluginRequirement(
        pluginId: pluginId,
        displayName: pluginInfo?.name ?? pluginId,
        description: pluginInfo?.description,
        required: false,
      );
    }));

    // Parse data sources
    final dataSourceIds = (yaml['data_sources'] as List<dynamic>?)
        ?.cast<String>() ?? [];
    final dataSources = dataSourceIds
        .map((id) => dataSourcesMap?[id])
        .whereType<DataSourceInfo>()
        .toList();

    // Parse features
    final featuresList = (yaml['features'] as List<dynamic>?) ?? [];
    final features = featuresList.map((f) {
      final map = f as Map<String, dynamic>;
      return FeatureInfo(
        icon: map['icon'] as String? ?? 'info',
        label: map['label'] as String? ?? '',
        description: map['description'] as String? ?? '',
      );
    }).toList();

    return ToolInfoData(
      id: id,
      name: yaml['name'] as String? ?? id,
      description: yaml['description'] as String? ?? '',
      requiredPlugins: requiredPlugins,
      dataSources: dataSources,
      features: features,
    );
  }
}

/// Plugin requirement with status
class PluginRequirement {
  final String pluginId;
  final String displayName;
  final bool required; // true = required, false = optional
  final String? description;

  const PluginRequirement({
    required this.pluginId,
    required this.displayName,
    this.required = true,
    this.description,
  });
}

/// Plugin info from the plugins section of YAML
class PluginInfo {
  final String id;
  final String name;
  final String? description;

  const PluginInfo({
    required this.id,
    required this.name,
    this.description,
  });

  factory PluginInfo.fromYaml(String id, Map<String, dynamic> yaml) {
    return PluginInfo(
      id: id,
      name: yaml['name'] as String? ?? id,
      description: yaml['description'] as String?,
    );
  }
}

/// Data source attribution
class DataSourceInfo {
  final String id;
  final String name;
  final String? url;

  const DataSourceInfo({
    required this.id,
    required this.name,
    this.url,
  });

  factory DataSourceInfo.fromYaml(String id, Map<String, dynamic> yaml) {
    return DataSourceInfo(
      id: id,
      name: yaml['name'] as String? ?? id,
      url: yaml['url'] as String?,
    );
  }
}

/// Feature/metric that can be displayed in the info dialog
class FeatureInfo {
  final String icon; // Material icon name
  final String label;
  final String description;

  const FeatureInfo({
    required this.icon,
    required this.label,
    required this.description,
  });
}
