/// Scale Service
///
/// Loads and provides menu item definitions from scales.yaml.
/// Simplified version focused on menu items for SignalK app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Menu item definition from scales.yaml
class MenuItemDefinition {
  final String id;
  final String icon;
  final String label;
  final String description;

  const MenuItemDefinition({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
  });

  /// Get the Flutter IconData for this menu item
  IconData get iconData {
    const iconMap = {
      'add': Icons.add,
      'edit': Icons.edit,
      'refresh': Icons.refresh,
      'fullscreen': Icons.fullscreen,
      'settings': Icons.settings,
      'delete': Icons.delete,
      'done': Icons.done,
      'close': Icons.close,
      'menu': Icons.menu,
      'group': Icons.group,
      'light_mode': Icons.light_mode,
      'dark_mode': Icons.dark_mode,
      'brightness_auto': Icons.brightness_auto,
      'new_releases': Icons.new_releases,
    };
    return iconMap[icon] ?? Icons.help_outline;
  }
}

/// Service for loading scale definitions and menu items
class ScaleService {
  static ScaleService? _instance;
  static ScaleService get instance => _instance ??= ScaleService._();

  ScaleService._();

  final Map<String, MenuItemDefinition> _menuItems = {};
  bool _initialized = false;

  bool get initialized => _initialized;

  /// Initialize from scales.yaml
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final yamlString = await rootBundle.loadString('assets/defaults/scales.yaml');
      final yaml = loadYaml(yamlString) as YamlMap;

      // Parse menu items
      if (yaml['menuItems'] != null) {
        final menuItems = yaml['menuItems'] as YamlMap;
        for (final entry in menuItems.entries) {
          final id = entry.key as String;
          final def = entry.value as YamlMap;
          _menuItems[id] = MenuItemDefinition(
            id: id,
            icon: def['icon'] as String? ?? 'help_outline',
            label: def['label'] as String? ?? id,
            description: def['description'] as String? ?? '',
          );
        }
      }

      _initialized = true;
      debugPrint('ScaleService: Loaded ${_menuItems.length} menu items');
    } catch (e) {
      debugPrint('Error loading scales.yaml: $e');
      // Load defaults if file not found
      _loadDefaults();
      _initialized = true;
    }
  }

  void _loadDefaults() {
    _menuItems['addTool'] = const MenuItemDefinition(
      id: 'addTool',
      icon: 'add',
      label: 'Add Widget',
      description: 'Add a new widget',
    );
    _menuItems['editMode'] = const MenuItemDefinition(
      id: 'editMode',
      icon: 'edit',
      label: 'Edit Mode',
      description: 'Resize and move widgets',
    );
    _menuItems['theme'] = const MenuItemDefinition(
      id: 'theme',
      icon: 'brightness_auto',
      label: 'Theme',
      description: 'Toggle dark/light mode',
    );
    _menuItems['fullscreen'] = const MenuItemDefinition(
      id: 'fullscreen',
      icon: 'fullscreen',
      label: 'Full Screen',
      description: 'Toggle full screen',
    );
    _menuItems['crew'] = const MenuItemDefinition(
      id: 'crew',
      icon: 'group',
      label: 'Crew',
      description: 'Crew communications',
    );
    _menuItems['settings'] = const MenuItemDefinition(
      id: 'settings',
      icon: 'settings',
      label: 'Settings',
      description: 'App settings',
    );
  }

  /// Get menu item definition by id
  MenuItemDefinition? getMenuItem(String id) => _menuItems[id];

  /// Get all menu items
  Map<String, MenuItemDefinition> get menuItems => Map.unmodifiable(_menuItems);
}
