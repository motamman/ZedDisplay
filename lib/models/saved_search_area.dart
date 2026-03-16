import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// A saved geographic search area for the Historical Data Explorer.
///
/// Stores the two draw points that define a bbox (rectangle) or radius (circle)
/// area. Serializes to GeoJSON Features for interoperability and to SignalK
/// resource format for server-side persistence.
class SavedSearchArea {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final String type; // 'bbox' or 'radius'
  final double point1Lat;
  final double point1Lng;
  final double point2Lat;
  final double point2Lng;
  final double? radiusMeters; // precomputed, radius type only

  SavedSearchArea({
    String? id,
    required this.name,
    this.description,
    DateTime? createdAt,
    required this.type,
    required this.point1Lat,
    required this.point1Lng,
    required this.point2Lat,
    required this.point2Lng,
    this.radiusMeters,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  // -------------------------------------------------------------------------
  // Getters — reconstruct spatial params from stored points
  // -------------------------------------------------------------------------

  LatLng get drawPoint1 => LatLng(point1Lat, point1Lng);
  LatLng get drawPoint2 => LatLng(point2Lat, point2Lng);

  /// Bbox query param: "west,south,east,north"
  String? get bboxParam {
    if (type != 'bbox') return null;
    final west = math.min(point1Lng, point2Lng);
    final south = math.min(point1Lat, point2Lat);
    final east = math.max(point1Lng, point2Lng);
    final north = math.max(point1Lat, point2Lat);
    return '$west,$south,$east,$north';
  }

  /// Radius query param: "lon,lat,meters"
  String? get radiusParam {
    if (type != 'radius') return null;
    final meters = radiusMeters ??
        const Distance()
            .as(LengthUnit.Meter, drawPoint1, drawPoint2)
            .roundToDouble();
    return '$point1Lng,$point1Lat,${meters.round()}';
  }

  // -------------------------------------------------------------------------
  // Plain JSON — local Hive storage
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'createdAt': createdAt.toIso8601String(),
        'type': type,
        'point1Lat': point1Lat,
        'point1Lng': point1Lng,
        'point2Lat': point2Lat,
        'point2Lng': point2Lng,
        if (radiusMeters != null) 'radiusMeters': radiusMeters,
      };

  factory SavedSearchArea.fromJson(Map<String, dynamic> json) {
    return SavedSearchArea(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      type: json['type'] as String,
      point1Lat: (json['point1Lat'] as num).toDouble(),
      point1Lng: (json['point1Lng'] as num).toDouble(),
      point2Lat: (json['point2Lat'] as num).toDouble(),
      point2Lng: (json['point2Lng'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble(),
    );
  }

  // -------------------------------------------------------------------------
  // GeoJSON Feature
  // -------------------------------------------------------------------------

  /// Returns a GeoJSON Feature representation.
  /// - bbox → Polygon geometry (5-point closed ring)
  /// - radius → Point geometry with `radius` property (meters)
  Map<String, dynamic> toGeoJsonFeature() {
    final properties = <String, dynamic>{
      'name': name,
      if (description != null) 'description': description,
      'createdAt': createdAt.toIso8601String(),
      'areaType': type,
    };

    Map<String, dynamic> geometry;
    if (type == 'bbox') {
      final west = math.min(point1Lng, point2Lng);
      final south = math.min(point1Lat, point2Lat);
      final east = math.max(point1Lng, point2Lng);
      final north = math.max(point1Lat, point2Lat);
      geometry = {
        'type': 'Polygon',
        'coordinates': [
          [
            [west, south],
            [east, south],
            [east, north],
            [west, north],
            [west, south], // closed ring
          ]
        ],
      };
    } else {
      // radius — Point geometry with radius in properties
      final meters = radiusMeters ??
          const Distance()
              .as(LengthUnit.Meter, drawPoint1, drawPoint2)
              .roundToDouble();
      geometry = {
        'type': 'Point',
        'coordinates': [point1Lng, point1Lat],
      };
      properties['radius'] = meters;
    }

    return {
      'type': 'Feature',
      'geometry': geometry,
      'properties': properties,
    };
  }

  // -------------------------------------------------------------------------
  // SignalK resource format
  // -------------------------------------------------------------------------

  /// Returns data formatted for `putResource()`.
  /// Uses the notes resource pattern: name, description (JSON of GeoJSON),
  /// position.
  Map<String, dynamic> toResourceData() {
    return {
      'name': name,
      'description': jsonEncode(toGeoJsonFeature()),
      'position': {
        'latitude': point1Lat,
        'longitude': point1Lng,
      },
    };
  }

  /// Reconstruct a SavedSearchArea from server resource data.
  factory SavedSearchArea.fromResourceData(String id, Map<String, dynamic> data) {
    final geoJsonStr = data['description'] as String? ?? '{}';
    Map<String, dynamic> geoJson;
    try {
      geoJson = jsonDecode(geoJsonStr) as Map<String, dynamic>;
    } catch (_) {
      geoJson = {};
    }

    final properties = geoJson['properties'] as Map<String, dynamic>? ?? {};
    final geometry = geoJson['geometry'] as Map<String, dynamic>? ?? {};
    final areaType = properties['areaType'] as String? ?? 'bbox';

    double p1Lat, p1Lng, p2Lat, p2Lng;
    double? radius;

    if (areaType == 'bbox') {
      final coords = geometry['coordinates'] as List?;
      if (coords != null && coords.isNotEmpty) {
        final ring = coords[0] as List;
        // ring: [SW, SE, NE, NW, SW]
        p1Lng = (ring[0][0] as num).toDouble(); // west
        p1Lat = (ring[0][1] as num).toDouble(); // south
        p2Lng = (ring[2][0] as num).toDouble(); // east
        p2Lat = (ring[2][1] as num).toDouble(); // north
      } else {
        p1Lat = p1Lng = p2Lat = p2Lng = 0;
      }
    } else {
      // radius — Point geometry
      final coords = geometry['coordinates'] as List?;
      p1Lng = (coords?[0] as num?)?.toDouble() ?? 0;
      p1Lat = (coords?[1] as num?)?.toDouble() ?? 0;
      radius = (properties['radius'] as num?)?.toDouble();
      // Approximate p2 from radius (due east)
      if (radius != null && radius > 0) {
        final center = LatLng(p1Lat, p1Lng);
        final edge = const Distance().offset(center, radius, 90);
        p2Lat = edge.latitude;
        p2Lng = edge.longitude;
      } else {
        p2Lat = p1Lat;
        p2Lng = p1Lng;
      }
    }

    return SavedSearchArea(
      id: id,
      name: data['name'] as String? ?? 'Untitled',
      description: properties['description'] as String?,
      createdAt: properties['createdAt'] != null
          ? DateTime.tryParse(properties['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      type: areaType,
      point1Lat: p1Lat,
      point1Lng: p1Lng,
      point2Lat: p2Lat,
      point2Lng: p2Lng,
      radiusMeters: radius,
    );
  }
}
