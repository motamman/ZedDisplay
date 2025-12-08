import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/crew_member.dart';
import '../../models/crew_message.dart';
import '../../services/messaging_service.dart';
import '../../services/crew_service.dart';
import '../../services/file_share_service.dart';
import '../../services/intercom_service.dart';
import '../../widgets/crew/file_picker_widget.dart';
import '../../widgets/crew/incoming_call_overlay.dart';

/// Screen for direct one-on-one messaging with a crew member
class DirectChatScreen extends StatefulWidget {
  final CrewMember crewMember;

  const DirectChatScreen({
    super.key,
    required this.crewMember,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage(MessagingService messagingService) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Send direct message to this specific crew member
    messagingService.sendMessage(text, toId: widget.crewMember.id);
    _messageController.clear();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _shareFile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return FilePickerWidget(
            toCrewId: widget.crewMember.id,
          );
        },
      ),
    );
  }

  void _startCall() {
    final intercomService = Provider.of<IntercomService>(context, listen: false);
    intercomService.startDirectCall(widget.crewMember.id, widget.crewMember.name);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${widget.crewMember.name}...'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MessagingService, CrewService>(
      builder: (context, messagingService, crewService, child) {
        final messages = messagingService.getDirectMessages(widget.crewMember.id);
        final isOnline = crewService.presence[widget.crewMember.id]?.online ?? false;

        return IncomingCallOverlay(
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
            title: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _getRoleColor(widget.crewMember.role),
                      child: Text(
                        widget.crewMember.name[0].toUpperCase(),
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
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.crewMember.name,
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Call button
              if (isOnline)
                IconButton(
                  icon: const Icon(Icons.call),
                  onPressed: _startCall,
                  tooltip: 'Voice Call',
                ),
              // Share file button
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _shareFile,
                tooltip: 'Share File',
              ),
            ],
          ),
          body: Column(
            children: [
              // Messages list
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMe = message.fromId == crewService.localProfile?.id;
                          return _MessageBubble(
                            message: message,
                            isMe: isMe,
                          );
                        },
                      ),
              ),

              // Input bar
              _buildInputBar(messagingService),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to ${widget.crewMember.name}',
            style: TextStyle(
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(MessagingService messagingService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attachment button
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _shareFile,
              tooltip: 'Attach',
            ),
            // Text input
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Message ${widget.crewMember.name}...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(messagingService),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: () => _sendMessage(messagingService),
              tooltip: 'Send',
            ),
          ],
        ),
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
    final timeFormat = DateFormat.Hm();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeFormat.format(message.timestamp.toLocal()),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
