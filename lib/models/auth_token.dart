import 'package:json_annotation/json_annotation.dart';

part 'auth_token.g.dart';

@JsonSerializable()
class AuthToken {
  final String token;
  final String? clientId;
  final DateTime? expiresAt;
  final DateTime issuedAt;
  final String serverUrl;
  final String? connectionId; // Links token to specific connection

  AuthToken({
    required this.token,
    this.clientId,
    this.expiresAt,
    DateTime? issuedAt,
    required this.serverUrl,
    this.connectionId,
  }) : issuedAt = issuedAt ?? DateTime.now();

  /// Check if token is expired or will expire soon (within 1 hour)
  bool get isExpired {
    if (expiresAt == null) return false;
    final oneHourFromNow = DateTime.now().add(const Duration(hours: 1));
    return expiresAt!.isBefore(oneHourFromNow);
  }

  /// Check if token is valid
  bool get isValid => !isExpired;

  factory AuthToken.fromJson(Map<String, dynamic> json) =>
      _$AuthTokenFromJson(json);
  Map<String, dynamic> toJson() => _$AuthTokenToJson(this);
}
