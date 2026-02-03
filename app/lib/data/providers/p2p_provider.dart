import 'package:get/get.dart';
import '../../../p2p_manager.dart';
import '../../services/log_service.dart';

/// P2P 服务提供者
///
/// 封装 P2PManager 单例，提供 GetX 兼容的接口
class P2PProvider extends GetxService {
  late final P2PManager _manager;
  final LogService _log = Get.find<LogService>();

  /// 是否已初始化
  final isInitialized = false.obs;

  /// 本地 Peer ID
  final localPeerId = ''.obs;

  /// 设备名称
  final deviceName = ''.obs;

  /// 初始化状态错误信息
  final Rxn<String> initError = Rxn<String>();

  P2PProvider() {
    _manager = P2PManager.instance;
    _syncState();
  }

  /// 同步状态
  void _syncState() {
    isInitialized.value = _manager.isInitialized;
    if (_manager.isInitialized) {
      try {
        localPeerId.value = _manager.getLocalPeerId();
        deviceName.value = _manager.getDeviceName();
      } catch (e) {
        _log.e('同步状态失败: $e', e);
      }
    }
  }

  /// 初始化 P2P
  Future<void> init(P2PInitConfig config) async {
    try {
      await _manager.init(config);
      _syncState();
    } catch (e) {
      initError.value = '初始化失败: $e';
      rethrow;
    }
  }

  /// 启动 P2P
  Future<void> start() async {
    await _manager.start();
    _syncState();
  }

  /// 停止 P2P
  Future<void> stop() async {
    await _manager.stop();
  }

  /// 清理资源
  void cleanup() {
    _manager.cleanup();
    isInitialized.value = false;
  }

  /// 获取已验证的节点列表
  List<dynamic> getVerifiedNodes() {
    return _manager.getVerifiedNodes();
  }

  /// 发送消息
  Future<void> sendMessage(String targetPeerId, String message) async {
    await _manager.sendMessage(targetPeerId, message);
  }

  /// 获取系统状态
  Future<SystemStatusJson> getSystemStatus() async {
    return await _manager.getSystemStatusAsync();
  }

  /// 事件流
  Stream get eventStream => _manager.eventStream;

  /// 暴露底层 Manager（仅在必要时使用）
  P2PManager get manager => _manager;
}
