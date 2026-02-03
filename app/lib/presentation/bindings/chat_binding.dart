import 'package:get/get.dart';
import '../controllers/chat_controller.dart';

/// 聊天页面依赖注入
class ChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ChatController>(() => ChatController());
  }
}
