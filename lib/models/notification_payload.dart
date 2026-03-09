import 'dart:convert';

/// Structured payload for notification tap-to-navigate.
///
/// Types: 'signalk', 'weather_nws', 'crew_message', 'intercom', 'alarm'
class NotificationPayload {
  final String type;
  final String? notificationKey;
  final String? toolTypeId;
  final Map<String, String>? context;

  const NotificationPayload({
    required this.type,
    this.notificationKey,
    this.toolTypeId,
    this.context,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (notificationKey != null) 'notificationKey': notificationKey,
        if (toolTypeId != null) 'toolTypeId': toolTypeId,
        if (context != null) 'context': context,
      };

  factory NotificationPayload.fromJson(Map<String, dynamic> json) {
    return NotificationPayload(
      type: json['type'] as String,
      notificationKey: json['notificationKey'] as String?,
      toolTypeId: json['toolTypeId'] as String?,
      context: json['context'] != null
          ? Map<String, String>.from(json['context'] as Map)
          : null,
    );
  }

  /// Encode to JSON string for use as notification payload.
  String encode() => jsonEncode(toJson());

  /// Decode from JSON string. Returns null on failure.
  static NotificationPayload? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return NotificationPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
