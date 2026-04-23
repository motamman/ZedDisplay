/// User-owned boat profile stored by the route planner
/// (`routing/routers/boats.py:BoatSpec`). Every dimensional field is
/// SI — the Flutter client converts for display at the UI boundary
/// via `MetadataStore`.
class Boat {
  const Boat({
    required this.id,
    required this.ownerEmail,
    required this.name,
    required this.type,
    this.loaM,
    this.beamM,
    this.draughtM,
    this.airDraftM,
    this.displacementKg,
    this.rigType,
    this.keelType,
    this.polarPath,
    this.motorSpeedMs,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerEmail;
  final String name;
  final String type; // 'sail' | 'power'
  final double? loaM;
  final double? beamM;
  final double? draughtM;
  final double? airDraftM;
  final double? displacementKg;
  final String? rigType;
  final String? keelType;
  final String? polarPath;
  final double? motorSpeedMs;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSail => type == 'sail';
  bool get isPower => type == 'power';

  factory Boat.fromJson(Map<String, dynamic> j) => Boat(
        id: j['id'] as String? ?? '',
        ownerEmail: j['owner_email'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'sail',
        loaM: (j['loa_m'] as num?)?.toDouble(),
        beamM: (j['beam_m'] as num?)?.toDouble(),
        draughtM: (j['draught_m'] as num?)?.toDouble(),
        airDraftM: (j['air_draft_m'] as num?)?.toDouble(),
        displacementKg: (j['displacement_kg'] as num?)?.toDouble(),
        rigType: j['rig_type'] as String?,
        keelType: j['keel_type'] as String?,
        polarPath: j['polar_path'] as String?,
        motorSpeedMs: (j['motor_speed_ms'] as num?)?.toDouble(),
        createdAt: _parseTs(j['created_at']),
        updatedAt: _parseTs(j['updated_at']),
      );

  static DateTime? _parseTs(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}

/// Mutable draft for create/edit flows. Serialised via [toBoatSpecJson]
/// into the shape the server's `BoatSpec` pydantic model accepts
/// (missing fields become `null` on create or remain unchanged on
/// `PATCH`). `name` + `type` are the only required server-side fields.
class BoatDraft {
  BoatDraft({
    this.name,
    this.type,
    this.loaM,
    this.beamM,
    this.draughtM,
    this.airDraftM,
    this.displacementKg,
    this.rigType,
    this.keelType,
    this.polarPath,
    this.motorSpeedMs,
  });

  String? name;
  String? type;
  double? loaM;
  double? beamM;
  double? draughtM;
  double? airDraftM;
  double? displacementKg;
  String? rigType;
  String? keelType;
  String? polarPath;
  double? motorSpeedMs;

  factory BoatDraft.fromBoat(Boat b) => BoatDraft(
        name: b.name,
        type: b.type,
        loaM: b.loaM,
        beamM: b.beamM,
        draughtM: b.draughtM,
        airDraftM: b.airDraftM,
        displacementKg: b.displacementKg,
        rigType: b.rigType,
        keelType: b.keelType,
        polarPath: b.polarPath,
        motorSpeedMs: b.motorSpeedMs,
      );

  /// Accepts the `BoatDraft`-shaped JSON from
  /// `GET /boats/from-external/sailboatdata/{id}`. Drops the
  /// `external` block — the UI surfaces that separately via
  /// [ExternalBoatPrefill].
  factory BoatDraft.fromJson(Map<String, dynamic> j) => BoatDraft(
        name: j['name'] as String?,
        type: j['type'] as String?,
        loaM: (j['loa_m'] as num?)?.toDouble(),
        beamM: (j['beam_m'] as num?)?.toDouble(),
        draughtM: (j['draught_m'] as num?)?.toDouble(),
        airDraftM: (j['air_draft_m'] as num?)?.toDouble(),
        displacementKg: (j['displacement_kg'] as num?)?.toDouble(),
        rigType: j['rig_type'] as String?,
        keelType: j['keel_type'] as String?,
        polarPath: j['polar_path'] as String?,
        motorSpeedMs: (j['motor_speed_ms'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toBoatSpecJson() => {
        if (name != null) 'name': name,
        if (type != null) 'type': type,
        if (loaM != null) 'loa_m': loaM,
        if (beamM != null) 'beam_m': beamM,
        if (draughtM != null) 'draught_m': draughtM,
        if (airDraftM != null) 'air_draft_m': airDraftM,
        if (displacementKg != null) 'displacement_kg': displacementKg,
        if (rigType != null) 'rig_type': rigType,
        if (keelType != null) 'keel_type': keelType,
        if (polarPath != null) 'polar_path': polarPath,
        if (motorSpeedMs != null) 'motor_speed_ms': motorSpeedMs,
      };

  /// Full payload including explicit `null`s for omitted fields
  /// (what `PUT /boats/{id}` needs — "any field omitted from the body
  /// goes to null").
  Map<String, dynamic> toFullReplaceJson() => {
        'name': name,
        'type': type,
        'loa_m': loaM,
        'beam_m': beamM,
        'draught_m': draughtM,
        'air_draft_m': airDraftM,
        'displacement_kg': displacementKg,
        'rig_type': rigType,
        'keel_type': keelType,
        'polar_path': polarPath,
        'motor_speed_ms': motorSpeedMs,
      };
}
