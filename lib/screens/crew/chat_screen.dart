import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crew_message.dart';
import '../../services/messaging_service.dart';
import '../../services/crew_service.dart';
import '../../widgets/crew/file_picker_widget.dart';

/// Chat screen for crew messaging
class ChatScreen extends StatefulWidget {
  /// If provided, shows direct messages with this crew member
  /// If null, shows broadcast channel
  final String? directMessageCrewId;
  final String? directMessageCrewName;

  const ChatScreen({
    super.key,
    this.directMessageCrewId,
    this.directMessageCrewName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Mark messages as read when entering chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagingService>().markAllAsRead();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get isDirectMessage => widget.directMessageCrewId != null;

  String get title => isDirectMessage
      ? widget.directMessageCrewName ?? 'Direct Message'
      : 'Crew Chat';

  List<CrewMessage> _getMessages(MessagingService messagingService) {
    if (isDirectMessage) {
      return messagingService.getDirectMessages(widget.directMessageCrewId!);
    }
    return messagingService.broadcastMessages;
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    final messagingService = context.read<MessagingService>();
    final success = await messagingService.sendMessage(
      text,
      toId: widget.directMessageCrewId ?? 'all',
    );

    if (success) {
      _messageController.clear();
      _scrollToBottom();
    }

    setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!isDirectMessage)
            IconButton(
              icon: const Icon(Icons.campaign),
              tooltip: 'Quick Status',
              onPressed: () => _showStatusPicker(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: Consumer<MessagingService>(
              builder: (context, messagingService, child) {
                final messages = _getMessages(messagingService);

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDirectMessage ? Icons.chat_bubble_outline : Icons.forum_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isDirectMessage
                              ? 'No messages yet'
                              : 'No crew messages yet',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isDirectMessage
                              ? 'Start a conversation'
                              : 'Send a message to the crew',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isFromMe = message.fromId ==
                        context.read<CrewService>().localProfile?.id;

                    return _MessageBubble(
                      message: message,
                      isFromMe: isFromMe,
                    );
                  },
                );
              },
            ),
          ),

          // Message input
          _MessageInput(
            controller: _messageController,
            onSend: _sendMessage,
            isSending: _isSending,
            onAttachment: () => showFilePickerSheet(
              context,
              toCrewId: widget.directMessageCrewId,
            ),
          ),
        ],
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _StatusPickerSheet(
        onStatusSelected: (status, isAlert) async {
          Navigator.pop(context);
          final messagingService = context.read<MessagingService>();
          if (isAlert) {
            await messagingService.sendAlert(status);
          } else {
            await messagingService.sendStatusBroadcast(status);
          }
          _scrollToBottom();
        },
      ),
    );
  }
}

/// Individual message bubble
class _MessageBubble extends StatelessWidget {
  final CrewMessage message;
  final bool isFromMe;

  const _MessageBubble({
    required this.message,
    required this.isFromMe,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = message.type == MessageType.alert;
    final isStatus = message.type == MessageType.status;

    // Alerts are centered and highlighted
    if (isAlert) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fromName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    message.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Status updates are centered with icon
    if (isStatus) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${message.fromName}: ${message.content}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Regular text messages
    return Align(
      alignment: isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isFromMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isFromMe ? const Radius.circular(4) : null,
            bottomLeft: !isFromMe ? const Radius.circular(4) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isFromMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.fromName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                color: isFromMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                color: isFromMe
                    ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final localTime = time.toLocal();

    if (now.difference(time).inDays == 0) {
      // Today - show time only
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(time).inDays == 1) {
      // Yesterday
      return 'Yesterday ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else {
      // Older - show date
      return '${localTime.day}/${localTime.month} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// Message input field
class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isSending;
  final VoidCallback? onAttachment;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.isSending,
    this.onAttachment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attachment button
            if (onAttachment != null)
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: onAttachment,
                tooltip: 'Attach file',
              ),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isSending ? null : onSend,
              icon: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status picker bottom sheet
class _StatusPickerSheet extends StatelessWidget {
  final Function(String status, bool isAlert) onStatusSelected;

  const _StatusPickerSheet({required this.onStatusSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          // Alerts section
          Text(
            'Alerts',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.red,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatusMessages.alerts.map((status) {
              return ActionChip(
                avatar: const Icon(Icons.warning, color: Colors.red, size: 18),
                label: Text(status),
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                onPressed: () => onStatusSelected(status, true),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Watch status
          Text(
            'Watch Status',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatusMessages.watchStatus.map((status) {
              return ActionChip(
                label: Text(status),
                onPressed: () => onStatusSelected(status, false),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Vessel status
          Text(
            'Vessel Status',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatusMessages.vesselStatus.map((status) {
              return ActionChip(
                label: Text(status),
                onPressed: () => onStatusSelected(status, false),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // General
          Text(
            'General',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatusMessages.general.map((status) {
              return ActionChip(
                label: Text(status),
                onPressed: () => onStatusSelected(status, false),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
