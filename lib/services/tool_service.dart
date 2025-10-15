import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/tool.dart';
import '../models/tool_placement.dart';
import '../models/tool_config.dart';
import 'storage_service.dart';

/// Service for managing tools
/// Tools are the unified model - every tool can be placed on dashboards
/// and every tool can be saved/shared
class ToolService extends ChangeNotifier {
  final StorageService _storageService;

  final List<Tool> _tools = [];
  bool _initialized = false;

  ToolService(this._storageService);

  List<Tool> get tools => List.unmodifiable(_tools);
  bool get initialized => _initialized;

  /// Initialize and load tools from storage
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load tools from storage (migrate from old templates)
      final toolData = await _storageService.loadAllTemplates();

      _tools.clear();
      for (final data in toolData) {
        try {
          final tool = Tool.fromJson(data);
          _tools.add(tool);
        } catch (e) {
          if (kDebugMode) {
            print('Error loading tool: $e');
          }
        }
      }

      _initialized = true;
      notifyListeners();

      if (kDebugMode) {
        print('ToolService initialized with ${_tools.length} tools');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing ToolService: $e');
      }
      rethrow;
    }
  }

  /// Create a new tool with metadata
  Tool createTool({
    required String toolTypeId,
    required ToolConfig config,
    required String name,
    required String description,
    required String author,
    ToolCategory category = ToolCategory.other,
    List<String> tags = const [],
  }) {
    // Extract required paths from the tool's data sources
    final requiredPaths = config.dataSources
        .map((ds) => ds.path)
        .toList();

    return Tool(
      id: 'tool_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      author: author,
      createdAt: DateTime.now(),
      toolTypeId: toolTypeId,
      config: config,
      category: category,
      tags: tags,
      requiredPaths: requiredPaths,
      isLocal: true,
    );
  }

  /// Create a placement for a tool
  ToolPlacement createPlacement({
    required String toolId,
    required String screenId,
    int row = 0,
    int col = 0,
  }) {
    return ToolPlacement(
      toolId: toolId,
      screenId: screenId,
      position: GridPosition(row: row, col: col),
    );
  }

  /// Get a tool by ID
  Tool? getTool(String toolId) {
    try {
      return _tools.firstWhere((t) => t.id == toolId);
    } catch (e) {
      return null;
    }
  }

  /// Save a tool to local storage
  Future<void> saveTool(Tool tool) async {
    try {
      await _storageService.saveTemplate(tool.id, tool.toJson());

      // Update local list
      final existingIndex = _tools.indexWhere((t) => t.id == tool.id);
      if (existingIndex >= 0) {
        _tools[existingIndex] = tool;
      } else {
        _tools.add(tool);
      }

      notifyListeners();

      if (kDebugMode) {
        print('Tool saved: ${tool.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving tool: $e');
      }
      rethrow;
    }
  }

  /// Delete a tool
  Future<void> deleteTool(String toolId) async {
    try {
      await _storageService.deleteTemplate(toolId);

      _tools.removeWhere((t) => t.id == toolId);
      notifyListeners();

      if (kDebugMode) {
        print('Tool deleted: $toolId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting tool: $e');
      }
      rethrow;
    }
  }

  /// Export tool to JSON string
  String exportTool(Tool tool) {
    final json = tool.toJson();
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Import tool from JSON string
  Tool importTool(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return Tool.fromJson(json);
    } catch (e) {
      throw Exception('Invalid tool JSON: $e');
    }
  }

  /// Get tools by category
  List<Tool> getToolsByCategory(ToolCategory category) {
    return _tools.where((t) => t.category == category).toList();
  }

  /// Search tools by name or tags
  List<Tool> searchTools(String query) {
    if (query.isEmpty) return _tools;

    final lowerQuery = query.toLowerCase();
    return _tools.where((t) {
      return t.name.toLowerCase().contains(lowerQuery) ||
             t.description.toLowerCase().contains(lowerQuery) ||
             t.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)) ||
             t.author.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get compatible tools for available paths
  List<Tool> getCompatibleTools(List<String> availablePaths) {
    return _tools
        .where((t) => t.isCompatible(availablePaths))
        .toList();
  }

  /// Get tools by tool type
  List<Tool> getToolsByToolType(String toolTypeId) {
    return _tools.where((t) => t.toolTypeId == toolTypeId).toList();
  }

  /// Import tool and save it
  Future<Tool> importAndSave(String jsonString) async {
    final tool = importTool(jsonString);

    // Update metadata for imported tool
    final updatedTool = tool.copyWith(
      isLocal: false,
      updatedAt: DateTime.now(),
    );

    await saveTool(updatedTool);
    return updatedTool;
  }

  /// Get popular tools (sorted by usage count)
  List<Tool> getPopularTools({int limit = 10}) {
    final sorted = List<Tool>.from(_tools)
      ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return sorted.take(limit).toList();
  }

  /// Get top rated tools
  List<Tool> getTopRatedTools({int limit = 10}) {
    final sorted = List<Tool>.from(_tools)
      ..sort((a, b) {
        // Sort by rating, then by number of ratings
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.ratingCount.compareTo(a.ratingCount);
      });
    return sorted.take(limit).toList();
  }

  /// Get recently added tools
  List<Tool> getRecentTools({int limit = 10}) {
    final sorted = List<Tool>.from(_tools)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  /// Validate tool compatibility and return issues
  List<String> validateTool(Tool tool, List<String> availablePaths) {
    final issues = <String>[];

    // Check required paths
    final missingPaths = tool.getMissingPaths(availablePaths);
    if (missingPaths.isNotEmpty) {
      issues.add('Missing required paths: ${missingPaths.join(", ")}');
    }

    return issues;
  }

  /// Get tool statistics
  Map<String, dynamic> getStatistics() {
    return {
      'total': _tools.length,
      'local': _tools.where((t) => t.isLocal).length,
      'downloaded': _tools.where((t) => !t.isLocal).length,
      'categories': {
        for (final category in ToolCategory.values)
          category.name: _tools.where((t) => t.category == category).length,
      },
    };
  }

  /// Increment usage count when tool is placed on dashboard
  Future<void> incrementUsage(String toolId) async {
    final tool = getTool(toolId);
    if (tool != null) {
      final updatedTool = tool.incrementUsage();
      await saveTool(updatedTool);
    }
  }

  /// Get all required paths from a list of tool IDs
  List<String> getRequiredPathsForTools(List<String> toolIds) {
    final paths = <String>{};

    for (final toolId in toolIds) {
      final tool = getTool(toolId);
      if (tool != null) {
        for (final dataSource in tool.config.dataSources) {
          paths.add(dataSource.path);
        }
      }
    }

    return paths.toList();
  }
}
