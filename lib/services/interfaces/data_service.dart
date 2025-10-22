/// Interface for data services
library;

import '../../models/signalk_data.dart';

/// Abstract interface for data services
///
/// Defines the contract for services that provide SignalK data.
/// This allows tools to depend on an interface rather than a
/// concrete implementation, improving testability and flexibility.
abstract class DataService {
  /// Gets the latest data point for a given path
  ///
  /// If [source] is specified, returns data from that specific source.
  /// Otherwise returns the default value for the path.
  SignalKDataPoint? getValue(String path, {String? source});

  /// Gets the converted (unit-adjusted) value for a path
  ///
  /// Returns the value after unit conversion by the server,
  /// or the raw numeric value if no conversion is available.
  double? getConvertedValue(String path);

  /// Gets the unit symbol for a path
  ///
  /// Returns the unit symbol from the server's unit conversion,
  /// e.g., "kn" for knots, "°C" for Celsius.
  String? getUnitSymbol(String path);

  /// Checks if data for a path is fresh (recently updated)
  ///
  /// If [ttlSeconds] is specified, checks if data is newer than that.
  /// If [source] is specified, checks data from that specific source.
  bool isDataFresh(String path, {String? source, int? ttlSeconds});

  /// Sends a PUT request to update a SignalK value
  ///
  /// [path] is the SignalK path to update
  /// [value] is the new value to set
  Future<void> sendPutRequest(String path, dynamic value);

  /// Whether the service is currently connected
  bool get isConnected;

  /// The server URL (for creating related services like zones)
  String get serverUrl;

  /// Whether to use secure connections
  bool get useSecureConnection;
}
