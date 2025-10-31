import 'package:flutter/material.dart';
import '../models/autopilot_v2_models.dart';

/// Widget for selecting autopilot instance (V2 API only)
///
/// Displays available autopilot instances and allows user to select one.
/// Used when V2 API is detected and multiple instances are available.
class AutopilotInstanceSelector extends StatelessWidget {
  final List<AutopilotInstance> instances;
  final AutopilotInstance? selectedInstance;
  final ValueChanged<AutopilotInstance> onSelected;

  const AutopilotInstanceSelector({
    super.key,
    required this.instances,
    this.selectedInstance,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Autopilot Instance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            ...instances.map((instance) {
              final isSelected = instance.id == selectedInstance?.id;

              return ListTile(
                selected: isSelected,
                leading: Radio<String>(
                  value: instance.id,
                  groupValue: selectedInstance?.id,
                  onChanged: (_) => onSelected(instance),
                ),
                title: Text(instance.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Provider: ${instance.provider}'),
                    Text('ID: ${instance.id}'),
                  ],
                ),
                trailing: instance.isDefault
                    ? Chip(
                        label: const Text('DEFAULT'),
                        backgroundColor: Colors.green.withOpacity(0.2),
                      )
                    : null,
                onTap: () => onSelected(instance),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show instance selector dialog
///
/// Returns the selected instance, or null if canceled.
Future<AutopilotInstance?> showInstanceSelectorDialog({
  required BuildContext context,
  required List<AutopilotInstance> instances,
  AutopilotInstance? currentInstance,
}) async {
  return showDialog<AutopilotInstance>(
    context: context,
    builder: (context) {
      AutopilotInstance? selectedInstance = currentInstance;

      return AlertDialog(
        title: const Text('Select Autopilot'),
        content: SizedBox(
          width: double.maxFinite,
          child: AutopilotInstanceSelector(
            instances: instances,
            selectedInstance: selectedInstance,
            onSelected: (instance) {
              selectedInstance = instance;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(selectedInstance),
            child: const Text('SELECT'),
          ),
        ],
      );
    },
  );
}
