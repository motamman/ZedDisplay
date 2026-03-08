/// Typed model for an AIS vessel.
/// All numeric values stored in raw SI units (radians, m/s, meters).
class AISVessel {
  final String vesselId; // e.g., "urn:mrn:imo:mmsi:123456789"
  String? name;
  double? latitude;
  double? longitude;
  double? cogRad; // Course over ground in radians
  double? sogMs; // Speed over ground in m/s
  double? headingTrueRad; // True heading in radians
  int? aisShipType;
  String? navState;
  String? aisClass;
  String? aisStatus; // from sk-ais-status-plugin
  DateTime lastSeen;
  bool fromREST;

  AISVessel({
    required this.vesselId,
    required this.lastSeen,
    this.fromREST = false,
  });

  /// Update a single field from a SignalK path suffix + raw value.
  void updateFromPath(String path, dynamic value, DateTime timestamp) {
    lastSeen = timestamp;

    switch (path) {
      case 'navigation.position':
        if (value is Map) {
          final lat = value['latitude'];
          final lon = value['longitude'];
          if (lat is num) latitude = lat.toDouble();
          if (lon is num) longitude = lon.toDouble();
        }
      case 'navigation.courseOverGroundTrue':
        if (value is num) cogRad = value.toDouble();
      case 'navigation.speedOverGround':
        if (value is num) sogMs = value.toDouble();
      case 'navigation.headingTrue':
        if (value is num) headingTrueRad = value.toDouble();
      case 'name':
        if (value is String) name = value;
      case 'design.aisShipType':
        if (value is Map) {
          aisShipType = value['id'] as int?;
        } else if (value is num) {
          aisShipType = value.toInt();
        }
      case 'navigation.state':
        if (value is String) navState = value;
      case 'sensors.ais.class':
        if (value is String) aisClass = value;
      case 'sensors.ais.status':
        if (value is String) aisStatus = value;
    }
  }

  int get ageMinutes => DateTime.now().difference(lastSeen).inMinutes;
  bool get hasPosition => latitude != null && longitude != null;
}
