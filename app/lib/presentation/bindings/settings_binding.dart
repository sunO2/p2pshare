import 'package:get/get.dart';
import '../controllers/settings_controller.dart';

/// 设置页面依赖注入
class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SettingsController>(() => SettingsController());
  }
}
