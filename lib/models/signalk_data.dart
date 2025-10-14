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
    return SignalKUpdateValue(
      source: json['source']?['label'],
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
  final dynamic value;
  final DateTime timestamp;
  final String? unit;

  SignalKDataPoint({
    required this.path,
    required this.value,
    required this.timestamp,
    this.unit,
  });
}
