import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/intercom_channel.dart' show IntercomChannel, IntercomMode;
import '../../services/intercom_service.dart';
import '../../services/crew_service.dart';

/// Intercom panel with PTT button and channel selector
class IntercomPanel extends StatelessWidget {
  const IntercomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<IntercomService, CrewService>(
      builder: (context, intercomService, crewService, child) {
        if (!crewService.hasProfile) {
          return _buildNoProfileMessage(context);
        }

        if (!intercomService.hasMicPermission) {
          return _buildPermissionRequest(context, intercomService);
        }

        return Column(
          children: [
            // Channel selector
            _ChannelSelector(
              channels: intercomService.channels,
              currentChannel: intercomService.currentChannel,
              onChannelSelected: (channel) => intercomService.selectChannel(channel),
            ),

            const SizedBox(height: 16),

            // Transmission indicator (shows all active transmitters)
            if (intercomService.hasActiveTransmitters)
              _TransmissionIndicator(
                activeTransmitters: intercomService.activeTransmitters,
                myId: crewService.localProfile?.id,
              ),

            const SizedBox(height: 16),

            // PTT Button - in duplex mode, allow transmit even when receiving
            _PTTButton(
              isActive: intercomService.isPTTActive,
              isEnabled: intercomService.currentChannel != null &&
                        (intercomService.isDuplexMode || !intercomService.isReceiving),
              onPTTStart: () => intercomService.startPTT(),
              onPTTEnd: () => intercomService.stopPTT(),
            ),

            // Start/Stop button for duplex mode
            if (intercomService.isDuplexMode && intercomService.currentChannel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: () {
                    if (intercomService.isPTTActive) {
                      intercomService.stopPTT();
                    } else {
                      intercomService.startPTT();
                    }
                  },
                  icon: Icon(intercomService.isPTTActive ? Icons.stop : Icons.play_arrow),
                  label: Text(intercomService.isPTTActive ? 'STOP' : 'START'),
                  style: FilledButton.styleFrom(
                    backgroundColor: intercomService.isPTTActive ? Colors.red : Colors.green,
                  ),
                ),
              )
            // Stop button for PTT mode (visible when transmitting as fallback)
            else if (intercomService.isPTTActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () => intercomService.stopPTT(),
                  icon: const Icon(Icons.stop, color: Colors.red),
                  label: const Text('TAP TO STOP', style: TextStyle(color: Colors.red)),
                ),
              ),

            const SizedBox(height: 16),

            // Mode toggle
            _ModeToggle(
              mode: intercomService.mode,
              onModeChanged: (mode) => intercomService.setMode(mode),
            ),

            const SizedBox(height: 16),

            // Controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mute button
                IconButton.filled(
                  onPressed: intercomService.toggleMute,
                  icon: Icon(
                    intercomService.isMuted ? Icons.mic_off : Icons.mic,
                  ),
                  tooltip: intercomService.isMuted ? 'Unmute' : 'Mute',
                  style: IconButton.styleFrom(
                    backgroundColor: intercomService.isMuted
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),

                const SizedBox(width: 16),

                // Channel info
                if (intercomService.currentChannel != null)
                  Text(
                    intercomService.isDuplexMode
                        ? (intercomService.isPTTActive ? 'Open Channel' : 'Ready')
                        : (intercomService.isListening ? 'Listening' : 'Ready'),
                    style: TextStyle(
                      color: intercomService.isPTTActive || intercomService.isListening
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoProfileMessage(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Create a crew profile to use the intercom',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRequest(BuildContext context, IntercomService service) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.mic_none,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Microphone permission required for voice intercom',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final granted = await service.requestMicPermission();
              if (!granted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please grant microphone permission in settings'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.mic),
            label: const Text('Grant Permission'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Channel selector dropdown
class _ChannelSelector extends StatelessWidget {
  final List<IntercomChannel> channels;
  final IntercomChannel? currentChannel;
  final Function(IntercomChannel) onChannelSelected;

  const _ChannelSelector({
    required this.channels,
    required this.currentChannel,
    required this.onChannelSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentChannel?.id,
          hint: const Text('Select Channel'),
          isExpanded: true,
          items: channels.map((channel) {
            return DropdownMenuItem(
              value: channel.id,
              child: Row(
                children: [
                  Icon(
                    channel.isEmergency ? Icons.warning : Icons.radio,
                    color: channel.isEmergency ? Colors.red : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          style: TextStyle(
                            fontWeight: channel.isEmergency
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: channel.isEmergency ? Colors.red : null,
                          ),
                        ),
                        if (channel.description != null)
                          Text(
                            channel.description!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (channelId) {
            if (channelId != null) {
              final channel = channels.firstWhere((c) => c.id == channelId);
              onChannelSelected(channel);
            }
          },
        ),
      ),
    );
  }
}

/// Transmission indicator showing who is transmitting (supports multiple)
class _TransmissionIndicator extends StatelessWidget {
  final Map<String, String> activeTransmitters; // id -> name
  final String? myId;

  const _TransmissionIndicator({
    required this.activeTransmitters,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    final isTransmitting = myId != null && activeTransmitters.containsKey(myId);
    final otherTransmitters = activeTransmitters.entries
        .where((e) => e.key != myId)
        .map((e) => e.value)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isTransmitting
            ? Colors.red.withValues(alpha: 0.2)
            : Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTransmitting ? Colors.red : Colors.green,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTransmitting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'You are transmitting',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          if (isTransmitting && otherTransmitters.isNotEmpty)
            const SizedBox(height: 8),
          if (otherTransmitters.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    otherTransmitters.length == 1
                        ? '${otherTransmitters.first} is transmitting'
                        : '${otherTransmitters.length} are transmitting',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Push-to-talk button
class _PTTButton extends StatefulWidget {
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onPTTStart;
  final VoidCallback onPTTEnd;

  const _PTTButton({
    required this.isActive,
    required this.isEnabled,
    required this.onPTTStart,
    required this.onPTTEnd,
  });

  @override
  State<_PTTButton> createState() => _PTTButtonState();
}

class _PTTButtonState extends State<_PTTButton> {
  bool _isPressed = false;

  void _startTransmit() {
    if (!_isPressed && widget.isEnabled) {
      _isPressed = true;
      HapticFeedback.heavyImpact();
      widget.onPTTStart();
    }
  }

  void _stopTransmit() {
    if (_isPressed) {
      _isPressed = false;
      HapticFeedback.lightImpact();
      widget.onPTTEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isEnabled ? (_) => _startTransmit() : null,
      onTapUp: widget.isEnabled ? (_) => _stopTransmit() : null,
      onTapCancel: widget.isEnabled ? _stopTransmit : null,
      onPanEnd: widget.isEnabled ? (_) => _stopTransmit() : null,  // Also stop on drag end
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isActive
              ? Colors.red
              : widget.isEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
          boxShadow: widget.isActive
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isActive ? Icons.mic : Icons.mic_none,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              widget.isActive ? 'TRANSMITTING' : 'PUSH TO TALK',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mode toggle (PTT vs Duplex)
class _ModeToggle extends StatelessWidget {
  final IntercomMode mode;
  final Function(IntercomMode) onModeChanged;

  const _ModeToggle({
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<IntercomMode>(
      segments: const [
        ButtonSegment(
          value: IntercomMode.ptt,
          label: Text('PTT'),
          icon: Icon(Icons.touch_app),
        ),
        ButtonSegment(
          value: IntercomMode.duplex,
          label: Text('Open'),
          icon: Icon(Icons.swap_horiz),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) {
        onModeChanged(selected.first);
      },
    );
  }
}

/// Compact intercom widget for embedding in other screens
class IntercomMini extends StatelessWidget {
  final VoidCallback? onExpand;

  const IntercomMini({super.key, this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Consumer<IntercomService>(
      builder: (context, intercomService, child) {
        final channel = intercomService.currentChannel;
        final isTransmitting = intercomService.isPTTActive;
        final myId = context.read<CrewService>().localProfile?.id;
        final isReceiving = intercomService.isReceiving;

        // Get other transmitters' names
        final otherTransmitters = intercomService.activeTransmitters.entries
            .where((e) => e.key != myId)
            .map((e) => e.value)
            .toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isTransmitting
                ? Colors.red.withValues(alpha: 0.2)
                : isReceiving
                    ? Colors.green.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isTransmitting
                  ? Colors.red
                  : isReceiving
                      ? Colors.green
                      : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // Channel indicator
              Icon(
                channel?.isEmergency == true ? Icons.warning : Icons.radio,
                color: channel?.isEmergency == true
                    ? Colors.red
                    : isTransmitting
                        ? Colors.red
                        : isReceiving
                            ? Colors.green
                            : Colors.blue,
              ),
              const SizedBox(width: 12),

              // Channel name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel?.name ?? 'No Channel',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (isTransmitting && isReceiving)
                      Text(
                        'Duplex: ${otherTransmitters.join(", ")}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (isTransmitting)
                      Text(
                        intercomService.isDuplexMode ? 'Open channel active' : 'Transmitting',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (isReceiving)
                      Text(
                        otherTransmitters.length == 1
                            ? '${otherTransmitters.first} is transmitting'
                            : '${otherTransmitters.length} transmitting',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (intercomService.isListening)
                      Text(
                        intercomService.isDuplexMode ? 'Open mode' : 'Listening',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),

              // Quick mute toggle
              if (channel != null)
                IconButton(
                  icon: Icon(
                    intercomService.isMuted ? Icons.mic_off : Icons.mic,
                    color: intercomService.isMuted ? Colors.red : null,
                  ),
                  onPressed: intercomService.toggleMute,
                  tooltip: intercomService.isMuted ? 'Unmute' : 'Mute',
                ),

              // Expand button
              if (onExpand != null)
                IconButton(
                  icon: const Icon(Icons.open_in_full),
                  onPressed: onExpand,
                  tooltip: 'Open Intercom',
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Intercom status indicator that shows at the bottom when someone is transmitting
/// Uses a snackbar-style appearance to be less obtrusive
class IntercomStatusIndicator extends StatelessWidget {
  final VoidCallback? onTap;

  const IntercomStatusIndicator({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<IntercomService>(
      builder: (context, intercomService, child) {
        final channel = intercomService.currentChannel;
        final myId = context.read<CrewService>().localProfile?.id;
        final isReceiving = intercomService.isReceiving;

        // Get other transmitters' names
        final otherTransmitters = intercomService.activeTransmitters.entries
            .where((e) => e.key != myId)
            .map((e) => e.value)
            .toList();

        // Only show if in a channel and someone else is transmitting
        if (channel == null || !isReceiving) {
          return const SizedBox.shrink();
        }

        final statusText = otherTransmitters.length == 1
            ? '${otherTransmitters.first} on ${channel.name}'
            : '${otherTransmitters.length} transmitting on ${channel.name}';

        return Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: GestureDetector(
              onTap: onTap,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: Colors.green.shade700,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: intercomService.toggleMute,
                        child: Icon(
                          intercomService.isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
