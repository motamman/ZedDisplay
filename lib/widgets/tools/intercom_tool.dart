import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/intercom_channel.dart';
import '../../services/signalk_service.dart';
import '../../services/intercom_service.dart';
import '../../services/crew_service.dart';
import '../../services/tool_registry.dart';

/// Dashboard tool for voice intercom
class IntercomTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const IntercomTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<IntercomService, CrewService>(
      builder: (context, intercomService, crewService, child) {
        if (!crewService.hasProfile) {
          return _buildNoProfileView(context);
        }

        if (!intercomService.hasMicPermission) {
          return _buildPermissionView(context, intercomService);
        }

        return SizedBox.expand(
          child: Column(
            children: [
              // Header with channel selector
              _buildHeader(context, intercomService),

              // Main PTT area
              Expanded(
                child: _buildPTTArea(context, intercomService, crewService),
              ),

              // Mode toggle and controls
              _buildControls(context, intercomService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, IntercomService intercomService) {
    final channel = intercomService.currentChannel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            channel?.isEmergency == true ? Icons.warning : Icons.radio,
            size: 20,
            color: channel?.isEmergency == true ? Colors.red : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: channel?.id,
                hint: const Text('Select Channel'),
                isDense: true,
                items: intercomService.channels.map((ch) {
                  return DropdownMenuItem(
                    value: ch.id,
                    child: Text(
                      ch.name,
                      style: TextStyle(
                        color: ch.isEmergency ? Colors.red : null,
                        fontWeight: ch.isEmergency ? FontWeight.bold : null,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final ch = intercomService.channels.firstWhere((c) => c.id == id);
                    intercomService.selectChannel(ch);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPTTArea(BuildContext context, IntercomService intercomService, CrewService crewService) {
    final isTransmitting = intercomService.isPTTActive;
    final isReceiving = intercomService.isReceiving;
    final myId = crewService.localProfile?.id;

    // Get transmitters
    final otherTransmitters = intercomService.activeTransmitters.entries
        .where((e) => e.key != myId)
        .map((e) => e.value)
        .toList();

    return GestureDetector(
      onTapDown: intercomService.currentChannel != null && !intercomService.isDuplexMode
          ? (_) => _startPTT(intercomService)
          : null,
      onTapUp: !intercomService.isDuplexMode
          ? (_) => _stopPTT(intercomService)
          : null,
      onTapCancel: !intercomService.isDuplexMode
          ? () => _stopPTT(intercomService)
          : null,
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isTransmitting
              ? Colors.red.withValues(alpha: 0.3)
              : isReceiving
                  ? Colors.green.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isTransmitting
                ? Colors.red
                : isReceiving
                    ? Colors.green
                    : Colors.grey.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isTransmitting
                    ? Icons.mic
                    : isReceiving
                        ? Icons.volume_up
                        : Icons.mic_none,
                size: 48,
                color: isTransmitting
                    ? Colors.red
                    : isReceiving
                        ? Colors.green
                        : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                isTransmitting
                    ? 'TRANSMITTING'
                    : isReceiving
                        ? otherTransmitters.join(', ')
                        : intercomService.isDuplexMode
                            ? 'OPEN CHANNEL'
                            : 'PUSH TO TALK',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isTransmitting
                      ? Colors.red
                      : isReceiving
                          ? Colors.green
                          : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              if (intercomService.currentChannel == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Select a channel',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, IntercomService intercomService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute button
          IconButton(
            onPressed: intercomService.toggleMute,
            icon: Icon(
              intercomService.isMuted ? Icons.mic_off : Icons.mic,
              color: intercomService.isMuted ? Colors.red : null,
            ),
            tooltip: intercomService.isMuted ? 'Unmute' : 'Mute',
          ),

          // Mode toggle
          SegmentedButton<IntercomMode>(
            segments: const [
              ButtonSegment(
                value: IntercomMode.ptt,
                icon: Icon(Icons.touch_app, size: 16),
                label: Text('PTT'),
              ),
              ButtonSegment(
                value: IntercomMode.duplex,
                icon: Icon(Icons.swap_horiz, size: 16),
                label: Text('Open'),
              ),
            ],
            selected: {intercomService.mode},
            onSelectionChanged: (selected) {
              intercomService.setMode(selected.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          // Start/Stop button for duplex mode
          if (intercomService.isDuplexMode && intercomService.currentChannel != null)
            IconButton(
              onPressed: () {
                if (intercomService.isPTTActive) {
                  intercomService.stopPTT();
                } else {
                  intercomService.startPTT();
                }
              },
              icon: Icon(
                intercomService.isPTTActive ? Icons.stop : Icons.play_arrow,
                color: intercomService.isPTTActive ? Colors.red : Colors.green,
              ),
              tooltip: intercomService.isPTTActive ? 'Stop' : 'Start',
            )
          // Stop button for PTT mode (fallback if stuck)
          else if (intercomService.isPTTActive)
            IconButton(
              onPressed: () => intercomService.stopPTT(),
              icon: const Icon(Icons.stop, color: Colors.red),
              tooltip: 'Stop',
            ),
        ],
      ),
    );
  }

  void _startPTT(IntercomService intercomService) {
    HapticFeedback.heavyImpact();
    intercomService.startPTT();
  }

  void _stopPTT(IntercomService intercomService) {
    HapticFeedback.lightImpact();
    intercomService.stopPTT();
  }

  Widget _buildNoProfileView(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'Create a crew profile to use intercom',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionView(BuildContext context, IntercomService intercomService) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text(
              'Microphone permission required',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => intercomService.requestMicPermission(),
              icon: const Icon(Icons.mic),
              label: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builder for the intercom tool
class IntercomToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'intercom',
      name: 'Intercom',
      description: 'Voice communication with crew members',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return IntercomTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) => null;
}
