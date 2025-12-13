/// Common layout widget for control tools
library;

import 'package:flutter/material.dart';

/// Reusable layout widget for control tools (slider, knob, dropdown, switch, checkbox)
///
/// Provides consistent structure:
/// - Card with standard elevation
/// - Standard padding
/// - Optional label
/// - Optional value display
/// - Main control widget
/// - Path display at bottom
/// - Optional sending indicator
class ControlToolLayout extends StatelessWidget {
  /// Optional label text
  final String? label;

  /// Whether to show the label (from config)
  final bool showLabel;

  /// Optional widget to display the current value
  final Widget? valueWidget;

  /// The main control widget (slider, switch, etc.)
  final Widget controlWidget;

  /// The SignalK path being controlled
  final String path;

  /// Whether a value is currently being sent
  final bool isSending;

  /// Optional background color for the card
  final Color? backgroundColor;

  /// Optional additional widgets to display above the control
  final List<Widget>? additionalWidgets;

  const ControlToolLayout({
    super.key,
    this.label,
    this.showLabel = true,
    this.valueWidget,
    required this.controlWidget,
    required this.path,
    this.isSending = false,
    this.backgroundColor,
    this.additionalWidgets,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label
            if (showLabel && label != null) ...[
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
            ],

            // Value display
            if (valueWidget != null) ...[
              valueWidget!,
              const SizedBox(height: 4),
            ],

            // Additional widgets (e.g., min/max labels for slider)
            if (additionalWidgets != null) ...additionalWidgets!,

            // Main control widget
            controlWidget,

            // Path info
            const SizedBox(height: 4),
            Text(
              path,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Sending indicator
            if (isSending) ...[
              const SizedBox(height: 4),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
