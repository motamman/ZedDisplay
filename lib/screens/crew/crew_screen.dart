import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crew_member.dart';
import '../../services/crew_service.dart';
import '../../widgets/crew/crew_list.dart';
import 'crew_profile_screen.dart';

/// Main crew screen with crew list and profile access
class CrewScreen extends StatelessWidget {
  const CrewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CrewService>(
      builder: (context, crewService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Crew'),
            actions: [
              // Profile button
              IconButton(
                icon: crewService.hasProfile
                    ? CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            _getRoleColor(crewService.localProfile!.role),
                        child: Text(
                          crewService.localProfile!.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : const Icon(Icons.person_add),
                onPressed: () => _openProfile(context),
                tooltip: crewService.hasProfile ? 'Edit Profile' : 'Set Up Profile',
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              // Status quick-change bar (if profile exists)
              if (crewService.hasProfile)
                _StatusBar(
                  currentStatus: crewService.localProfile!.status,
                  onStatusChanged: (status) async {
                    await crewService.setStatus(status);
                  },
                ),

              // No profile prompt
              if (!crewService.hasProfile)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_add,
                        size: 48,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Set up your crew profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create a profile to communicate with other crew members',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openProfile(context),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Create Profile'),
                      ),
                    ],
                  ),
                ),

              // Crew list
              const Expanded(child: CrewList()),
            ],
          ),
        );
      },
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CrewProfileScreen(),
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

/// Quick status change bar
class _StatusBar extends StatelessWidget {
  final CrewStatus currentStatus;
  final Function(CrewStatus) onStatusChanged;

  const _StatusBar({
    required this.currentStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Status:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: CrewStatus.values.map((status) {
                  final isSelected = currentStatus == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(status),
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : _getStatusColor(status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getStatusLabel(status),
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                      selected: isSelected,
                      selectedColor: _getStatusColor(status),
                      onSelected: (selected) {
                        if (selected) {
                          onStatusChanged(status);
                        }
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
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

  IconData _getStatusIcon(CrewStatus status) {
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

  Color _getStatusColor(CrewStatus status) {
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
