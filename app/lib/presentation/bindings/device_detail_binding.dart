import 'package:get/get.dart';
import '../controllers/device_detail_controller.dart';

/// 设备详情页面依赖注入
class DeviceDetailBinding extends Bindings {
  @override
  void dependencies() {
    // 使用动态 tag，基于 peerId 生成唯一标识
    // 这样同一设备的详情页面会共享同一个 Controller 实例
    final peerId = Get.parameters['peerId'] ?? 'unknown';
    final tag = 'device_detail_$peerId';

    Get.lazyPut<DeviceDetailController>(
      () => DeviceDetailController(),
      tag: tag,
    );
  }
}
