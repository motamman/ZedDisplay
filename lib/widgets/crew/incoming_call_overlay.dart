import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/intercom_service.dart';

/// Overlay widget that shows incoming call UI and active call UI
class IncomingCallOverlay extends StatelessWidget {
  final Widget child;

  const IncomingCallOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<IntercomService>(
      builder: (context, intercomService, _) {
        return Stack(
          children: [
            child,
            // Incoming call banner
            if (intercomService.hasIncomingCall)
              _IncomingCallBanner(
                callerName: intercomService.incomingCallFromName ?? 'Unknown',
                onAccept: () => intercomService.answerIncomingCall(),
                onDecline: () => intercomService.declineIncomingCall(),
              ),
            // Active call banner
            if (intercomService.isInDirectCall && !intercomService.hasIncomingCall)
              _ActiveCallBanner(
                targetName: intercomService.directCallTargetName ?? 'Unknown',
                onHangUp: () => intercomService.endDirectCall(),
                onMute: () => intercomService.toggleMute(),
                isMuted: intercomService.isMuted,
              ),
          ],
        );
      },
    );
  }
}

class _IncomingCallBanner extends StatefulWidget {
  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingCallBanner({
    required this.callerName,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<_IncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.green,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.green,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Incoming Call',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          widget.callerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.onDecline,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.call_end),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Accept button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.call),
                      label: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner showing active call with hang up button
class _ActiveCallBanner extends StatelessWidget {
  final String targetName;
  final VoidCallback onHangUp;
  final VoidCallback onMute;
  final bool isMuted;

  const _ActiveCallBanner({
    required this.targetName,
    required this.onHangUp,
    required this.onMute,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.green,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.call,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'In Call',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      targetName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Mute button
              IconButton(
                onPressed: onMute,
                icon: Icon(
                  isMuted ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                ),
                tooltip: isMuted ? 'Unmute' : 'Mute',
              ),
              const SizedBox(width: 8),
              // Hang up button
              ElevatedButton.icon(
                onPressed: onHangUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.call_end),
                label: const Text('Hang Up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
