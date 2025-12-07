import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/crew_member.dart';
import '../../services/signalk_service.dart';
import '../../services/crew_service.dart';
import '../../services/intercom_service.dart';
import '../../services/tool_registry.dart';
import '../../screens/crew/crew_profile_screen.dart';
import '../../screens/crew/direct_chat_screen.dart';

/// Dashboard tool showing online crew members
class CrewListTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const CrewListTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CrewService>(
      builder: (context, crewService, child) {
        final hasProfile = crewService.hasProfile;
        final crewMembers = crewService.crewMembers.values.toList();
        final localProfile = crewService.localProfile;

        if (!hasProfile) {
          return _buildNoProfileView(context);
        }

        return ClipRect(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(context, crewMembers.length),

              // Crew list
              Flexible(
                child: crewMembers.isEmpty
                    ? _buildEmptyView()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: crewMembers.length,
                        itemBuilder: (context, index) {
                          final member = crewMembers[index];
                          final isMe = member.id == localProfile?.id;
                          final isOnline = crewService.presence[member.id]?.online ?? false;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: _getStatusColor(member.status),
                              child: Text(
                                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                            title: Text(
                              isMe ? '${member.name} (You)' : member.name,
                              style: TextStyle(
                                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              member.role.name,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: isMe
                                ? _buildStatusIndicator(member.status)
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Direct message button
                                      SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: IconButton(
                                          icon: const Icon(Icons.message_outlined, size: 18),
                                          onPressed: () => _openDirectChat(context, member),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                      // Direct call button (only if online)
                                      if (isOnline) ...[
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: IconButton(
                                            icon: const Icon(Icons.call, size: 18),
                                            onPressed: () => _startDirectCall(context, member),
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.group, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Crew',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count online',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrewList(BuildContext context, List<CrewMember> members, String? myId) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final isMe = member.id == myId;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: _getStatusColor(member.status),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          title: Text(
            isMe ? '${member.name} (You)' : member.name,
            style: TextStyle(
              fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            member.role?.name ?? 'Crew',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: _buildStatusIndicator(member.status),
        );
      },
    );
  }

  Widget _buildStatusIndicator(CrewStatus status) {
    final color = _getStatusColor(status);
    final label = _getStatusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(CrewStatus status) {
    switch (status) {
      case CrewStatus.onWatch:
        return Colors.green;
      case CrewStatus.offWatch:
        return Colors.blue;
      case CrewStatus.standby:
        return Colors.orange;
      case CrewStatus.resting:
        return Colors.purple;
      case CrewStatus.away:
        return Colors.grey;
    }
  }

  String _getStatusLabel(CrewStatus status) {
    switch (status) {
      case CrewStatus.onWatch:
        return 'On Watch';
      case CrewStatus.offWatch:
        return 'Off Watch';
      case CrewStatus.standby:
        return 'Standby';
      case CrewStatus.resting:
        return 'Resting';
      case CrewStatus.away:
        return 'Away';
    }
  }

  void _openDirectChat(BuildContext context, CrewMember member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DirectChatScreen(crewMember: member),
      ),
    );
  }

  void _startDirectCall(BuildContext context, CrewMember member) {
    final intercomService = Provider.of<IntercomService>(context, listen: false);
    intercomService.startDirectCall(member.id, member.name);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${member.name}...'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_off, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'No crew online',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProfileView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text(
              'Create a crew profile',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CrewProfileScreen()),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Setup Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builder for the crew list tool
class CrewListToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'crew_list',
      name: 'Crew List',
      description: 'View online crew members and their status',
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
    return CrewListTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) => null;
}
