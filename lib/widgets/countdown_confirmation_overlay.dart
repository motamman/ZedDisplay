import 'dart:async';
import 'package:flutter/material.dart';

/// Countdown confirmation overlay for critical autopilot actions
///
/// Displays a countdown timer that requires the user to confirm the action
/// by tapping the confirmation button again within the countdown period.
/// This prevents accidental tacking or waypoint changes.
class CountdownConfirmationOverlay extends StatefulWidget {
  final String title;
  final String action;
  final int countdownSeconds;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const CountdownConfirmationOverlay({
    super.key,
    required this.title,
    required this.action,
    this.countdownSeconds = 5,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<CountdownConfirmationOverlay> createState() =>
      _CountdownConfirmationOverlayState();
}

class _CountdownConfirmationOverlayState
    extends State<CountdownConfirmationOverlay>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Countdown circle with pulsing animation
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange.withOpacity(0.2 + _pulseController.value * 0.3),
                        border: Border.all(
                          color: Colors.orange,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$_remainingSeconds',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
                Text(
                  'Tap [${widget.action}] again to confirm',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('CANCEL'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _timer?.cancel();
                        widget.onConfirm();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      child: Text(widget.action.toUpperCase()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to show countdown confirmation dialog
///
/// Returns true if confirmed, false if canceled or timed out.
Future<bool> showCountdownConfirmation({
  required BuildContext context,
  required String title,
  required String action,
  int countdownSeconds = 5,
}) async {
  final completer = Completer<bool>();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => CountdownConfirmationOverlay(
      title: title,
      action: action,
      countdownSeconds: countdownSeconds,
      onConfirm: () {
        Navigator.of(context).pop();
        completer.complete(true);
      },
      onCancel: () {
        Navigator.of(context).pop();
        completer.complete(false);
      },
    ),
  );

  return completer.future;
}
