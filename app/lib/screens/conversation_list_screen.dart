import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import '../bridge/types.dart';
import '../bridge/third_party/localp2p_ffi/bridge.dart';
import '../bridge/frb_generated.dart';
import '../p2p_manager.dart';
import 'chat_screen.dart';

/// 聊天会话列表页面
class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  List<ConversationJson> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('[ConversationList] initState 开始加载会话列表');
    _loadConversations();
  }

  /// 加载会话列表
  Future<void> _loadConversations() async {
    debugPrint('[ConversationList] _loadConversations 开始');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('[ConversationList] 调用 localp2PFfiBridgeP2PGetConversations()...');
      final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetConversations();
      debugPrint('[ConversationList] 返回 ${result.length} 个会话');

      if (mounted) {
        setState(() {
          _conversations = result;
          _isLoading = false;
        });
      }

      // 打印每个会话的详细信息
      for (var conv in result) {
        debugPrint('[ConversationList] 会话: peerId=${conv.peerId}, peerName=${conv.peerName}, lastMessage=${conv.lastMessage}');
      }
    } catch (e, stackTrace) {
      debugPrint('[ConversationList] 加载失败: $e');
      debugPrint('[ConversationList] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header Section
        _buildHeaderSection(),

        // Content
        Expanded(
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Top Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('我的聊天', style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(height: 4),
                  Text(
                    '有 ${_conversations.length} 个对话',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _isLoading ? null : _loadConversations,
                    child: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: Color(0xFF6D6C6A),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D8A5A)),
            ),
            SizedBox(height: 16),
            Text('正在加载聊天记录...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text('加载失败', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadConversations,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无聊天记录',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '去设备列表选择一个设备开始聊天吧',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // 按最后消息时间排序（最新的在最前）
    final sortedConversations = List<ConversationJson>.from(_conversations);
    sortedConversations.sort((a, b) {
      final timeA = a.lastMessageTime?.toInt() ?? 0;
      final timeB = b.lastMessageTime?.toInt() ?? 0;
      return timeB.compareTo(timeA);
    });

    debugPrint('[ConversationList] 显示 ${sortedConversations.length} 个会话');

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView.separated(
         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), 
        itemCount: sortedConversations.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final conversation = sortedConversations[index];
          return _ConversationTile(
            conversation: conversation,
            onTap: () => _openChat(conversation),
          );
        },
      ),
    );
  }

  void _openChat(ConversationJson conversation) {
    debugPrint('[ConversationList] 打开聊天: peerId=${conversation.peerId}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          peerId: conversation.peerId,
          peerName: conversation.peerName ?? conversation.peerId,
        ),
      ),
    ).then((_) {
      // 从聊天页面返回时，刷新会话列表
      debugPrint('[ConversationList] 返回，刷新会话列表');
      _loadConversations();
    });
  }
}

/// 会话列表项
class _ConversationTile extends StatelessWidget {
  final ConversationJson conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation.lastMessage ?? '暂无消息';
    final lastMessageTime = _formatTime(conversation.lastMessageTime);
    final unreadCount = conversation.unreadCount;
    final peerName = conversation.peerName ?? conversation.peerId;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E8E6)),
        ),
        child: Row(
          children: [
            // 头像
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF3D8A5A),
              child: Text(
                peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          peerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        lastMessageTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3D8A5A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(PlatformInt64? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final msgTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
    final diff = now.difference(msgTime);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${msgTime.month}/${msgTime.day}';
    }
  }
}
