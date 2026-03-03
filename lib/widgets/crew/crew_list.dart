import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crew_member.dart';
import '../../models/intercom_channel.dart';
import '../../services/crew_service.dart';
import '../../services/intercom_service.dart';
import '../../screens/crew/direct_chat_screen.dart';

/// Widget to display list of crew members with online/offline status
class CrewList extends StatelessWidget {
  const CrewList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CrewService>(
      builder: (context, crewService, child) {
        final onlineCrew = crewService.onlineCrew;
        final offlineCrew = crewService.offlineCrew;

        if (onlineCrew.isEmpty && offlineCrew.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No crew members yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Set up your profile to get started',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView(
          children: [
            if (onlineCrew.isNotEmpty) ...[
              _SectionHeader(
                key: const ValueKey('online_header'),
                title: 'Online',
                count: onlineCrew.length,
                color: Colors.green,
              ),
              ...onlineCrew.map((member) => _CrewMemberTile(
                    key: ValueKey('online_${member.id}'),
                    member: member,
                    isOnline: true,
                    isLocalUser: member.id == crewService.localProfile?.id,
                  )),
            ],
            if (offlineCrew.isNotEmpty) ...[
              _SectionHeader(
                key: const ValueKey('offline_header'),
                title: 'Offline',
                count: offlineCrew.length,
                color: Colors.grey,
              ),
              ...offlineCrew.map((member) => _CrewMemberTile(
                    key: ValueKey('offline_${member.id}'),
                    member: member,
                    isOnline: false,
                    isLocalUser: member.id == crewService.localProfile?.id,
                  )),
            ],
          ],
        );
      },
    );
  }
}

/// Section header for online/offline groups
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: TextStyle(color: color.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// Individual crew member list tile
class _CrewMemberTile extends StatelessWidget {
  final CrewMember member;
  final bool isOnline;
  final bool isLocalUser;

  const _CrewMemberTile({
    super.key,
    required this.member,
    required this.isOnline,
    required this.isLocalUser,
  });

  /// Extract a display-friendly identity from the member ID
  /// Returns "user:xxx" or "device:xxx" or abbreviated UUID for old profiles
  String _getIdentityDisplay() {
    final id = member.id;
    if (id.startsWith('user:')) {
      return id; // Already user:username format
    } else if (id.startsWith('device:')) {
      // Shorten device ID to first 8 chars
      final deviceId = id.substring(7);
      return 'device:${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}…';
    } else {
      // Old UUID format - show abbreviated
      return 'id:${id.length > 8 ? id.substring(0, 8) : id}…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: _getRoleColor(member.role),
            child: member.avatar != null
                ? null
                : Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Text(member.name),
          const SizedBox(width: 6),
          Text(
            '(${_getIdentityDisplay()})',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.normal,
            ),
          ),
          if (isLocalUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoleBadge(role: member.role),
              const SizedBox(width: 8),
              _StatusBadge(status: member.status),
            ],
          ),
          const SizedBox(height: 4),
          Consumer<CrewService>(
            builder: (context, crewService, child) {
              // Captains and first mates can edit any crew member's subscriptions
              final localRole = crewService.localProfile?.role;
              final isAdmin = localRole == CrewRole.captain || localRole == CrewRole.firstMate;
              final canEdit = isLocalUser || isAdmin;

              return _ChannelSubscriptionIcons(
                memberId: member.id,
                canEdit: canEdit,
              );
            },
          ),
        ],
      ),
      trailing: !isLocalUser
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Direct message button
                IconButton(
                  icon: const Icon(Icons.message_outlined, size: 20),
                  onPressed: () => _openDirectChat(context),
                  tooltip: 'Message ${member.name}',
                  visualDensity: VisualDensity.compact,
                ),
                // Direct call button (only if online)
                if (isOnline)
                  IconButton(
                    icon: const Icon(Icons.call, size: 20),
                    onPressed: () => _startDirectCall(context),
                    tooltip: 'Call ${member.name}',
                    visualDensity: VisualDensity.compact,
                  ),
                // Delete button (only for captains)
                Consumer<CrewService>(
                  builder: (context, crewService, child) {
                    if (crewService.canDelete(member.id)) {
                      return IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmDeleteMember(context, crewService),
                        tooltip: 'Remove ${member.name}',
                        visualDensity: VisualDensity.compact,
                        color: Colors.red.shade400,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _confirmDeleteMember(BuildContext context, CrewService crewService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Crew Member?'),
        content: Text(
          'Are you sure you want to remove ${member.name} from the crew? '
          'They will need to create a new profile to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await crewService.deleteCrewMember(member.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '${member.name} has been removed'
                : 'Failed to remove ${member.name}'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _openDirectChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DirectChatScreen(crewMember: member),
      ),
    );
  }

  void _startDirectCall(BuildContext context) {
    final intercomService = Provider.of<IntercomService>(context, listen: false);
    intercomService.startDirectCall(member.id, member.name);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${member.name}...'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Color _getRoleColor(CrewRole role) {
    switch (role) {
      case CrewRole.captain:
        return Colors.amber.shade700;
      case CrewRole.firstMate:
        return Colors.blue.shade700;
      case CrewRole.crew:
        return Colors.teal.shade700;
      case CrewRole.guest:
        return Colors.grey.shade600;
    }
  }
}

/// Badge showing crew role
class _RoleBadge extends StatelessWidget {
  final CrewRole role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          fontSize: 11,
          color: _getColor(),
        ),
      ),
    );
  }

  String _getLabel() {
    switch (role) {
      case CrewRole.captain:
        return 'Captain';
      case CrewRole.firstMate:
        return 'First Mate';
      case CrewRole.crew:
        return 'Crew';
      case CrewRole.guest:
        return 'Guest';
    }
  }

  Color _getColor() {
    switch (role) {
      case CrewRole.captain:
        return Colors.amber.shade700;
      case CrewRole.firstMate:
        return Colors.blue.shade700;
      case CrewRole.crew:
        return Colors.teal.shade700;
      case CrewRole.guest:
        return Colors.grey.shade600;
    }
  }
}

