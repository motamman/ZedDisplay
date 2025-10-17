/// Model classes for SignalK data
class SignalKUpdate {
  final String context;
  final List<SignalKUpdateValue> updates;

  SignalKUpdate({
    required this.context,
    required this.updates,
  });

  factory SignalKUpdate.fromJson(Map<String, dynamic> json) {
    return SignalKUpdate(
      context: json['context'] ?? '',
      updates: (json['updates'] as List?)
              ?.map((u) => SignalKUpdateValue.fromJson(u))
              .toList() ??
          [],
    );
  }
}

class SignalKUpdateValue {
  final String? source;
  final DateTime timestamp;
  final List<SignalKValue> values;

  SignalKUpdateValue({
    this.source,
    required this.timestamp,
    required this.values,
  });

  factory SignalKUpdateValue.fromJson(Map<String, dynamic> json) {
    // Parse source - handle both standard SignalK format and units-preference format
    String? sourceLabel;
    if (json.containsKey('\$source')) {
      // Units-preference format: "$source": "pypilot" (string)
      sourceLabel = json['\$source'] as String?;
    } else if (json.containsKey('source')) {
      // Standard SignalK format: "source": {"label": "pypilot", ...} (object)
      final sourceObj = json['source'];
      if (sourceObj is Map<String, dynamic>) {
        sourceLabel = sourceObj['label'] as String?;
      } else if (sourceObj is String) {
        sourceLabel = sourceObj;
      }
    }

    return SignalKUpdateValue(
      source: sourceLabel,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      values: (json['values'] as List?)
              ?.map((v) => SignalKValue.fromJson(v))
              .toList() ??
          [],
    );
  }
}

class SignalKValue {
  final String path;
  final dynamic value;

  SignalKValue({
    required this.path,
    required this.value,
  });

  factory SignalKValue.fromJson(Map<String, dynamic> json) {
    return SignalKValue(
      path: json['path'] ?? '',
      value: json['value'],
    );
  }
}

/// Simple data holder for display
class SignalKDataPoint {
  final String path;
  final dynamic value;          // Raw value (for compatibility)
  final DateTime timestamp;
  final String? unit;

  // Units-preference plugin fields
  final double? converted;      // Converted numeric value
  final String? formatted;      // Display-ready string (e.g., "10.0 kn")
  final String? symbol;         // Unit symbol (e.g., "kn", "°C")
  final dynamic original;       // Original SI value

  SignalKDataPoint({
    required this.path,
    required this.value,
    required this.timestamp,
    this.unit,
    this.converted,
    this.formatted,
    this.symbol,
    this.original,
  });

  /// Check if this data point has converted values from units-preference plugin
  bool get hasConvertedValue => formatted != null;
}
