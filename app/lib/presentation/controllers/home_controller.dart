import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/providers/p2p_provider.dart';
import '../../services/storage_service.dart';
import '../../services/log_service.dart';
import '../../../p2p_manager.dart';
import '../views/devices/device_list_view.dart';
import '../views/conversations/conversation_list_view.dart';
import '../views/settings/settings_view.dart';

/// 首页控制器
///
/// 管理：应用初始化、底部导航、生命周期
class HomeController extends GetxController with WidgetsBindingObserver {
  // ========== 状态变量 ==========

  /// 是否已初始化
  final isInitialized = false.obs;

  /// 本地 Peer ID
  final localPeerId = ''.obs;

  /// 设备名称
  final deviceName = ''.obs;

  /// 当前选中的底部导航索引
  final currentIndex = 0.obs;

  /// 初始化错误信息
  final Rxn<String> initError = Rxn<String>();

  // ========== 依赖注入 ==========

  final P2PProvider _p2p = Get.find<P2PProvider>();
  final LogService _log = Get.find<LogService>();
  final StorageService _storage = Get.find<StorageService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[HomeController] onInit');
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[HomeController] onReady');
  }

  @override
  void onClose() {
    _log.i('[HomeController] onClose');
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.i('[HomeController] 应用生命周期变化: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _onResumed();
        break;
      case AppLifecycleState.paused:
        _log.i('[HomeController] 应用退入后台');
        break;
      case AppLifecycleState.detached:
        _onDetached();
        break;
      default:
        break;
    }
  }

  // ========== 初始化逻辑 ==========

  /// 初始化所有服务和 P2P
  Future<void> _initialize() async {
    try {
      // 1. 获取工作目录
      final workDir = await _getWorkDirectory();
      _log.i('工作目录: $workDir');

      // 2. 初始化服务
      await _initServices(workDir);

      // 3. 初始化 P2P
      await _initP2P(workDir);
    } catch (e, stackTrace) {
      _log.e('初始化异常: $e', e, stackTrace);
      initError.value = '初始化失败：$e';
    }
  }

  /// 初始化服务
  Future<void> _initServices([String? workDir]) async {
    try {
      await _log.init(workDir);
      _log.i('日志服务已初始化');
    } catch (e) {
      _log.e('日志服务初始化失败: $e');
    }

    try {
      await _storage.init();
      _log.i('存储服务已初始化');
    } catch (e) {
      _log.e('存储服务初始化失败: $e');
    }
  }

  /// 初始化 P2P
  Future<void> _initP2P(String workDir) async {
    try {
      _log.i('开始初始化 P2P...');

      // 获取设备名称
      final deviceName = await _storage.getDeviceName();
      _log.i('使用设备名称: $deviceName');

      // 创建配置
      final config = P2PInitConfig(
        deviceName: deviceName,
        workDir: workDir,
      );

      // 初始化
      await _p2p.init(config);
      _log.i('P2P 初始化成功');

      // 启动
      await _p2p.start();
      _log.i('P2P 启动成功');

      // 同步状态
      _syncP2PState();
    } catch (e, stackTrace) {
      _log.e('P2P 初始化异常: $e', e, stackTrace);
      initError.value = '初始化失败：$e';
      rethrow;
    }
  }

  /// 同步 P2P 状态
  Future<void> _syncP2PState() async {
    try {
      if (_p2p.isInitialized.value) {
        final deviceName = await _storage.getDeviceName();
        final localPeerId = await _p2p.manager.getLocalPeerIdAsync();

        isInitialized.value = true;
        this.localPeerId.value = localPeerId;
        this.deviceName.value = deviceName;
        initError.value = null;

        _log.i('同步 P2P 状态: Peer ID = $localPeerId, Device Name = $deviceName');
      }
    } catch (e) {
      _log.e('同步 P2P 状态失败: $e');
    }
  }

  // ========== 应用生命周期处理 ==========

  /// 应用恢复
  Future<void> _onResumed() async {
    _log.i('应用恢复，检查 mDNS 服务状态...');
    await _checkMdnsHealth();
    _syncP2PState();
    _p2p.manager.resumeEventStream();
  }

  /// 应用退出
  void _onDetached() {
    _log.i('应用退出，清理 P2P 资源...');
    _p2p.cleanup();
  }

  /// 检查 mDNS 健康状态
  Future<void> _checkMdnsHealth() async {
    try {
      if (!_p2p.isInitialized.value) {
        _log.w('mDNS 健康检查: P2P 未初始化，跳过');
        return;
      }

      final status = await _p2p.getSystemStatus();
      _log.i('mDNS 健康检查: running=${status.mdnsService.isRunning}, health=${status.mdnsService.health}');

      // 重启 mDNS 浏览服务
      _log.i('从后台恢复，重启 mDNS 浏览服务...');
      await _p2p.manager.restartDiscovery();
      _log.i('mDNS 浏览服务重启完成');
    } catch (e) {
      _log.e('mDNS 健康检查失败: $e');
    }
  }

  // ========== UI 操作 ==========

  /// 切换底部导航
  void changeTab(int index) {
    currentIndex.value = index;
  }

  /// 重试初始化
  Future<void> retryInit() async {
    initError.value = null;
    final workDir = await _getWorkDirectory();
    await _initP2P(workDir);
  }

  // ========== 工具方法 ==========

  /// 获取工作目录
  ///
  /// 优先使用外部存储目录，方便调试和数据访问
  /// 如果外部存储不可用，则使用应用文档目录
  Future<String> _getWorkDirectory() async {
    // 尝试获取外部存储目录
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final workDir = '${externalDir.path}/localp2p';
        _log.i('使用外部存储目录: $workDir');
        return workDir;
      }
    } catch (e) {
      _log.w('无法获取外部存储目录: $e，使用应用文档目录');
    }

    // 回退到应用文档目录
    final appDocDir = await getApplicationDocumentsDirectory();
    final workDir = '${appDocDir.path}/localp2p';
    _log.i('使用应用文档目录: $workDir');
    return workDir;
  }

  // ========== 页面列表 ==========

  /// 子页面列表（用于 IndexedStack）
  /// 注意：不能使用 const，因为 GetView 需要动态绑定 Controller
  List<Widget> get pages => [
    const DeviceListView(),
    const ConversationListView(),
    const _FilePlaceholderScreen(),
    const SettingsView(),
  ];
}

/// 文件占位页面
class _FilePlaceholderScreen extends StatelessWidget {
  const _FilePlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '文件传输功能开发中...',
            style: context.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
