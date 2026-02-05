import 'package:get/get.dart';
import '../controllers/peer_settings_controller.dart';
import '../../../services/peer_config_service.dart';

/// 设备设置依赖注入
class PeerSettingsBinding extends Bindings {
  @override
  void dependencies() {
    final peerId = Get.parameters['peerId'] ?? 'unknown';
    final tag = 'peer_settings_$peerId';

    // 确保 PeerConfigService 已注册
    if (!Get.isRegistered<PeerConfigService>()) {
      Get.put(PeerConfigService());
    }

    Get.lazyPut<PeerSettingsController>(
      () => PeerSettingsController(),
      tag: tag,
    );
  }
}
