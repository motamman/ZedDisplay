import 'package:flutter/material.dart';

/// Shown when the app is not connected to a SignalK server.
///
/// Drop this into any tool's build method where you'd previously
/// have an inline "Not connected" message.
class WidgetDisconnectedState extends StatelessWidget {
  const WidgetDisconnectedState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text('Not connected to SignalK server'),
        ],
      ),
    );
  }
}

/// Shown when a widget has no data source configured (or a custom message).
///
/// Pass an optional [message] to override the default text.
class WidgetEmptyState extends StatelessWidget {
  final String message;

  const WidgetEmptyState({
    super.key,
    this.message = 'No data source configured',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message),
    );
  }
}
