import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/setup_service.dart';
import '../services/dashboard_service.dart';
import '../models/dashboard_setup.dart';

/// Screen for managing saved dashboard setups
class SetupManagementScreen extends StatefulWidget {
  const SetupManagementScreen({super.key});

  @override
  State<SetupManagementScreen> createState() => _SetupManagementScreenState();
}

class _SetupManagementScreenState extends State<SetupManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final setupService = Provider.of<SetupService>(context);
    final savedSetups = setupService.getSavedSetups();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importSetup,
            tooltip: 'Import Setup',
          ),
        ],
      ),
      body: savedSetups.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: savedSetups.length,
              itemBuilder: (context, index) {
                final setup = savedSetups[index];
                return _buildSetupCard(setup);
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _createNewDashboard,
            heroTag: 'new_dashboard',
            icon: const Icon(Icons.add),
            label: const Text('New Dashboard'),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _saveCurrentSetup,
            heroTag: 'save_current',
            icon: const Icon(Icons.save),
            label: const Text('Save Current As'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No saved setups',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Save your current dashboard configuration\nto switch between different setups',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saveCurrentSetup,
            icon: const Icon(Icons.save),
            label: const Text('Save Current As'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupCard(SavedSetup setup) {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final isActive = dashboardService.currentLayout?.id == setup.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.dashboard,
              color: isActive ? Colors.green : Colors.blue,
              size: 32,
            ),
            title: Text(
              setup.name,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (setup.description.isNotEmpty)
                  Text(setup.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  '${setup.screenCount} screens • ${setup.toolCount} tools',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (setup.lastUsedAt != null)
                  Text(
                    'Last used: ${_formatDateTime(setup.lastUsedAt!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
            trailing: isActive
                ? const Chip(
                    label: Text('Active', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                : null,
            onTap: isActive ? null : () => _confirmLoadSetup(setup),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isActive)
                  TextButton.icon(
                    onPressed: () => _confirmLoadSetup(setup),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Switch'),
                  ),
                TextButton.icon(
                  onPressed: () => _shareSetup(setup),
                  icon: const Icon(Icons.share, size: 16),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  onPressed: () => _editSetup(setup),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
                if (!isActive)
                  TextButton.icon(
                    onPressed: () => _confirmDeleteSetup(setup),
                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Future<void> _saveCurrentSetup() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Current As'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Setup Name',
                  hintText: 'My Sailing Setup',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Dashboard configuration for sailing',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final setupService = Provider.of<SetupService>(context, listen: false);
        await setupService.saveCurrentAsSetup(
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Setup "${nameController.text.trim()}" saved'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _createNewDashboard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Dashboard'),
        content: const Text(
          'This will clear your current dashboard and create a blank one.\n\n'
          'Make sure to save your current dashboard first if you want to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create Blank Dashboard'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final dashboardService = Provider.of<DashboardService>(context, listen: false);
        final setupService = Provider.of<SetupService>(context, listen: false);

        // Create a blank layout
        await dashboardService.createNewDashboard();

        // Save it as a setup so it appears in the dashboard list
        await setupService.saveCurrentAsSetup(
          name: 'New Dashboard',
          description: 'Blank dashboard',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New blank dashboard created and saved'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back to dashboard
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating new dashboard: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmLoadSetup(SavedSetup setup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Setup'),
        content: Text(
          'Switch to "${setup.name}"?\n\nThis will replace your current dashboard configuration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final setupService = Provider.of<SetupService>(context, listen: false);
        await setupService.loadSetup(setup.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to "${setup.name}"'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _shareSetup(SavedSetup setupRef) async {
    try {
      final setupService = Provider.of<SetupService>(context, listen: false);

      // Export current setup if it's the active one, otherwise we need to load it
      final dashboardService = Provider.of<DashboardService>(context, listen: false);
      final isActive = dashboardService.currentLayout?.id == setupRef.id;

      DashboardSetup setup;
      if (isActive) {
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      } else {
        // For non-active setups, we need to access storage directly
        // Since we can't access private fields, we'll need to load and re-export
        await setupService.loadSetup(setupRef.id);
        setup = setupService.exportCurrentSetup(
          name: setupRef.name,
          description: setupRef.description,
        );
      }

      // Export to JSON
      final jsonString = setupService.exportToJson(setup);

      // Create a temporary file
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${setupRef.name.replaceAll(' ', '_')}.json');
      await file.writeAsString(jsonString);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Dashboard Setup: ${setupRef.name}',
        text: 'Check out my dashboard setup!',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup exported and ready to share'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing setup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSetup() async {
    // Show dialog with two options: Browse for file or Paste JSON
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Setup'),
        content: const Text('How would you like to import the setup?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'paste'),
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste JSON'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'browse'),
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse File'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    String? jsonString;

    if (choice == 'browse') {
      // Browse for a file
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          allowMultiple: false,
        );

        if (result != null && result.files.single.path != null) {
          final file = File(result.files.single.path!);
          jsonString = await file.readAsString();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error reading file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } else if (choice == 'paste') {
      // Paste JSON text
      final controller = TextEditingController();

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste Setup JSON'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Paste the setup JSON below:'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'JSON',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 10,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (result == true) {
        jsonString = controller.text.trim();
      }
    }

    // Import the setup
    if (jsonString != null && jsonString.isNotEmpty && mounted) {
      try {
        final setupService = Provider.of<SetupService>(context, listen: false);

        // Just import and save the setup (don't activate it)
        await setupService.importSetup(jsonString);

        if (mounted) {
          // Ask user if they want to switch to it now
          final switchNow = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Setup Imported'),
              content: const Text(
                'The setup has been saved to your list.\n\n'
                'Would you like to switch to it now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not Now'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Switch Now'),
                ),
              ],
            ),
          );

          if (switchNow == true && mounted) {
            // Load the setup by its ID
            final savedSetups = setupService.getSavedSetups();
            if (savedSetups.isNotEmpty) {
              // Find the most recently added setup (should be the one we just imported)
              final recentSetup = savedSetups.first;
              await setupService.loadSetup(recentSetup.id);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to "${recentSetup.name}"'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Setup saved. You can switch to it anytime.'),
                backgroundColor: Colors.blue,
              ),
            );
          }

          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error importing setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editSetup(SavedSetup setup) async {
    final nameController = TextEditingController(text: setup.name);
    final descriptionController = TextEditingController(text: setup.description);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Setup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Setup Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final setupService = Provider.of<SetupService>(context, listen: false);
        await setupService.renameSetup(setup.id, nameController.text.trim());
        await setupService.updateSetupDescription(setup.id, descriptionController.text.trim());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Setup updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteSetup(SavedSetup setup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Setup'),
        content: Text(
          'Are you sure you want to delete "${setup.name}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final setupService = Provider.of<SetupService>(context, listen: false);
        await setupService.deleteSetup(setup.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Setup "${setup.name}" deleted'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting setup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
