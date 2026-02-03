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
          actions: [
            GestureDetector(
              onTap: controller.openDeviceDetail,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.info_outline,
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

  // 这个方法已被移除，逻辑合并到 _buildAppBar 中

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

        return ListView.separated(
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

            final message = controller.messages[index];
            if (message.isSelf) {
              return ChatBubbleSent(message: message);
            } else {
              return ChatBubbleReceived(
                message: message,
                peerName: controller.peerName,
              );
            }
          },
        );
      }),
    );
  }

  /// 构建输入区域
  Widget _buildInputArea(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 0, maxHeight: 120),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackground,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller.messageController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: null,
              decoration: InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(fontSize: 15, color: theme.iconColorLight),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.statusGreen),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.statusGreen),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.statusGreen),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
              ),
              onSubmitted: (text) => controller.sendMessage(text),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => controller.sendMessage(controller.messageController.text),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.statusGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
