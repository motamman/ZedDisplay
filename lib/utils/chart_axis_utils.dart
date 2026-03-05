import '../models/tool_config.dart';
import '../services/metadata_store.dart';

/// Utilities for managing dual Y-axis assignment in charts.
/// Supports up to 2 different base units (primary and secondary axes).
class ChartAxisUtils {
  /// Determine primary and secondary axis units from data sources.
  /// Returns the first two unique unit identifiers found.
  /// Uses baseUnit, falls back to category, then to symbol for grouping.
  static ({String? primary, String? secondary}) determineAxisUnits(
    List<DataSource> dataSources,
    MetadataStore metadataStore,
  ) {
    String? primary;
    String? secondary;

    for (final ds in dataSources) {
      final metadata = metadataStore.get(ds.path);
      // Use stored baseUnit from DataSource, fallback to MetadataStore baseUnit,
      // then category, then symbol (for grouping purposes)
      final unitKey = ds.baseUnit ??
          metadata?.baseUnit ??
          metadata?.category ??
          metadata?.symbol;
      if (unitKey == null) continue;

      if (primary == null) {
        primary = unitKey;
      } else if (unitKey != primary && secondary == null) {
        secondary = unitKey;
      }
    }
    return (primary: primary, secondary: secondary);
  }

  /// Get the unit key for a path (for axis grouping).
  /// Uses baseUnit, falls back to category, then symbol.
  static String? getUnitKey(String path, MetadataStore metadataStore, {String? storedBaseUnit}) {
    final metadata = metadataStore.get(path);
    return storedBaseUnit ??
        metadata?.baseUnit ??
        metadata?.category ??
        metadata?.symbol;
  }

  /// Get axis assignment for a data source ('primary' or 'secondary').
  /// Returns 'primary' if the unitKey matches primary or if no assignment is possible.
  static String getAxisAssignment(
    String? unitKey,
    String? primaryAxisUnit,
    String? secondaryAxisUnit,
  ) {
    if (unitKey == null || primaryAxisUnit == null) return 'primary';
    if (unitKey == primaryAxisUnit) return 'primary';
    if (unitKey == secondaryAxisUnit) return 'secondary';
    return 'primary';
  }

  /// Check if a path is compatible with existing chart axes.
  /// A path is compatible if:
  /// - It has no unitKey (unknown = compatible with anything)
  /// - No axes are defined yet (first path)
  /// - Its unitKey matches the primary axis
  /// - Its unitKey matches the secondary axis
  /// - Only one axis is defined (can create secondary)
  static bool isPathCompatible(
    String? pathUnitKey,
    String? primaryAxisUnit,
    String? secondaryAxisUnit,
  ) {
    // Unknown unitKey = compatible with anything
    if (pathUnitKey == null) return true;
    // No axes yet = compatible
    if (primaryAxisUnit == null) return true;
    // Matches primary axis
    if (pathUnitKey == primaryAxisUnit) return true;
    // Can create secondary axis (secondary not yet assigned)
    if (secondaryAxisUnit == null) return true;
    // Matches secondary axis
    if (pathUnitKey == secondaryAxisUnit) return true;
    // 3rd different unit = incompatible
    return false;
  }

  /// Get the axis name for use in SfCartesianChart series.
  /// Returns 'secondaryYAxis' for secondary, 'primaryYAxis' for primary.
  static String getAxisName(
    String? unitKey,
    String? primaryAxisUnit,
    String? secondaryAxisUnit,
  ) {
    final assignment = getAxisAssignment(
      unitKey,
      primaryAxisUnit,
      secondaryAxisUnit,
    );
    return assignment == 'secondary' ? 'secondaryYAxis' : 'primaryYAxis';
  }
}
