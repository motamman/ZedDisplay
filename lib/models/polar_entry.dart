/// Entry in the `GET /polars` list.
/// `source` is one of `vessel` (server default), `user` (the caller's
/// generated polars — the only ones `DELETE /polars` accepts), or
/// `library` (read-only shared).
class PolarEntry {
  const PolarEntry({
    required this.name,
    required this.path,
    required this.source,
    required this.label,
  });

  final String name;
  final String path;
  final String source;
  final String label;

  bool get isUser => source == 'user';
  bool get isVessel => source == 'vessel';
  bool get isLibrary => source == 'library';

  factory PolarEntry.fromJson(Map<String, dynamic> j) => PolarEntry(
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        source: j['source'] as String? ?? 'library',
        label: j['label'] as String? ?? (j['name'] as String? ?? ''),
      );
}