/// Badge showing crew status
class _StatusBadge extends StatelessWidget {
  final CrewStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 12,
            color: _getColor(),
          ),
          const SizedBox(width: 4),
          Text(
            _getLabel(),
            style: TextStyle(
              fontSize: 11,
              color: _getColor(),
            ),
          ),
        ],
      ),
    );
  }

  String _getLabel() {
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

  IconData _getIcon() {
    switch (status) {
      case CrewStatus.onWatch:
        return Icons.visibility;
      case CrewStatus.offWatch:
        return Icons.visibility_off;
      case CrewStatus.standby:
        return Icons.hourglass_empty;
      case CrewStatus.resting:
        return Icons.bed;
      case CrewStatus.away:
        return Icons.directions_walk;
    }
  }

  Color _getColor() {
    switch (status) {
      case CrewStatus.onWatch:
        return Colors.green;
      case CrewStatus.offWatch:
        return Colors.grey;
      case CrewStatus.standby:
        return Colors.orange;
      case CrewStatus.resting:
        return Colors.blue;
      case CrewStatus.away:
        return Colors.purple;
    }
  }
}

/// Channel subscription toggle icons
class _ChannelSubscriptionIcons extends StatelessWidget {
  final String memberId;
  final bool canEdit;

  const _ChannelSubscriptionIcons({
    required this.memberId,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<IntercomService>(
      builder: (context, intercomService, child) {
        final channels = intercomService.channels;
        if (channels.isEmpty) {
          return const SizedBox.shrink();
        }

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          children: channels.map((channel) {
            final isSubscribed = intercomService.isSubscribed(memberId, channel.id);
            final isEmergency = channel.isEmergency;

            return _ChannelChip(
              channel: channel,
              isSubscribed: isSubscribed,
              isEmergency: isEmergency,
              canToggle: canEdit && !isEmergency,
              onToggle: canEdit && !isEmergency
                  ? () => intercomService.toggleChannelSubscription(memberId, channel.id)
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

/// Individual channel subscription chip
class _ChannelChip extends StatelessWidget {
  final IntercomChannel channel;
  final bool isSubscribed;
  final bool isEmergency;
  final bool canToggle;
  final VoidCallback? onToggle;

  const _ChannelChip({
    required this.channel,
    required this.isSubscribed,
    required this.isEmergency,
    required this.canToggle,
    this.onToggle,
  });

  /// Get a short label for the channel (2-3 chars)
  String _getShortLabel() {
    final name = channel.name;
    if (isEmergency) return '16';
    // Use channel ID number if available (ch01 -> 01)
    if (channel.id.startsWith('ch') && channel.id.length >= 4) {
      return channel.id.substring(2, 4);
    }
    // Otherwise use first 2 letters of name
    if (name.length >= 2) {
      return name.substring(0, 2).toUpperCase();
    }
    return name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = isEmergency
        ? Colors.red
        : (isSubscribed ? Colors.green : Colors.grey);

    return Tooltip(
      message: isEmergency
          ? '${channel.name} (always on)'
          : (isSubscribed
              ? '${channel.name} - subscribed${canToggle ? ' (tap to unsubscribe)' : ''}'
              : '${channel.name} - not subscribed${canToggle ? ' (tap to subscribe)' : ''}'),
      child: InkWell(
        onTap: canToggle ? onToggle : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSubscribed
                ? color.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: isSubscribed ? 0.6 : 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEmergency) ...[
                Icon(
                  Icons.warning,
                  size: 10,
                  color: color,
                ),
                const SizedBox(width: 2),
              ],
              Text(
                _getShortLabel(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSubscribed ? FontWeight.bold : FontWeight.normal,
                  color: isSubscribed ? color : color.withValues(alpha: 0.6),
                ),
              ),
              if (isSubscribed && !isEmergency) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.check,
                  size: 8,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
