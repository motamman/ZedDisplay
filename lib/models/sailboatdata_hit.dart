import 'boat.dart';

/// A single hit in the `GET /boats/search` response. All dimensions
/// normalized to SI by the server.
class SailboatdataHit {
  const SailboatdataHit({
    required this.id,
    required this.title,
    this.builder,
    this.firstBuilt,
    this.loaM,
    this.lwlM,
    this.beamM,
    this.draughtM,
    this.displacementKg,
    this.balDispRatio,
    this.saDispRatio,
    this.keelType,
    this.permalink,
  });

  final String id;
  final String title;
  final String? builder;
  final int? firstBuilt;
  final double? loaM;
  final double? lwlM;
  final double? beamM;
  final double? draughtM;
  final double? displacementKg;
  final double? balDispRatio;
  final double? saDispRatio;
  final String? keelType;
  final String? permalink;

  factory SailboatdataHit.fromJson(Map<String, dynamic> j) => SailboatdataHit(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        builder: j['builder'] as String?,
        firstBuilt: (j['first_built'] as num?)?.toInt(),
        loaM: (j['loa_m'] as num?)?.toDouble(),
        lwlM: (j['lwl_m'] as num?)?.toDouble(),
        beamM: (j['beam_m'] as num?)?.toDouble(),
        draughtM: (j['draught_m'] as num?)?.toDouble(),
        displacementKg: (j['displacement_kg'] as num?)?.toDouble(),
        balDispRatio: (j['bal_disp_ratio'] as num?)?.toDouble(),
        saDispRatio: (j['sa_disp_ratio'] as num?)?.toDouble(),
        keelType: j['keel_type'] as String?,
        permalink: j['permalink'] as String?,
      );
}

class SailboatdataSearchResult {
  const SailboatdataSearchResult({
    required this.query,
    required this.cached,
    required this.hits,
  });

  final String query;
  final bool cached;
  final List<SailboatdataHit> hits;

  factory SailboatdataSearchResult.fromJson(Map<String, dynamic> j) {
    final rawHits = j['hits'] as List? ?? const [];
    return SailboatdataSearchResult(
      query: j['query'] as String? ?? '',
      cached: j['cached'] as bool? ?? false,
      hits: rawHits
          .whereType<Map<String, dynamic>>()
          .map(SailboatdataHit.fromJson)
          .toList(growable: false),
    );
  }
}

/// Non-authoritative metadata scraped by the server from a sailboatdata
/// permalink. Shown in the editor as a read-only panel next to the
/// editable [BoatDraft] fields.
class ExternalBoatPrefill {
  const ExternalBoatPrefill({
    this.source,
    this.externalId,
    this.permalink,
    this.builder,
    this.firstBuilt,
    this.saTotalM2,
    this.balDispRatio,
    this.saDispRatio,
  });

  final String? source;
  final String? externalId;
  final String? permalink;
  final String? builder;
  final int? firstBuilt;
  final double? saTotalM2;
  final double? balDispRatio;
  final double? saDispRatio;

  static ExternalBoatPrefill? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return ExternalBoatPrefill(
      source: j['source'] as String?,
      externalId: j['id'] as String?,
      permalink: j['permalink'] as String?,
      builder: j['builder'] as String?,
      firstBuilt: (j['first_built'] as num?)?.toInt(),
      saTotalM2: (j['sa_total_m2'] as num?)?.toDouble(),
      balDispRatio: (j['bal_disp_ratio'] as num?)?.toDouble(),
      saDispRatio: (j['sa_disp_ratio'] as num?)?.toDouble(),
    );
  }
}

/// Combined payload the UI receives from
/// `GET /boats/from-external/sailboatdata/{id}`: the editable boat
/// draft plus the non-authoritative source metadata to display.
class ExternalBoatPayload {
  const ExternalBoatPayload({required this.draft, required this.external});
  final BoatDraft draft;
  final ExternalBoatPrefill? external;

  factory ExternalBoatPayload.fromJson(Map<String, dynamic> j) {
    return ExternalBoatPayload(
      draft: BoatDraft.fromJson(j),
      external:
          ExternalBoatPrefill.fromJson(j['external'] as Map<String, dynamic>?),
    );
  }
}
