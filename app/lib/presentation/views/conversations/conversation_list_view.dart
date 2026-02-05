import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import '../../../bridge/types.dart';
import '../../../core/theme/app_theme.dart';
import '../../controllers/conversation_controller.dart';

/// 会话列表视图 - GetX 版本
///
/// 基于 screens/conversation_list_screen.dart 转换
/// 功能：会话列表、加载状态、未读消息、刷新
class ConversationListView extends GetView<ConversationController> {
  const ConversationListView({super.key});

  @override
  Widget build(BuildContext context) {
    // 不使用 SafeArea，直接让 Column 从顶部开始
    return Column(
      children: [
        // 导航头 - 使用与 UnifiedAppBar 相同的高度计算
        _buildTopBar(context),

        // 扩展内容区域（刷新按钮、空状态）
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  /// 构建顶部导航栏（与 UnifiedAppBar 相同的高度）
  Widget _buildTopBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = 70.0 + topPadding;
    final theme = context.customTheme;

    return Container(
      height: totalHeight,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      decoration: BoxDecoration(color: theme.scaffoldBackground),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('我的聊天', style: context.appTextTheme.appBarTitle.copyWith(
                color: theme.scaffoldBackground == AppTheme.backgroundDark
                    ? Colors.white
                    : AppTheme.textPrimary,
              )),
              const SizedBox(height: 4),
              Obx(() => Text(
                '有 ${controller.conversations.length} 个对话',
                style: context.appTextTheme.bodyMedium,
              )),
            ],
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.cardBackground,
              shape: BoxShape.circle,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => controller.refreshConversations(),
                child: Icon(
                  Icons.refresh,
                  size: 20,
                  color: theme.iconColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      if (controller.isLoading.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.statusGreen),
              ),
              const SizedBox(height: 16),
              Text('正在加载聊天记录...', style: TextStyle(color: theme.iconColor)),
            ],
          ),
        );
      }

      if (controller.error.value != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.statusRed),
              const SizedBox(height: 16),
              Text('加载失败', style: context.appTextTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                controller.error.value!,
                style: TextStyle(color: theme.statusRed),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => controller.loadConversations(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.statusGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }

      if (controller.conversations.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: theme.iconColorLight),
              const SizedBox(height: 16),
              Text(
                '暂无聊天记录',
                style: context.appTextTheme.bodyLarge?.copyWith(color: theme.iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                '去设备列表选择一个设备开始聊天吧',
                style: context.appTextTheme.bodySmall?.copyWith(color: theme.iconColorLight),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: controller.refreshConversations,
        color: theme.statusGreen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ScrollConfiguration(
            behavior: MaterialScrollBehavior().copyWith(overscroll: false),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            itemCount: controller.sortedConversations.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final conversation = controller.sortedConversations[index];
              return _ConversationTile(
                conversation: conversation,
                onTap: () => controller.openChat(conversation),
              );
            },
          ),
          ),
        ),
      );
    });
  }
}

/// 会话列表项
class _ConversationTile extends StatelessWidget {
  final ConversationJson conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.customTheme;
    final lastMessage = conversation.lastMessage ?? '暂无消息';
    final unreadCount = conversation.unreadCount;
    final peerName = conversation.peerName ?? conversation.peerId;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            // 🔥 头像 - 点击跳转到设备详情
            GestureDetector(
              onTap: () {
                // 跳转到设备详情页面
                Get.toNamed(
                  '/device-detail',
                  parameters: {'peerId': conversation.peerId},
                );
              },
              child: CircleAvatar(
                radius: 28,
                backgroundColor: theme.statusGreen,
                child: Text(
                  peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: theme.iconColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(conversation.lastMessageTime),
                        style: TextStyle(fontSize: 12, color: theme.iconColorLight),
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
                            color: theme.iconColorLight,
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
                            color: theme.statusGreen,
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
