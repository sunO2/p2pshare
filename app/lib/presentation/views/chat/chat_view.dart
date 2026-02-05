import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/chat_controller.dart';
import '../../../widgets/chat_bubble_sent.dart';
import '../../../widgets/chat_bubble_received.dart';
import '../../../widgets/unified_app_bar.dart';
import '../../../core/theme/app_theme.dart';

/// 聊天页面视图
class ChatView extends GetView<ChatController> {
  const ChatView({super.key});

  @override
  // 使用动态 tag，基于 peerId 生成唯一标识
  String get tag => 'chat_controller_${Get.parameters['peerId'] ?? 'unknown'}';

  @override
  Widget build(BuildContext context) {
    final theme = context.customTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: theme.scaffoldBackground,
        statusBarIconBrightness: theme.scaffoldBackground == AppTheme.backgroundDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: theme.scaffoldBackground == AppTheme.backgroundDark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackground,
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            Expanded(child: _buildMessagesArea(context)),
            _buildInputArea(context),
          ],
        ),
      ),
    );
  }

  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final theme = context.customTheme;
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Obx(() {
        final isOnline = controller.isOnline.value;
        final statusText = controller.statusText.value;

        return UnifiedAppBar(
          title: controller.peerName,
          subtitleWidget: isOnline
              ? const OnlineStatusIndicator(text: '在线')
              : OfflineStatusIndicator(text: statusText),
          // 🔥 settings 按钮替代 info 按钮
          actions: [
            GestureDetector(
              onTap: controller.openSettings,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.settings,
                  size: 18,
                  color: theme.iconColor,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// 构建消息区域
  Widget _buildMessagesArea(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      color: theme.scaffoldBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Obx(() {
        // 如果没有消息且不在加载中，显示空状态
        if (controller.messages.isEmpty && !controller.isLoadingHistory.value) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: theme.iconColorLight,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无消息记录',
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.iconColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '发送一条消息开始聊天吧',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.iconColorLight,
                  ),
                ),
              ],
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ScrollConfiguration(
            behavior: MaterialScrollBehavior().copyWith(overscroll: false),
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
            reverse: true,
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemCount: controller.messages.length + (controller.hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            // 加载更多指示器
            final isLoadMoreIndicator =
                controller.hasMore.value && index == controller.messages.length;
            if (isLoadMoreIndicator) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: controller.isLoadingHistory.value
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.statusGreen,
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.iconColorLight,
                          ),
                        ),
                      ),
              );
            }

            // 获取消息
            final message = controller.messages[index];
            final isSelf = message.isSelf;

            return isSelf
                ? ChatBubbleSent(key: ValueKey(message.id), message: message)
                : ChatBubbleReceived(key: ValueKey(message.id), message: message);
          },
        ),
          ),
        );
      }),
    );
  }

  /// 构建输入区域
  Widget _buildInputArea(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackground,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 文件按钮
            IconButton(
              onPressed: controller.sendFileMessage,
              icon: Icon(
                Icons.add_circle_outline,
                color: theme.statusGreen,
              ),
              tooltip: '发送文件',
            ),

            // 输入框
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.searchBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: controller.messageController,
                  maxLines: 5,
                  minLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.iconColor,
                  ),
                  decoration: const InputDecoration(
                    hintText: '输入消息...',
                    hintStyle: TextStyle(fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => controller.sendMessage(controller.messageController.text),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 发送按钮
            GestureDetector(
              onTap: () => controller.sendMessage(controller.messageController.text),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.statusGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
