import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/chat_controller.dart';
import '../../../widgets/chat_bubble_sent.dart';
import '../../../widgets/chat_bubble_received.dart';
import '../../../widgets/unified_app_bar.dart';

/// 聊天页面视图
class ChatView extends GetView<ChatController> {
  const ChatView({super.key});

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
              _buildAppBar(context),
              Expanded(child: _buildMessagesArea(context)),
              _buildInputArea(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建 AppBar
  Widget _buildAppBar(BuildContext context) {
    return Obx(() => UnifiedAppBar(
          title: controller.peerName,
          subtitleWidget: _buildStatusIndicator(context),
          actions: [
            GestureDetector(
              onTap: controller.openDeviceDetail,
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
        ));
  }

  /// 构建状态指示器
  Widget _buildStatusIndicator(BuildContext context) {
    final isOnline = controller.isOnline.value;
    final statusText = controller.statusText.value;

    if (isOnline) {
      return OnlineStatusIndicator(text: statusText);
    } else {
      return OfflineStatusIndicator(text: statusText);
    }
  }

  /// 构建消息区域
  Widget _buildMessagesArea(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F8F6),
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
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无消息记录',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '发送一条消息开始聊天吧',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
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
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF3D8A5A),
                          ),
                        ),
                      )
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFCCCCCC),
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
              controller: controller.messageController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9C9B99)),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3D8A5A)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
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
}
