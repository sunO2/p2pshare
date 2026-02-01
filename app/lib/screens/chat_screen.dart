import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../p2p_manager.dart';
import '../widgets/chat_bubble_sent.dart';
import '../widgets/chat_bubble_received.dart';
import '../widgets/unified_app_bar.dart';
import '../services/p2p_event_bus.dart' as eb;
import '../bridge/types.dart';
import '../bridge/third_party/localp2p_ffi/bridge.dart';
import '../bridge/frb_generated.dart';
import 'device_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;

  const ChatScreen({
    super.key,
    required this.peerId,
    this.peerName = 'Unknown',
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

  /// 是否正在加载历史消息
  bool _isLoadingHistory = false;
  /// 是否还有更多历史消息
  bool _hasMore = true;
  /// 每页消息数量
  final int _pageSize = 20;

  /// 🔥 自动加载更多：是否已经触发过一次加载
  bool _autoLoadTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentStatus();
    _loadHistoricalMessages();
    _listenToEvents();
    _listenToEventBus();
    _setupScrollListener();
  }

  /// 🔥 设置滚动监听，实现自动加载更多
  void _setupScrollListener() {
    _scrollController.addListener(() {
      // 使用 reverse 模式时：
      // - position.pixels 接近 0 = 底部（最新消息）
      // - position.pixels 接近 maxScrollExtent = 顶部（最旧消息）
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final current = position.pixels;

      // 当滚动到接近顶部（剩余少于 300px）时触发加载
      // reverse 模式下，顶部是 maxScrollExtent
      final distanceFromTop = maxScroll - current;

      if (_hasMore &&
          !_isLoadingHistory &&
          !_autoLoadTriggered &&
          distanceFromTop < 300) {
        debugPrint('[ChatScreen] 触发自动加载更多');
        _autoLoadTriggered = true;
        _loadHistoricalMessages(loadMore: true);
      }

      // 当用户离开顶部时重置触发标志
      if (distanceFromTop > 500) {
        _autoLoadTriggered = false;
      }
    });
  }

  /// 加载历史消息
  Future<void> _loadHistoricalMessages({bool loadMore = false}) async {
    if (_isLoadingHistory) return;
    if (loadMore && !_hasMore) return;

    debugPrint('[ChatScreen] _loadHistoricalMessages 开始加载历史消息 ${loadMore ? "(加载更多)" : ""}');
    debugPrint('[ChatScreen] peerId: ${widget.peerId}');

    setState(() {
      _isLoadingHistory = true;
    });

    try {
      // 🔥 使用 reverse 后，beforeTimestamp 应该取最旧消息（列表最后一条）
      final beforeTimestamp = loadMore && _messages.isNotEmpty
          ? _messages.last.timestamp.millisecondsSinceEpoch
          : null;

      debugPrint('[ChatScreen] 调用 localp2PFfiBridgeP2PGetMessagesByPeer...');
      final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetMessagesByPeer(
        peerId: widget.peerId,
        limit: _pageSize,
        beforeTimestamp: beforeTimestamp,
      );

      debugPrint('[ChatScreen] 返回 ${result.length} 条消息');

      if (mounted) {
        setState(() {
          // 🔥 后端返回倒序（最新的在前），reverse ListView 需要最新在 index 0
          // 所以直接使用，不需要反转
          final newMessages = result.map((msg) => _parseMessageJson(msg)).toList();

          if (loadMore) {
            // 加载更多：更旧的消息添加到列表末尾
            _messages.addAll(newMessages);
          } else {
            // 首次加载：直接添加（已经是新->旧顺序）
            _messages.addAll(newMessages);
          }

          // 判断是否还有更多
          _hasMore = result.length >= _pageSize;
          _isLoadingHistory = false;
        });

        debugPrint('[ChatScreen] 已加载 ${_messages.length} 条消息');

        // 🔥 加载完成后重置自动加载触发标志
        if (loadMore && mounted) {
          // 延迟重置，避免立即再次触发
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _autoLoadTriggered = false;
            }
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[ChatScreen] 加载历史消息失败: $e');
      debugPrint('[ChatScreen] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          // 加载失败也要重置触发标志
          _autoLoadTriggered = false;
        });
      }
    }
  }

  /// 解析消息 JSON
  ChatMessageData _parseMessageJson(MessageJson msg) {
    // 解析消息内容
    String displayText = '';
    try {
      final contentJson = jsonDecode(msg.content);
      if (msg.messageType == 1) {
        // 文本消息
        displayText = contentJson['text'] ?? '';
      } else if (msg.messageType == 2) {
        displayText = '[图片]';
      } else if (msg.messageType == 3) {
        displayText = '[视频]';
      } else if (msg.messageType == 4) {
        displayText = '[文件]';
      } else if (msg.messageType == 5) {
        displayText = '[音频]';
      } else {
        displayText = '[未知消息]';
      }
    } catch (e) {
      displayText = msg.content;
    }

    // 判断是否是自己发送的消息
    final isSelf = msg.senderPeerId == _getLocalPeerId();

    return ChatMessageData(
      message: displayText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
      isSelf: isSelf,
    );
  }

  /// 获取本地 Peer ID
  String _getLocalPeerId() {
    try {
      return P2PManager.instance.getLocalPeerId();
    } catch (e) {
      return '';
    }
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
          _messages.insert(
            0,
            ChatMessageData(
              message: event.message,
              timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
              isSelf: false,
            ),
          );
        });
      } else if (event is MessageSentEvent && event.to == widget.peerId) {
        setState(() {
          _messages.insert(
            0,
            ChatMessageData(
              message: '(sent)',
              timestamp: DateTime.now(),
              isSelf: true,
            ),
          );
        });
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

      // 🔥 将收到的消息添加到列表前面（index 0 = 底部）
      final messageData = event.data;
      if (messageData is Map<String, dynamic>) {
        final message = messageData['message'] as String?;
        final timestamp = messageData['timestamp'] as int?;
        if (message != null) {
          setState(() {
            _messages.insert(
              0,
              ChatMessageData(
                message: message,
                timestamp: timestamp != null
                    ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                    : DateTime.now(),
                isSelf: false,
              ),
            );
          });
        }
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
          bottom: true,
          child: Column(
            children: [
              // Header - use UnifiedAppBar
              UnifiedAppBar(
                title: widget.peerName,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        reverse: true,  // 🔥 反转列表，最新消息在底部
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // 加载更多指示器 - reverse 时在列表末尾（最大 index）
          final isLoadMoreIndicator = _hasMore && index == _messages.length;
          if (isLoadMoreIndicator) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: _isLoadingHistory
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D8A5A)),
                      ),
                    )
                  : const SizedBox(
                      // 🔥 自动加载时显示提示，但不显示可点击按钮
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFCCCCCC)),
                      ),
                    ),
            );
          }

          // reverse 时，index 直接对应消息索引（0 是最新消息）
          final message = _messages[index];
          if (message.isSelf) {
            return ChatBubbleSent(message: message);
          } else {
            return ChatBubbleReceived(
              message: message,
              peerName: widget.peerName,
            );
          }
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      constraints: const BoxConstraints(minHeight: 0, maxHeight: 120),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        border: Border(top: BorderSide(color: Color(0xFFCCCCCC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9C9B99)),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8))
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8))
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8))
                ),
              ),
              onSubmitted: (_) => _sendMessage(_messageController.text),
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
      // 🔥 reverse ListView: index 0 在底部，新消息插入到开头
      _messages.insert(
        0,
        ChatMessageData(message: text, timestamp: DateTime.now(), isSelf: true),
      );
    });
    // 🔥 使用 reverse 后，新消息自动显示在底部，不需要手动滚动
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
