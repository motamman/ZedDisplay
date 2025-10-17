import 'package:json_annotation/json_annotation.dart';

part 'access_request.g.dart';

enum AccessRequestState {
  pending,
  approved,
  denied,
  error,
}

// Custom converter for AccessRequestState to handle uppercase strings from server
class AccessRequestStateConverter implements JsonConverter<AccessRequestState, String> {
  const AccessRequestStateConverter();

  @override
  AccessRequestState fromJson(String json) {
    switch (json.toUpperCase()) {
      case 'PENDING':
        return AccessRequestState.pending;
      case 'APPROVED':
        return AccessRequestState.approved;
      case 'DENIED':
        return AccessRequestState.denied;
      default:
        return AccessRequestState.error;
    }
  }

  @override
  String toJson(AccessRequestState state) {
    switch (state) {
      case AccessRequestState.pending:
        return 'PENDING';
      case AccessRequestState.approved:
        return 'APPROVED';
      case AccessRequestState.denied:
        return 'DENIED';
      case AccessRequestState.error:
        return 'ERROR';
    }
  }
}

@JsonSerializable()
class AccessRequest {
  final String requestId;
  final String clientId;
  final String description;

  @AccessRequestStateConverter()
  final AccessRequestState state;

  final String? token;
  final DateTime? expiresAt;
  final String? statusHref;
  final String? message;

  AccessRequest({
    required this.requestId,
    required this.clientId,
    required this.description,
    required this.state,
    this.token,
    this.expiresAt,
    this.statusHref,
    this.message,
  });

  /// Copy with new state
  AccessRequest copyWith({
    AccessRequestState? state,
    String? token,
    DateTime? expiresAt,
    String? message,
  }) {
    return AccessRequest(
      requestId: requestId,
      clientId: clientId,
      description: description,
      state: state ?? this.state,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
      statusHref: statusHref,
      message: message ?? this.message,
    );
  }

  factory AccessRequest.fromJson(Map<String, dynamic> json) =>
      _$AccessRequestFromJson(json);
  Map<String, dynamic> toJson() => _$AccessRequestToJson(this);
}
