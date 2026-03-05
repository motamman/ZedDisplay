import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/tool_info.dart';
import 'signalk_service.dart';

/// Service for loading and managing tool information
/// Singleton that loads tool_info.yaml and checks plugin status
class ToolInfoService extends ChangeNotifier {
  static final ToolInfoService _instance = ToolInfoService._internal();
  static ToolInfoService get instance => _instance;

  ToolInfoService._internal();

  final Map<String, ToolInfoData> _toolInfo = {};
  final Map<String, DataSourceInfo> _dataSources = {};
  final Map<String, PluginInfo> _plugins = {};
  bool _loaded = false;
  String? _loadError;

  /// Whether the service has loaded its data
  bool get isLoaded => _loaded;

  /// Error message if loading failed
  String? get loadError => _loadError;

  /// Load tool_info.yaml from assets
  Future<void> load() async {
    if (_loaded) return;

    try {
      final yamlString = await rootBundle.loadString('assets/tool_info.yaml');
      final yaml = loadYaml(yamlString) as YamlMap;

      // Parse data sources
      final dataSourcesYaml = yaml['data_sources'] as YamlMap?;
      if (dataSourcesYaml != null) {
        for (final entry in dataSourcesYaml.entries) {
          final id = entry.key as String;
          final data = _yamlMapToMap(entry.value as YamlMap);
          _dataSources[id] = DataSourceInfo.fromYaml(id, data);
        }
      }

      // Parse plugins
      final pluginsYaml = yaml['plugins'] as YamlMap?;
      if (pluginsYaml != null) {
        for (final entry in pluginsYaml.entries) {
          final id = entry.key as String;
          final data = _yamlMapToMap(entry.value as YamlMap);
          _plugins[id] = PluginInfo.fromYaml(id, data);
        }
      }

      // Parse tools
      final toolsYaml = yaml['tools'] as YamlMap?;
      if (toolsYaml != null) {
        for (final entry in toolsYaml.entries) {
          final id = entry.key as String;
          final data = _yamlMapToMap(entry.value as YamlMap);
          _toolInfo[id] = ToolInfoData.fromYaml(
            id,
            data,
            dataSourcesMap: _dataSources,
            pluginsMap: _plugins,
          );
        }
      }

      _loaded = true;
      _loadError = null;
      notifyListeners();

      if (kDebugMode) {
        print('ToolInfoService: Loaded ${_toolInfo.length} tools, '
            '${_plugins.length} plugins, ${_dataSources.length} data sources');
      }
    } catch (e) {
      _loadError = e.toString();
      if (kDebugMode) {
        print('ToolInfoService: Error loading tool_info.yaml: $e');
      }
    }
  }

  /// Convert YamlMap to regular Map
  Map<String, dynamic> _yamlMapToMap(YamlMap yamlMap) {
    final result = <String, dynamic>{};
    for (final entry in yamlMap.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is YamlMap) {
        result[key] = _yamlMapToMap(value);
      } else if (value is YamlList) {
        result[key] = _yamlListToList(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Convert YamlList to regular List
  List<dynamic> _yamlListToList(YamlList yamlList) {
    return yamlList.map((item) {
      if (item is YamlMap) {
        return _yamlMapToMap(item);
      } else if (item is YamlList) {
        return _yamlListToList(item);
      }
      return item;
    }).toList();
  }

  /// Get info for a specific tool
  ToolInfoData? getToolInfo(String toolId) {
    return _toolInfo[toolId];
  }

  /// Get plugin info by ID
  PluginInfo? getPluginInfo(String pluginId) {
    return _plugins[pluginId];
  }

  /// Get data source info by ID
  DataSourceInfo? getDataSourceInfo(String dataSourceId) {
    return _dataSources[dataSourceId];
  }

  /// Check plugin status against server plugins list
  /// Returns a map of plugin ID to status
  Future<Map<String, PluginStatus>> checkPluginStatus(
    List<PluginRequirement> requirements,
    SignalKService signalKService,
  ) async {
    final status = <String, PluginStatus>{};

    if (!signalKService.isConnected) {
      // If not connected, mark all as unknown (notInstalled)
      for (final req in requirements) {
        status[req.pluginId] = PluginStatus.notInstalled;
      }
      return status;
    }

    try {
      // Fetch plugins from SignalK server
      final protocol = signalKService.useSecureConnection ? 'https' : 'http';
      final url = '$protocol://${signalKService.serverUrl}/signalk/v2/features';

      final headers = <String, String>{};
      if (signalKService.authToken != null) {
        headers['Authorization'] = 'Bearer ${signalKService.authToken!.token}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final plugins = data['plugins'] as List<dynamic>? ?? [];

        for (final req in requirements) {
          final plugin = plugins.firstWhere(
            (p) => (p as Map<String, dynamic>)['id'] == req.pluginId,
            orElse: () => null,
          );

          if (plugin == null) {
            status[req.pluginId] = PluginStatus.notInstalled;
          } else {
            final pluginMap = plugin as Map<String, dynamic>;
            if (pluginMap['enabled'] == true) {
              status[req.pluginId] = PluginStatus.installed;
            } else {
              status[req.pluginId] = PluginStatus.disabled;
            }
          }
        }
      } else {
        // API error - mark all as unknown
        for (final req in requirements) {
          status[req.pluginId] = PluginStatus.notInstalled;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ToolInfoService: Error checking plugin status: $e');
      }
      // On error, mark all as unknown
      for (final req in requirements) {
        status[req.pluginId] = PluginStatus.notInstalled;
      }
    }

    return status;
  }
}
