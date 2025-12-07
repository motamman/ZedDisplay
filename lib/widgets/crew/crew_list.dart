import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crew_member.dart';
import '../../services/crew_service.dart';

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
                title: 'Online',
                count: onlineCrew.length,
                color: Colors.green,
              ),
              ...onlineCrew.map((member) => _CrewMemberTile(
                    member: member,
                    isOnline: true,
                    isLocalUser: member.id == crewService.localProfile?.id,
                  )),
            ],
            if (offlineCrew.isNotEmpty) ...[
              _SectionHeader(
                title: 'Offline',
                count: offlineCrew.length,
                color: Colors.grey,
              ),
              ...offlineCrew.map((member) => _CrewMemberTile(
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
    required this.member,
    required this.isOnline,
    required this.isLocalUser,
  });

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
      subtitle: Row(
        children: [
          _RoleBadge(role: member.role),
          const SizedBox(width: 8),
          _StatusBadge(status: member.status),
        ],
      ),
      trailing: isOnline
          ? IconButton(
              icon: const Icon(Icons.message_outlined),
              onPressed: () {
                // TODO: Open direct message
              },
            )
          : null,
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
