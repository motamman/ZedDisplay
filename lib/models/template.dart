import 'package:json_annotation/json_annotation.dart';
import 'tool_config.dart';

part 'template.g.dart';

/// Template category for organization
enum TemplateCategory {
  navigation,
  environment,
  electrical,
  engine,
  sailing,
  safety,
  complete,  // Complete dashboard layouts
  other,
}

/// A template for creating pre-configured tools
@JsonSerializable()
class Template {
  final String id;              // Unique template ID (UUID or slug)
  final String name;            // Display name
  final String description;     // Detailed description
  final String author;          // Template creator
  final String version;         // Template version (semver)
  final DateTime createdAt;     // Creation timestamp
  final DateTime? updatedAt;    // Last update timestamp

  // Tool configuration
  final String toolTypeId;      // Which tool this configures (e.g., "radial_gauge")
  final ToolConfig config;      // Pre-configured settings

  // Organization & discovery
  final TemplateCategory category;
  final List<String> tags;      // Searchable tags (e.g., ["speed", "wind", "navigation"])

  // Visual metadata
  final String? thumbnailUrl;   // Preview image URL
  final String? iconUrl;        // Icon URL

  // Compatibility & requirements
  final List<String> requiredPaths;  // SignalK paths this template needs
  final String? minAppVersion;       // Minimum app version required

  // Usage tracking
  final int downloadCount;      // Number of times downloaded
  final double rating;          // User rating (0-5)
  final int ratingCount;        // Number of ratings

  // Source tracking
  final String? sourceUrl;      // URL where template can be updated
  final bool isLocal;           // True if created locally, false if downloaded

  Template({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    this.version = '1.0.0',
    required this.createdAt,
    this.updatedAt,
    required this.toolTypeId,
    required this.config,
    this.category = TemplateCategory.other,
    this.tags = const [],
    this.thumbnailUrl,
    this.iconUrl,
    this.requiredPaths = const [],
    this.minAppVersion,
    this.downloadCount = 0,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.sourceUrl,
    this.isLocal = true,
  });

  factory Template.fromJson(Map<String, dynamic> json) =>
      _$TemplateFromJson(json);

  Map<String, dynamic> toJson() => _$TemplateToJson(this);

  /// Create a copy with modified fields
  Template copyWith({
    String? id,
    String? name,
    String? description,
    String? author,
    String? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? toolTypeId,
    ToolConfig? config,
    TemplateCategory? category,
    List<String>? tags,
    String? thumbnailUrl,
    String? iconUrl,
    List<String>? requiredPaths,
    String? minAppVersion,
    int? downloadCount,
    double? rating,
    int? ratingCount,
    String? sourceUrl,
    bool? isLocal,
  }) {
    return Template(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      toolTypeId: toolTypeId ?? this.toolTypeId,
      config: config ?? this.config,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      requiredPaths: requiredPaths ?? this.requiredPaths,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      downloadCount: downloadCount ?? this.downloadCount,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isLocal: isLocal ?? this.isLocal,
    );
  }

  /// Check if this template is compatible with available paths
  bool isCompatible(List<String> availablePaths) {
    if (requiredPaths.isEmpty) return true;

    // Check if all required paths are available
    for (final requiredPath in requiredPaths) {
      if (!availablePaths.contains(requiredPath)) {
        return false;
      }
    }
    return true;
  }

  /// Get missing paths that are required but not available
  List<String> getMissingPaths(List<String> availablePaths) {
    return requiredPaths
        .where((path) => !availablePaths.contains(path))
        .toList();
  }
}

/// Collection of templates (for multi-tool templates or complete dashboards)
@JsonSerializable()
class TemplateCollection {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final DateTime createdAt;
  final TemplateCategory category;
  final List<String> tags;

  final List<Template> templates;  // Multiple tool templates

  final String? thumbnailUrl;
  final bool isLocal;

  TemplateCollection({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    this.version = '1.0.0',
    required this.createdAt,
    this.category = TemplateCategory.complete,
    this.tags = const [],
    required this.templates,
    this.thumbnailUrl,
    this.isLocal = true,
  });

  factory TemplateCollection.fromJson(Map<String, dynamic> json) =>
      _$TemplateCollectionFromJson(json);

  Map<String, dynamic> toJson() => _$TemplateCollectionToJson(this);

  /// Get all required paths from all templates
  List<String> getAllRequiredPaths() {
    final paths = <String>{};
    for (final template in templates) {
      paths.addAll(template.requiredPaths);
    }
    return paths.toList();
  }

  /// Check if all templates are compatible
  bool isCompatible(List<String> availablePaths) {
    return templates.every((t) => t.isCompatible(availablePaths));
  }
}
