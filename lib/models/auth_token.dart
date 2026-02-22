import 'package:json_annotation/json_annotation.dart';

part 'auth_token.g.dart';

/// Authentication type for SignalK tokens
enum AuthType {
  device, // Device-based authentication (access request flow)
  user,   // User-based authentication (username/password login)
}

@JsonSerializable()
class AuthToken {
  final String token;
  final String? clientId;      // For device auth
  final String? username;      // For user auth
  final AuthType authType;     // Type of authentication
  final DateTime? expiresAt;
  final DateTime issuedAt;
  final String serverUrl;
  final String? connectionId;  // Links token to specific connection

  AuthToken({
    required this.token,
    this.clientId,
    this.username,
    this.authType = AuthType.device,
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
