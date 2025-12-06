import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/intercom_channel.dart';
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

            // Transmission indicator
            if (intercomService.currentTransmitterName != null)
              _TransmissionIndicator(
                transmitterName: intercomService.currentTransmitterName!,
                isMe: intercomService.currentTransmitterId == crewService.localProfile?.id,
              ),

            const SizedBox(height: 16),

            // PTT Button
            _PTTButton(
              isActive: intercomService.isPTTActive,
              isEnabled: intercomService.currentChannel != null &&
                        intercomService.currentTransmitterId == null,
              onPTTStart: () => intercomService.startPTT(),
              onPTTEnd: () => intercomService.stopPTT(),
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
                    intercomService.isListening ? 'Listening' : 'Ready',
                    style: TextStyle(
                      color: intercomService.isListening
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

/// Transmission indicator showing who is transmitting
class _TransmissionIndicator extends StatelessWidget {
  final String transmitterName;
  final bool isMe;

  const _TransmissionIndicator({
    required this.transmitterName,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
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
          Text(
            isMe ? 'You are transmitting' : '$transmitterName is transmitting',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isEnabled
          ? (_) {
              HapticFeedback.heavyImpact();
              widget.onPTTStart();
            }
          : null,
      onTapUp: widget.isEnabled
          ? (_) {
              HapticFeedback.lightImpact();
              widget.onPTTEnd();
            }
          : null,
      onTapCancel: widget.isEnabled ? widget.onPTTEnd : null,
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
        final transmitterName = intercomService.currentTransmitterName;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isTransmitting || transmitterName != null
                ? Colors.green.withValues(alpha: 0.2)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isTransmitting || transmitterName != null
                  ? Colors.green
                  : Colors.transparent,
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
                    if (transmitterName != null)
                      Text(
                        '$transmitterName is transmitting',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      )
                    else if (intercomService.isListening)
                      const Text(
                        'Listening',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
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
