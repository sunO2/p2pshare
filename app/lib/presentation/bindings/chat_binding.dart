import 'package:get/get.dart';
import '../controllers/chat_controller.dart';

/// 聊天页面依赖注入
class ChatBinding extends Bindings {
  @override
  void dependencies() {
    // 从路由参数获取 peerId，为每个聊天会话创建唯一的控制器实例
    final peerId = Get.parameters['peerId'] ?? 'unknown';
    final tag = 'chat_controller_$peerId';

    // 检查是否已存在，如果不存在则创建
    if (!Get.isRegistered<ChatController>(tag: tag)) {
      Get.put<ChatController>(
        ChatController(),
        tag: tag,
      );
    }
  }
}
