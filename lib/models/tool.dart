import 'package:json_annotation/json_annotation.dart';
import 'tool_config.dart';

part 'tool.g.dart';

/// Tool category for organization
enum ToolCategory {
  navigation,
  environment,
  electrical,
  engine,
  sailing,
  safety,
  complete,  // Complete dashboard layouts
  other,
}

/// A reusable tool with configuration and metadata
/// This is the unified model - every tool can be placed on dashboards
/// and every tool can be saved/shared
@JsonSerializable()
class Tool {
  final String id;              // Unique tool ID (UUID)
  final String name;            // Display name
  final String description;     // Detailed description
  final String author;          // Tool creator
  final String version;         // Tool version (semver)
  final DateTime createdAt;     // Creation timestamp
  final DateTime? updatedAt;    // Last update timestamp

  // Tool configuration
  final String toolTypeId;      // Which tool type this is (e.g., "radial_gauge")
  final ToolConfig config;      // Configuration (data sources, style, etc.)

  // Default sizing
  final int defaultWidth;       // Default width when placed (grid units)
  final int defaultHeight;      // Default height when placed (grid units)

  // Organization & discovery
  final ToolCategory category;
  final List<String> tags;      // Searchable tags (e.g., ["speed", "wind", "navigation"])

  // Visual metadata
  final String? thumbnailUrl;   // Preview image URL
  final String? iconUrl;        // Icon URL

  // Compatibility & requirements
  final List<String> requiredPaths;  // SignalK paths this tool needs
  final String? minAppVersion;       // Minimum app version required

  // Usage tracking
  final int usageCount;         // Number of times placed on dashboards
  final double rating;          // User rating (0-5)
  final int ratingCount;        // Number of ratings

  // Source tracking
  final String? sourceUrl;      // URL where tool can be updated
  final bool isLocal;           // True if created locally, false if downloaded

  Tool({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    this.version = '1.0.0',
    required this.createdAt,
    this.updatedAt,
    required this.toolTypeId,
    required this.config,
    this.defaultWidth = 2,
    this.defaultHeight = 2,
    this.category = ToolCategory.other,
    this.tags = const [],
    this.thumbnailUrl,
    this.iconUrl,
    this.requiredPaths = const [],
    this.minAppVersion,
    this.usageCount = 0,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.sourceUrl,
    this.isLocal = true,
  });

  factory Tool.fromJson(Map<String, dynamic> json) =>
      _$ToolFromJson(json);

  Map<String, dynamic> toJson() => _$ToolToJson(this);

  /// Create a copy with modified fields
  Tool copyWith({
    String? id,
    String? name,
    String? description,
    String? author,
    String? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? toolTypeId,
    ToolConfig? config,
    int? defaultWidth,
    int? defaultHeight,
    ToolCategory? category,
    List<String>? tags,
    String? thumbnailUrl,
    String? iconUrl,
    List<String>? requiredPaths,
    String? minAppVersion,
    int? usageCount,
    double? rating,
    int? ratingCount,
    String? sourceUrl,
    bool? isLocal,
  }) {
    return Tool(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      toolTypeId: toolTypeId ?? this.toolTypeId,
      config: config ?? this.config,
      defaultWidth: defaultWidth ?? this.defaultWidth,
      defaultHeight: defaultHeight ?? this.defaultHeight,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      requiredPaths: requiredPaths ?? this.requiredPaths,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      usageCount: usageCount ?? this.usageCount,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isLocal: isLocal ?? this.isLocal,
    );
  }

  /// Check if this tool is compatible with available paths
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

  /// Increment usage count when tool is placed on dashboard
  Tool incrementUsage() {
    return copyWith(usageCount: usageCount + 1);
  }
}
