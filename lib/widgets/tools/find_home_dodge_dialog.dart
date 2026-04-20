import 'dart:async';
import 'package:flutter/material.dart';

/// Post-dodge recovery dialog — offers restore, continue, or disengage.
class FindHomeDodgeRecoveryDialog extends StatefulWidget {
  final String reasonLabel;
  final String? preDodgeApState;

  const FindHomeDodgeRecoveryDialog({
    super.key,
    required this.reasonLabel,
    required this.preDodgeApState,
  });

  @override
  State<FindHomeDodgeRecoveryDialog> createState() =>
      _FindHomeDodgeRecoveryDialogState();
}

class _FindHomeDodgeRecoveryDialogState
    extends State<FindHomeDodgeRecoveryDialog> {
  static const _timeoutSeconds = 30;
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = _timeoutSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        Navigator.of(context).pop('continue');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPrevState = widget.preDodgeApState != null;

    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text(
        'Dodge Complete',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.reasonLabel,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(
            'Auto-selecting "Continue" in $_remaining s',
            style: const TextStyle(color: Colors.amber, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (hasPrevState)
          TextButton(
            onPressed: () => Navigator.of(context).pop('restore'),
            child: Text(
              'Resume ${widget.preDodgeApState}',
              style: const TextStyle(color: Colors.cyan),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('continue'),
          child: const Text(
            'Continue current course',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('disengage'),
          child: const Text(
            'Disengage autopilot',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
