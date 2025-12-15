import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../models/crew_message.dart';
import '../../services/signalk_service.dart';
import '../../services/messaging_service.dart';
import '../../services/crew_service.dart';
import '../../services/tool_registry.dart';
import '../../screens/crew/chat_screen.dart';

/// Dashboard tool for crew messaging
class CrewMessagesTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const CrewMessagesTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<CrewMessagesTool> createState() => _CrewMessagesToolState();
}

class _CrewMessagesToolState extends State<CrewMessagesTool> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage(MessagingService messagingService) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    messagingService.sendMessage(text);
    _messageController.clear();
    _focusNode.unfocus();
  }

  void _openFullChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MessagingService, CrewService>(
      builder: (context, messagingService, crewService, child) {
        final messages = messagingService.messages;
        final unreadCount = messagingService.unreadCount;
        final hasProfile = crewService.hasProfile;

        if (!hasProfile) {
          return _buildNoProfileView(context);
        }

        return ClipRect(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with unread badge and expand button
              _buildHeader(context, unreadCount),

              // Messages list - use Flexible instead of Expanded for safety
              Flexible(
                child: messages.isEmpty
                    ? _buildEmptyView()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shrinkWrap: true,
                        itemCount: messages.length > 10 ? 10 : messages.length,
                        itemBuilder: (context, index) {
                          final displayMessages = messages.length > 10
                              ? messages.sublist(messages.length - 10)
                              : messages;
                          final message = displayMessages[index];
                          final isMe = message.fromId == crewService.localProfile?.id;
                          return _MessageBubble(message: message, isMe: isMe);
                        },
                      ),
              ),

              // Quick reply input
              _buildQuickReply(context, messagingService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int unreadCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.message, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Crew Messages',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              icon: const Icon(Icons.open_in_full, size: 20),
              onPressed: () => _openFullChat(context),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(BuildContext context, List<CrewMessage> messages, String? myId) {
    // Show last N messages (most recent at bottom)
    final displayMessages = messages.length > 10
        ? messages.sublist(messages.length - 10)
        : messages;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final message = displayMessages[index];
        final isMe = message.fromId == myId;

        return _MessageBubble(
          message: message,
          isMe: isMe,
        );
      },
    );
  }

  Widget _buildQuickReply(BuildContext context, MessagingService messagingService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Message...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(messagingService),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(messagingService),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'No messages yet',
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
              'Create a crew profile to chat',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openFullChat(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Setup Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual message bubble
class _MessageBubble extends StatelessWidget {
  final CrewMessage message;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = message.type == MessageType.alert;
    final isStatus = message.type == MessageType.status;

    if (isStatus) {
      return _buildStatusMessage(context);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isAlert
              ? Colors.red.shade700
              : isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe)
              Text(
                message.fromName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isAlert ? Colors.white70 : Colors.grey,
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                color: isAlert || isMe ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            '${message.fromName}: ${message.content}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Builder for the crew messages tool
class CrewMessagesToolBuilder implements ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'crew_messages',
      name: 'Crew Messages',
      description: 'View and send messages to crew members',
      category: ToolCategory.communication,
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
    return CrewMessagesTool(
      config: config,
      signalKService: signalKService,
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) => null;
}
