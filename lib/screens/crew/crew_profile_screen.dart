import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crew_member.dart';
import '../../services/crew_service.dart';

/// Screen for setting up or editing crew profile
class CrewProfileScreen extends StatefulWidget {
  const CrewProfileScreen({super.key});

  @override
  State<CrewProfileScreen> createState() => _CrewProfileScreenState();
}

class _CrewProfileScreenState extends State<CrewProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  CrewRole _selectedRole = CrewRole.crew;
  CrewStatus _selectedStatus = CrewStatus.offWatch;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  void _loadExistingProfile() {
    final crewService = context.read<CrewService>();
    final profile = crewService.localProfile;
    if (profile != null) {
      _nameController.text = profile.name;
      _selectedRole = profile.role;
      _selectedStatus = profile.status;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final crewService = context.read<CrewService>();
      await crewService.setProfile(
        name: _nameController.text.trim(),
        role: _selectedRole,
        status: _selectedStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crewService = context.watch<CrewService>();
    final isNewProfile = crewService.localProfile == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNewProfile ? 'Set Up Profile' : 'Edit Profile'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile preview
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: _getRoleColor(_selectedRole),
                    child: Text(
                      _nameController.text.isNotEmpty
                          ? _nameController.text[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 36,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getRoleLabel(_selectedRole),
                    style: TextStyle(
                      color: _getRoleColor(_selectedRole),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Name field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'Enter your name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Role selector
            Text(
              'Role',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CrewRole.values.map((role) {
                final isSelected = _selectedRole == role;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getRoleIcon(role),
                        size: 18,
                        color: isSelected ? Colors.white : _getRoleColor(role),
                      ),
                      const SizedBox(width: 6),
                      Text(_getRoleLabel(role)),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: _getRoleColor(role),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedRole = role);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Status selector
            Text(
              'Current Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CrewStatus.values.map((status) {
                final isSelected = _selectedStatus == status;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(status),
                        size: 18,
                        color: isSelected ? Colors.white : _getStatusColor(status),
                      ),
                      const SizedBox(width: 6),
                      Text(_getStatusLabel(status)),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: _getStatusColor(status),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedStatus = status);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton.icon(
              onPressed: _isLoading ? null : _saveProfile,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(isNewProfile ? 'Create Profile' : 'Save Changes'),
            ),

            // Delete profile button (only show if profile exists)
            if (!isNewProfile) ...[
              const SizedBox(height: 48),
              const Divider(),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _confirmDeleteProfile,
                icon: const Icon(Icons.delete_forever),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                label: const Text('Delete My Profile'),
              ),
              const SizedBox(height: 8),
              Text(
                'This will remove your profile from the server and this device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: const Text(
          'This will permanently remove your crew profile from the server and this device. '
          'You will need to create a new profile to use crew features again.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteProfile();
    }
  }

  Future<void> _deleteProfile() async {
    setState(() => _isLoading = true);

    try {
      final crewService = context.read<CrewService>();
      final profileId = crewService.localProfile?.id;

      if (profileId != null) {
        final success = await crewService.deleteCrewMember(profileId);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile deleted'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to delete profile from server'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getRoleLabel(CrewRole role) {
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

  IconData _getRoleIcon(CrewRole role) {
    switch (role) {
      case CrewRole.captain:
        return Icons.star;
      case CrewRole.firstMate:
        return Icons.star_half;
      case CrewRole.crew:
        return Icons.person;
      case CrewRole.guest:
        return Icons.person_outline;
    }
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
