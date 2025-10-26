import '../services/signalk_service.dart';
import '../utils/conversion_utils.dart';

/// Model classes for SignalK Historical Data from signalk-parquet History API
class HistoricalDataResponse {
  final String context;
  final TimeRange range;
  final List<ValueInfo> values;
  final List<DataRow> data;

  HistoricalDataResponse({
    required this.context,
    required this.range,
    required this.values,
    required this.data,
  });

  factory HistoricalDataResponse.fromJson(Map<String, dynamic> json) {
    return HistoricalDataResponse(
      context: json['context'] ?? '',
      range: TimeRange.fromJson(json['range'] ?? {}),
      values: (json['values'] as List?)
              ?.map((v) => ValueInfo.fromJson(v))
              .toList() ??
          [],
      data: (json['data'] as List?)
              ?.map((d) => DataRow.fromList(d as List))
              .toList() ??
          [],
    );
  }
}

class TimeRange {
  final DateTime from;
  final DateTime to;

  TimeRange({
    required this.from,
    required this.to,
  });

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(
      from: DateTime.parse(json['from'] ?? DateTime.now().toIso8601String()),
      to: DateTime.parse(json['to'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class ValueInfo {
  final String path;
  final String method;

  ValueInfo({
    required this.path,
    required this.method,
  });

  factory ValueInfo.fromJson(Map<String, dynamic> json) {
    return ValueInfo(
      path: json['path'] ?? '',
      method: json['method'] ?? 'average',
    );
  }

  /// Check if this is an EMA or SMA column
  bool get isMovingAverage => method == 'ema' || method == 'sma';
}

class DataRow {
  final DateTime timestamp;
  final List<dynamic> values;

  DataRow({
    required this.timestamp,
    required this.values,
  });

  factory DataRow.fromList(List<dynamic> data) {
    if (data.isEmpty) {
      return DataRow(
        timestamp: DateTime.now(),
        values: [],
      );
    }
    return DataRow(
      timestamp: DateTime.parse(data[0] as String),
      values: data.sublist(1),
    );
  }
}

/// Helper class to organize chart data for a specific path
class ChartDataSeries {
  final String path;
  final String method;
  final List<ChartDataPoint> points;
  final double? minValue;
  final double? maxValue;

  ChartDataSeries({
    required this.path,
    required this.method,
    required this.points,
    this.minValue,
    this.maxValue,
  });

  /// Extract a series from historical data response with optional client-side unit conversion
  static ChartDataSeries? fromHistoricalData(
    HistoricalDataResponse response,
    String path, {
    String method = 'average',
    SignalKService? signalKService,
  }) {
    // Find the index of this path in the values array
    final valueIndex = response.values.indexWhere(
      (v) => v.path == path && v.method == method,
    );

    if (valueIndex == -1) {
      return null;
    }

    final points = <ChartDataPoint>[];
    double? min;
    double? max;

    for (final row in response.data) {
      if (valueIndex < row.values.length) {
        final value = row.values[valueIndex];
        if (value is num) {
          final rawValue = value.toDouble();

          // Apply client-side conversion if service is provided
          final convertedValue = signalKService != null
              ? ConversionUtils.convertValue(signalKService, path, rawValue) ?? rawValue
              : rawValue;

          points.add(ChartDataPoint(
            timestamp: row.timestamp,
            value: convertedValue,
          ));

          if (min == null || convertedValue < min) {
            min = convertedValue;
          }
          if (max == null || convertedValue > max) {
            max = convertedValue;
          }
        }
      }
    }

    return ChartDataSeries(
      path: path,
      method: method,
      points: points,
      minValue: min,
      maxValue: max,
    );
  }

  /// Get display name for this series
  String get displayName {
    if (method == 'ema') {
      return '$path (EMA)';
    } else if (method == 'sma') {
      return '$path (SMA)';
    }
    return path;
  }
}

class ChartDataPoint {
  final DateTime timestamp;
  final double value;

  ChartDataPoint({
    required this.timestamp,
    required this.value,
  });
}
