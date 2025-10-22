/// Mixin for control tools that send numeric values to SignalK
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../services/signalk_service.dart';
import '../../../utils/string_extensions.dart';

/// Mixin for control tools (slider, knob, dropdown) that send numeric values
///
/// Provides shared functionality for:
/// - Sending PUT requests to SignalK server
/// - Rounding values to specified decimal places
/// - Displaying success/error feedback via SnackBars
/// - Managing sending state
mixin ControlToolMixin<T extends StatefulWidget> on State<T> {
  bool _isSending = false;

  /// Whether a value is currently being sent to the server
  bool get isSending => _isSending;

  /// Sends a numeric value to a SignalK path
  ///
  /// Parameters:
  /// - [value]: The numeric value to send
  /// - [path]: The SignalK path to send to
  /// - [signalKService]: The service to use for sending
  /// - [decimalPlaces]: Number of decimal places to round to (default: 1)
  /// - [label]: Optional label for the SnackBar message (defaults to path)
  /// - [onComplete]: Optional callback after send completes (success or failure)
  Future<void> sendNumericValue({
    required double value,
    required String path,
    required SignalKService signalKService,
    int decimalPlaces = 1,
    String? label,
    VoidCallback? onComplete,
  }) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Round the value before sending
      final multiplier = pow(10, decimalPlaces).toDouble();
      final roundedValue = (value * multiplier).round() / multiplier;

      await signalKService.sendPutRequest(path, roundedValue);

      if (mounted) {
        final displayLabel = label ?? path.toReadableLabel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayLabel set to ${roundedValue.toStringAsFixed(decimalPlaces)}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set value: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        onComplete?.call();
      }
    }
  }
}
