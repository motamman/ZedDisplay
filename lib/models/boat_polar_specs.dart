/// Shape accepted by `POST /polar-from-specs`'s `specs` field
/// (`routing/routers/vpp.py:BoatSpecsModel`). A superset of the Boat
/// schema — polar generation needs hydrostatic + rig detail the
/// stored profile doesn't carry. Units: metres, kilograms, m².
///
/// Note: the server uses `draft_m` here (US spelling) while the
/// stored [Boat] profile uses `draught_m`. Both refer to the same
/// dimension; we map between them at the service boundary.
class BoatPolarSpecs {
  BoatPolarSpecs({
    required this.loaM,
    required this.lwlM,
    required this.beamM,
    required this.draftM,
    required this.displacementKg,
    required this.sailAreaUpwindM2,
    this.ballastKg,
    this.sailAreaDownwindM2 = 0.0,
    this.mastHeightM,
    this.rigType = 'sloop',
    this.keelType = 'fin',
    this.hullType = 'monohull',
  });

  double loaM;
  double lwlM;
  double beamM;
  double draftM;
  double displacementKg;
  double? ballastKg;
  double sailAreaUpwindM2;
  double sailAreaDownwindM2;
  double? mastHeightM;
  String rigType;
  String keelType;
  String hullType;

  static const List<String> rigTypes = [
    'sloop',
    'cutter',
    'ketch',
    'yawl',
    'cat',
  ];
  static const List<String> keelTypes = [
    'fin',
    'bulb',
    'wing',
    'full',
    'centerboard',
    'swing',
  ];
  static const List<String> hullTypes = [
    'monohull',
    'catamaran',
    'trimaran',
  ];

  Map<String, dynamic> toJson() => {
        'loa_m': loaM,
        'lwl_m': lwlM,
        'beam_m': beamM,
        'draft_m': draftM,
        'displacement_kg': displacementKg,
        if (ballastKg != null) 'ballast_kg': ballastKg,
        'sail_area_upwind_m2': sailAreaUpwindM2,
        'sail_area_downwind_m2': sailAreaDownwindM2,
        if (mastHeightM != null) 'mast_height_m': mastHeightM,
        'rig_type': rigType,
        'keel_type': keelType,
        'hull_type': hullType,
      };
}
