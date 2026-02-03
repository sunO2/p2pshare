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
    Get.lazyPut<DeviceController>(() => DeviceController());
    Get.lazyPut<ConversationController>(() => ConversationController());
    Get.lazyPut<SettingsController>(() => SettingsController());
    Get.lazyPut<LogsViewerController>(() => LogsViewerController());
  }
}
