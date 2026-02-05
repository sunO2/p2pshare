import 'package:get/get.dart';
import '../../data/providers/p2p_provider.dart';
import '../../services/storage_service.dart';
import '../../services/log_service.dart';
import '../../services/peer_config_service.dart';

/// 全局依赖注入
///
/// 在应用启动时注入全局单例服务
class InitialBindings extends Bindings {
  @override
  void dependencies() {
    // 注入日志服务（优先，其他服务可能依赖）
    Get.lazyPut<LogService>(() => LogService.instance, fenix: true);

    // 注入存储服务
    Get.lazyPut<StorageService>(() => StorageService.instance, fenix: true);

    // 🔥 注入设备配置服务
    Get.lazyPut<PeerConfigService>(() => PeerConfigService(), fenix: true);

    // 注入 P2P Provider（核心服务）
    Get.lazyPut<P2PProvider>(() => P2PProvider(), fenix: true);
  }
}
