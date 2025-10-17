import 'package:json_annotation/json_annotation.dart';

part 'server_connection.g.dart';

/// Represents a saved SignalK server connection
@JsonSerializable()
class ServerConnection {
  final String id; // Unique identifier
  final String name; // User-friendly name for this connection
  final String serverUrl; // Server URL (e.g., "192.168.1.88:3000")
  final bool useSecure; // Whether to use HTTPS/WSS
  final DateTime createdAt; // When this connection was first saved
  final DateTime? lastConnectedAt; // Last successful connection time

  ServerConnection({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.useSecure,
    required this.createdAt,
    this.lastConnectedAt,
  });

  /// Create a copy with updated fields
  ServerConnection copyWith({
    String? id,
    String? name,
    String? serverUrl,
    bool? useSecure,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
  }) {
    return ServerConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      useSecure: useSecure ?? this.useSecure,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  /// JSON serialization
  factory ServerConnection.fromJson(Map<String, dynamic> json) =>
      _$ServerConnectionFromJson(json);

  Map<String, dynamic> toJson() => _$ServerConnectionToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerConnection &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
