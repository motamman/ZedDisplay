import 'package:json_annotation/json_annotation.dart';
import 'dashboard_layout.dart';
import 'tool.dart';

part 'dashboard_setup.g.dart';

/// A complete shareable dashboard setup
/// Contains the layout with all screens/placements AND all referenced tools
@JsonSerializable()
class DashboardSetup {
  final String version;         // Export format version
  final SetupMetadata metadata; // Metadata about this setup
  final DashboardLayout layout; // The dashboard layout
  final List<Tool> tools;       // All tools referenced in the layout

  DashboardSetup({
    this.version = '1.0.0',
    required this.metadata,
    required this.layout,
    required this.tools,
  });

  factory DashboardSetup.fromJson(Map<String, dynamic> json) =>
      _$DashboardSetupFromJson(json);

  Map<String, dynamic> toJson() => _$DashboardSetupToJson(this);

  /// Create a copy with modified fields
  DashboardSetup copyWith({
    String? version,
    SetupMetadata? metadata,
    DashboardLayout? layout,
    List<Tool>? tools,
  }) {
    return DashboardSetup(
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
      layout: layout ?? this.layout,
      tools: tools ?? this.tools,
    );
  }

  /// Validate that all tools referenced in placements exist in tools list
  bool isValid() {
    final toolIds = tools.map((t) => t.id).toSet();
    final referencedIds = layout.getAllToolIds().toSet();

    // Check if all referenced tool IDs exist in the tools list
    return referencedIds.every((id) => toolIds.contains(id));
  }

  /// Get missing tool IDs (referenced but not included)
  List<String> getMissingToolIds() {
    final toolIds = tools.map((t) => t.id).toSet();
    final referencedIds = layout.getAllToolIds().toSet();

    return referencedIds.where((id) => !toolIds.contains(id)).toList();
  }
}

/// Metadata about a dashboard setup
@JsonSerializable()
class SetupMetadata {
  final String name;            // Display name
  final String description;     // Description
  final String author;          // Creator
  final DateTime createdAt;     // Creation time
  final DateTime? updatedAt;    // Last update time
  final String? thumbnailUrl;   // Optional preview image
  final List<String> tags;      // Searchable tags

  SetupMetadata({
    required this.name,
    this.description = '',
    required this.author,
    required this.createdAt,
    this.updatedAt,
    this.thumbnailUrl,
    this.tags = const [],
  });

  factory SetupMetadata.fromJson(Map<String, dynamic> json) =>
      _$SetupMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$SetupMetadataToJson(this);

  /// Create a copy with modified fields
  SetupMetadata copyWith({
    String? name,
    String? description,
    String? author,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? thumbnailUrl,
    List<String>? tags,
  }) {
    return SetupMetadata(
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      tags: tags ?? this.tags,
    );
  }
}

/// A saved setup reference for local storage
@JsonSerializable()
class SavedSetup {
  final String id;              // Unique setup ID
  final String name;            // Display name
  final String description;     // Description
  final DateTime createdAt;     // Creation time
  final DateTime? lastUsedAt;   // Last time this setup was active
  final bool isActive;          // Is this the currently active setup?
  final int screenCount;        // Number of screens in this setup
  final int toolCount;          // Number of unique tools in this setup

  SavedSetup({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    this.lastUsedAt,
    this.isActive = false,
    this.screenCount = 0,
    this.toolCount = 0,
  });

  factory SavedSetup.fromJson(Map<String, dynamic> json) =>
      _$SavedSetupFromJson(json);

  Map<String, dynamic> toJson() => _$SavedSetupToJson(this);

  /// Create from a DashboardSetup
  factory SavedSetup.fromDashboardSetup(DashboardSetup setup, {bool isActive = false}) {
    return SavedSetup(
      id: setup.layout.id,
      name: setup.metadata.name,
      description: setup.metadata.description,
      createdAt: setup.metadata.createdAt,
      lastUsedAt: isActive ? DateTime.now() : null,
      isActive: isActive,
      screenCount: setup.layout.screens.length,
      toolCount: setup.tools.length,
    );
  }

  /// Create a copy with modified fields
  SavedSetup copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    bool? isActive,
    int? screenCount,
    int? toolCount,
  }) {
    return SavedSetup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isActive: isActive ?? this.isActive,
      screenCount: screenCount ?? this.screenCount,
      toolCount: toolCount ?? this.toolCount,
    );
  }
}
