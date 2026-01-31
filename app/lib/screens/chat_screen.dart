import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../p2p_manager.dart';
import '../widgets/chat_bubble_sent.dart';
import '../widgets/chat_bubble_received.dart';
import '../widgets/unified_app_bar.dart';
import '../services/p2p_event_bus.dart' as eb;
import 'device_detail_screen.dart';

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

  eb.P2PEventSubscription<eb.P2PEvent>? _statusSubscription;
  StreamSubscription<eb.P2PEvent>? _messageSubscription;
  StreamSubscription? _p2pManagerSubscription;

  /// 当前在线状态
  bool _isOnline = true;
  /// 状态文本
  String _statusText = '在线';

  @override
  void initState() {
    super.initState();
    _loadCurrentStatus();
    _listenToEvents();
    _listenToEventBus();
  }

  /// 加载当前状态
  void _loadCurrentStatus() {
    // 从 EventBus 缓存中获取当前状态
    final currentData = eb.P2PEventBus.instance.getCurrentData(widget.peerId);
    if (currentData != null) {
      final status = currentData['status'];
      if (status != null) {
        final statusStr = status.toString().toLowerCase();
        setState(() {
          _isOnline = statusStr != '离线' && statusStr != 'offline';
          _statusText = _isOnline ? (status ?? '在线') : '离线';
        });
      }
    } else {
      // 如果没有缓存，使用 isOnline 方法检查
      setState(() {
        _isOnline = eb.P2PEventBus.instance.isOnline(widget.peerId);
        _statusText = _isOnline ? '在线' : '离线';
      });
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _messageSubscription?.cancel();
    _p2pManagerSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToEvents() {
    _p2pManagerSubscription = P2PManager.instance.eventStream.listen((event) {
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

  /// 使用 EventBus 监听指定设备的在线状态和消息（带状态缓存）
  void _listenToEventBus() {
    // 监听指定 peer 的所有事件（立即获取当前状态）
    _statusSubscription = eb.P2PEventBus.instance.subscribe(
      peerId: widget.peerId,
      onData: (event) {
        if (!mounted) return;
        debugPrint('[EventBus] Chat peer ${widget.peerId} event: ${event.type}');

        // 更新在线状态
        if (event.type == 'online' || event.type == 'offline') {
          final status = event.data?['status'];
          setState(() {
            if (event.type == 'offline') {
              _isOnline = false;
              _statusText = '离线';
            } else if (status != null) {
              final statusStr = status.toString().toLowerCase();
              _isOnline = statusStr != '离线' && statusStr != 'offline';
              _statusText = status ?? '在线';
            } else {
              _isOnline = true;
              _statusText = '在线';
            }
          });
        }

        // 如果设备离线，可以显示提示
        if (event.type == 'offline') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('对方已离线'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
    );

    // 监听指定 peer 的消息事件
    _messageSubscription = eb.P2PEventBus.instance.on(
      peerId: widget.peerId,
      type: 'message',
    ).listen((event) {
      if (!mounted) return;
      debugPrint('[EventBus] Message from ${widget.peerId}: ${event.data}');
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
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header - use UnifiedAppBar
              UnifiedAppBar(
                title: widget.deviceName,
                statusIndicator: _buildStatusIndicator(),
                actions: [
                  // 设备详情按钮
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _createDeviceDetailScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8E8E6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Color(0xFF6D6C6A),
                      ),
                    ),
                  ),
                ],
              ),

              // Messages
              Expanded(child: _buildMessagesArea()),

              // Input Area
              _buildInputArea(),
            ],
          ),
        ),
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
      height: 80,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        border: Border(top: BorderSide(color: Color(0xFFCCCCCC))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8E6),
                borderRadius: BorderRadius.circular(26),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
              width: 52,
              height: 52,
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

  /// 🔄 改为异步：使用 async/await 避免阻塞 UI
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await P2PManager.instance.sendMessage(widget.peerId, text);
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

  /// 构建动态状态指示器
  Widget _buildStatusIndicator() {
    // 状态颜色
    final Color statusColor;
    final Color backgroundColor;

    if (!_isOnline) {
      statusColor = const Color(0xFFD32F2F); // Red
      backgroundColor = const Color(0xFFFFEBEE);
    } else {
      statusColor = const Color(0xFF3D8A5A); // Green
      backgroundColor = const Color(0xFFC8F0D8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 创建设备详情页面
  Widget _createDeviceDetailScreen() {
    return DeviceDetailScreen(peerId: widget.peerId);
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
