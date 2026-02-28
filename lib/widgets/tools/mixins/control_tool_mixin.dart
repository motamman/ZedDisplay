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
  /// - [source]: IGNORED - source in PUT identifies the sender, not the target.
  ///   We read from a specific source but write as ourselves.
  /// - [decimalPlaces]: Number of decimal places to round to (default: 1)
  /// - [label]: Optional label for the SnackBar message (defaults to path)
  /// - [onComplete]: Optional callback after send completes (success or failure)
  Future<void> sendNumericValue({
    required double value,
    required String path,
    required SignalKService signalKService,
    String? source, // Kept for API compatibility but not used
    int decimalPlaces = 1,
    String? label,
    VoidCallback? onComplete,
  }) async {
    setState(() {
      _isSending = true;
    });

    try {
      // Round the display value before converting
      final multiplier = pow(10, decimalPlaces).toDouble();
      final roundedDisplayValue = (value * multiplier).round() / multiplier;

      // Convert display value back to raw SI value for PUT
      // e.g., 70 (displayed %) -> 0.70 (raw ratio)
      final metadata = signalKService.metadataStore.get(path);
      final rawValue = metadata?.convertToSI(roundedDisplayValue) ?? roundedDisplayValue;

      await signalKService.sendPutRequest(path, rawValue);

      if (mounted) {
        final displayLabel = label ?? path.toReadableLabel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayLabel set to ${roundedDisplayValue.toStringAsFixed(decimalPlaces)}'),
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
