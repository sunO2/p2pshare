import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../p2p_manager.dart';
import '../widgets/chat_bubble_sent.dart';
import '../widgets/chat_bubble_received.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String deviceName;

  const ChatScreen({
    super.key,
    required this.peerId,
    this.deviceName = 'Unknown',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessageData> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _listenToEvents();
  }

  void _listenToEvents() {
    P2PManager.instance.eventStream.listen((event) {
      if (!mounted) return;

      if (event is MessageReceivedEvent && event.from == widget.peerId) {
        setState(() {
          _messages.add(
            ChatMessageData(
              message: event.message,
              timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
              isSelf: false,
            ),
          );
        });
        _scrollToBottom();
      } else if (event is MessageSentEvent && event.to == widget.peerId) {
        setState(() {
          _messages.add(
            ChatMessageData(
              message: '(sent)',
              timestamp: DateTime.now(),
              isSelf: true,
            ),
          );
        });
        _scrollToBottom();
      }
    });
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
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Column(
          children: [
            // Header
            _buildHeader(),

            // Messages
            Expanded(child: _buildMessagesArea()),

            // Input Area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: 56 + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 24, right: 24, bottom: 0),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFE8E8E6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                size: 18,
                color: Color(0xFF6D6C6A),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deviceName,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 26,
                    fontWeight: FontWeight.normal,
                    color: Color(0xFF1A1918),
                  ),
                ),
                const SizedBox(height: 4),
                _buildStatusIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFC8F0D8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF3D8A5A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '在线',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFF3D8A5A)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesArea() {
    return Container(
      color: const Color(0xFFF8F8F6),
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _messages.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final message = _messages[index];
          if (message.isSelf) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [ChatBubbleSent(message: message)],
            );
          } else {
            return ChatBubbleReceived(message: message);
          }
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        border: Border(top: BorderSide(color: Color(0xFFCCCCCC))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8E6),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9C9B99)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _sendMessage(_messageController.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF3D8A5A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    try {
      P2PManager.instance.sendMessage(widget.peerId, text);
    } catch (e) {
      debugPrint('Failed to send message: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败: $e')));
        return;
      }
    }

    _messageController.clear();

    // Add to local messages immediately for better UX
    setState(() {
      _messages.add(
        ChatMessageData(message: text, timestamp: DateTime.now(), isSelf: true),
      );
    });
    _scrollToBottom();
  }
}

class ChatMessageData {
  final String message;
  final DateTime timestamp;
  final bool isSelf;

  ChatMessageData({
    required this.message,
    required this.timestamp,
    required this.isSelf,
  });
}
