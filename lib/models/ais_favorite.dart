/// Data model for an AIS vessel favorite
class AISFavorite {
  final String mmsi; // bare 9-digit MMSI
  String name; // vessel name (from AIS or user-entered)
  String? notes; // optional user notes
  final DateTime addedAt;

  AISFavorite({
    required this.mmsi,
    required this.name,
    this.notes,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'mmsi': mmsi,
        'name': name,
        'notes': notes,
        'addedAt': addedAt.toIso8601String(),
      };

  factory AISFavorite.fromJson(Map<String, dynamic> json) => AISFavorite(
        mmsi: json['mmsi'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
