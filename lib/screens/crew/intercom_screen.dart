import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/intercom_channel.dart';
import '../../services/intercom_service.dart';
import '../../services/crew_service.dart';
import '../../widgets/crew/intercom_panel.dart';

/// Full-screen intercom interface
class IntercomScreen extends StatelessWidget {
  const IntercomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<IntercomService, CrewService>(
      builder: (context, intercomService, crewService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Intercom'),
            actions: [
              // Manage channels
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showChannelManager(context, intercomService),
                tooltip: 'Manage Channels',
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Channel list
                  Expanded(
                    flex: 2,
                    child: _ChannelList(
                      channels: intercomService.channels,
                      currentChannel: intercomService.currentChannel,
                      onChannelSelected: (channel) => intercomService.selectChannel(channel),
                    ),
                  ),

                  const Divider(height: 32),

                  // Intercom controls
                  const Expanded(
                    flex: 3,
                    child: IntercomPanel(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showChannelManager(BuildContext context, IntercomService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _ChannelManager(
          scrollController: scrollController,
          channels: service.channels,
          onCreateChannel: (name, description) async {
            await service.createChannel(name: name, description: description);
            if (context.mounted) Navigator.pop(context);
          },
          onDeleteChannel: (channelId) => service.deleteChannel(channelId),
        ),
      ),
    );
  }
}

/// Grid list of channels
class _ChannelList extends StatelessWidget {
  final List<IntercomChannel> channels;
  final IntercomChannel? currentChannel;
  final Function(IntercomChannel) onChannelSelected;

  const _ChannelList({
    required this.channels,
    required this.currentChannel,
    required this.onChannelSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isSelected = currentChannel?.id == channel.id;

        return _ChannelCard(
          channel: channel,
          isSelected: isSelected,
          onTap: () => onChannelSelected(channel),
        );
      },
    );
  }
}

/// Individual channel card
class _ChannelCard extends StatelessWidget {
  final IntercomChannel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = channel.isEmergency
        ? Colors.red
        : isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.grey;

    return Material(
      color: isSelected
          ? color.withValues(alpha: 0.2)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                channel.isEmergency ? Icons.warning : Icons.radio,
                size: 32,
                color: color,
              ),
              const SizedBox(height: 8),
              Text(
                channel.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
              if (channel.description != null)
                Text(
                  channel.description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Channel manager bottom sheet
class _ChannelManager extends StatefulWidget {
  final ScrollController scrollController;
  final List<IntercomChannel> channels;
  final Function(String name, String? description) onCreateChannel;
  final Function(String channelId) onDeleteChannel;

  const _ChannelManager({
    required this.scrollController,
    required this.channels,
    required this.onCreateChannel,
    required this.onDeleteChannel,
  });

  @override
  State<_ChannelManager> createState() => _ChannelManagerState();
}

class _ChannelManagerState extends State<_ChannelManager> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultChannelIds = IntercomChannel.defaultChannels.map((c) => c.id).toSet();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Manage Channels',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _isCreating = true),
                tooltip: 'Create Channel',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Create channel form
          if (_isCreating) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Channel Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _isCreating = false;
                    _nameController.clear();
                    _descriptionController.clear();
                  }),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_nameController.text.isNotEmpty) {
                      widget.onCreateChannel(
                        _nameController.text,
                        _descriptionController.text.isEmpty
                            ? null
                            : _descriptionController.text,
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
          ],

          // Channel list
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: widget.channels.length,
              itemBuilder: (context, index) {
                final channel = widget.channels[index];
                final isDefault = defaultChannelIds.contains(channel.id);

                return ListTile(
                  leading: Icon(
                    channel.isEmergency ? Icons.warning : Icons.radio,
                    color: channel.isEmergency ? Colors.red : Colors.blue,
                  ),
                  title: Text(channel.name),
                  subtitle: channel.description != null
                      ? Text(channel.description!)
                      : null,
                  trailing: isDefault
                      ? const Chip(label: Text('Default'))
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Channel?'),
                                content: Text('Delete "${channel.name}"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              widget.onDeleteChannel(channel.id);
                            }
                          },
                          tooltip: 'Delete',
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
