import 'package:get/get.dart';
import '../controllers/conversation_controller.dart';

/// 会话列表依赖注入
class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConversationController>(() => ConversationController());
  }
}
