import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/template.dart';
import '../models/tool_instance.dart';
import '../models/tool_config.dart';
import 'storage_service.dart';

/// Service for managing tool templates
class TemplateService extends ChangeNotifier {
  final StorageService _storageService;

  final List<Template> _templates = [];
  bool _initialized = false;

  TemplateService(this._storageService);

  List<Template> get templates => List.unmodifiable(_templates);
  bool get initialized => _initialized;

  /// Initialize and load templates from storage
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load templates from storage
      final templateData = await _storageService.loadAllTemplates();

      _templates.clear();
      for (final data in templateData) {
        try {
          final template = Template.fromJson(data);
          _templates.add(template);
        } catch (e) {
          if (kDebugMode) {
            print('Error loading template: $e');
          }
        }
      }

      _initialized = true;
      notifyListeners();

      if (kDebugMode) {
        print('TemplateService initialized with ${_templates.length} templates');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing TemplateService: $e');
      }
      rethrow;
    }
  }

  /// Create a template from an existing tool instance
  Template createTemplateFromTool({
    required ToolInstance toolInstance,
    required String name,
    required String description,
    required String author,
    TemplateCategory category = TemplateCategory.other,
    List<String> tags = const [],
  }) {
    // Extract required paths from the tool's data sources
    final requiredPaths = toolInstance.config.dataSources
        .map((ds) => ds.path)
        .toList();

    return Template(
      id: 'template_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      author: author,
      createdAt: DateTime.now(),
      toolTypeId: toolInstance.toolTypeId,
      config: toolInstance.config,
      category: category,
      tags: tags,
      requiredPaths: requiredPaths,
      isLocal: true,
    );
  }

  /// Apply a template to create a tool instance
  ToolInstance applyTemplate({
    required Template template,
    required String screenId,
    int row = 0,
    int col = 0,
  }) {
    return ToolInstance(
      id: 'tool_${DateTime.now().millisecondsSinceEpoch}',
      toolTypeId: template.toolTypeId,
      config: template.config,
      screenId: screenId,
      position: GridPosition(row: row, col: col),
    );
  }

  /// Save a template to local storage
  Future<void> saveTemplate(Template template) async {
    try {
      await _storageService.saveTemplate(template.id, template.toJson());

      // Update local list
      final existingIndex = _templates.indexWhere((t) => t.id == template.id);
      if (existingIndex >= 0) {
        _templates[existingIndex] = template;
      } else {
        _templates.add(template);
      }

      notifyListeners();

      if (kDebugMode) {
        print('Template saved: ${template.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving template: $e');
      }
      rethrow;
    }
  }

  /// Delete a template
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _storageService.deleteTemplate(templateId);

      _templates.removeWhere((t) => t.id == templateId);
      notifyListeners();

      if (kDebugMode) {
        print('Template deleted: $templateId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting template: $e');
      }
      rethrow;
    }
  }

  /// Export template to JSON string
  String exportTemplate(Template template) {
    final json = template.toJson();
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Import template from JSON string
  Template importTemplate(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return Template.fromJson(json);
    } catch (e) {
      throw Exception('Invalid template JSON: $e');
    }
  }

  /// Get templates by category
  List<Template> getTemplatesByCategory(TemplateCategory category) {
    return _templates.where((t) => t.category == category).toList();
  }

  /// Search templates by name or tags
  List<Template> searchTemplates(String query) {
    if (query.isEmpty) return _templates;

    final lowerQuery = query.toLowerCase();
    return _templates.where((t) {
      return t.name.toLowerCase().contains(lowerQuery) ||
             t.description.toLowerCase().contains(lowerQuery) ||
             t.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)) ||
             t.author.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get compatible templates for available paths
  List<Template> getCompatibleTemplates(List<String> availablePaths) {
    return _templates
        .where((t) => t.isCompatible(availablePaths))
        .toList();
  }

  /// Get templates by tool type
  List<Template> getTemplatesByToolType(String toolTypeId) {
    return _templates.where((t) => t.toolTypeId == toolTypeId).toList();
  }

  /// Import template and save it
  Future<Template> importAndSave(String jsonString) async {
    final template = importTemplate(jsonString);

    // Update metadata for imported template
    final updatedTemplate = template.copyWith(
      isLocal: false,
      updatedAt: DateTime.now(),
    );

    await saveTemplate(updatedTemplate);
    return updatedTemplate;
  }

  /// Get popular templates (sorted by download count)
  List<Template> getPopularTemplates({int limit = 10}) {
    final sorted = List<Template>.from(_templates)
      ..sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
    return sorted.take(limit).toList();
  }

  /// Get top rated templates
  List<Template> getTopRatedTemplates({int limit = 10}) {
    final sorted = List<Template>.from(_templates)
      ..sort((a, b) {
        // Sort by rating, then by number of ratings
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.ratingCount.compareTo(a.ratingCount);
      });
    return sorted.take(limit).toList();
  }

  /// Get recently added templates
  List<Template> getRecentTemplates({int limit = 10}) {
    final sorted = List<Template>.from(_templates)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList();
  }

  /// Validate template compatibility and return issues
  List<String> validateTemplate(Template template, List<String> availablePaths) {
    final issues = <String>[];

    // Check required paths
    final missingPaths = template.getMissingPaths(availablePaths);
    if (missingPaths.isNotEmpty) {
      issues.add('Missing required paths: ${missingPaths.join(", ")}');
    }

    // Check if tool type exists (would need ToolRegistry)
    // This can be added later when integrating with ToolRegistry

    return issues;
  }

  /// Get template statistics
  Map<String, dynamic> getStatistics() {
    return {
      'total': _templates.length,
      'local': _templates.where((t) => t.isLocal).length,
      'downloaded': _templates.where((t) => !t.isLocal).length,
      'categories': {
        for (final category in TemplateCategory.values)
          category.name: _templates.where((t) => t.category == category).length,
      },
    };
  }
}
