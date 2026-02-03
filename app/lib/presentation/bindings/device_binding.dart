import 'package:get/get.dart';
import '../controllers/device_controller.dart';

/// 设备列表依赖注入
class DeviceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeviceController>(() => DeviceController());
  }
}
