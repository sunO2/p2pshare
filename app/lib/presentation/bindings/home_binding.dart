import 'package:get/get.dart';
import '../controllers/home_controller.dart';
import '../controllers/device_controller.dart';
import '../controllers/conversation_controller.dart';
import '../controllers/settings_controller.dart';

/// 首页依赖注入
///
/// 注入 HomeController 及所有子页面的 Controller
class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // 注入首页控制器
    Get.lazyPut<HomeController>(() => HomeController());

    // 注入所有子页面控制器（因为首页使用 IndexedStack 同时加载所有页面）
    // 使用 Get.put 而不是 Get.lazyPut，因为页面会被立即创建
    Get.put(DeviceController());
    Get.put(ConversationController());
    Get.put(SettingsController());

    // 强制触发 Controller 初始化（确保 onInit 被调用）
    // 这对于 IndexedStack 中的 GetView 很重要
    try {
      Get.find<DeviceController>();
      Get.find<ConversationController>();
      Get.find<SettingsController>();
    } catch (e) {
      // 忽略错误
    }
  }
}
