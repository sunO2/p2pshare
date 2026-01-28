import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../p2p_manager.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import 'device_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isInitialized = false;
  String? _localPeerId;
  String? _deviceName;
  int _currentIndex = 0;
  String? _initError;

  @override
  void initState() {
    super.initState();
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);
    // 初始化服务和 P2P
    _initialize();
  }

  /// 初始化所有服务和 P2P
  Future<void> _initialize() async {
    // 先初始化存储服务（必须在 P2P 之前完成）
    await _initServices();
    // 再初始化 P2P
    await _initP2P();
  }

  /// 初始化所有服务
  Future<void> _initServices() async {
    try {
      await LogService.instance.init();
      debugPrint('日志服务已初始化');
    } catch (e) {
      debugPrint('日志服务初始化失败: $e');
    }

    try {
      await StorageService.instance.init();
      debugPrint('存储服务已初始化');
    } catch (e) {
      debugPrint('存储服务初始化失败: $e');
    }
  }

  @override
  void dispose() {
    // 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 不再清理 P2P，保持后台运行
    // P2P 服务将在应用真正退出时（detached）清理
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('应用生命周期变化: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // 应用恢复 - 确保 UI 同步状态
        debugPrint('应用恢复，检查 P2P 状态...');
        _syncP2PState();
        break;
      case AppLifecycleState.detached:
        // 应用真正退出时才清理
        debugPrint('应用退出，清理 P2P 资源...');
        P2PManager.instance.cleanup();
        break;
      default:
        // 其他状态不做处理
        // paused: 应用退入后台，保持 P2P 运行以接收消息
        // inactive: 应用切换中，保持状态
        break;
    }
  }

  /// 同步 P2P 状态
  Future<void> _syncP2PState() async {
    try {
      if (P2PManager.instance.isInitialized) {
        // 从存储服务获取设备名称（确保使用正确的设备名称）
        final deviceName = await StorageService.instance.getDeviceName();
        final localPeerId = P2PManager.instance.getLocalPeerId();

        setState(() {
          _isInitialized = true;
          _localPeerId = localPeerId;
          _deviceName = deviceName;
          _initError = null;
        });

        debugPrint('同步 P2P 状态: Peer ID = $_localPeerId, Device Name = $_deviceName');
      }
    } catch (e) {
      debugPrint('同步 P2P 状态失败: $e');
    }
  }

  Future<void> _initP2P() async {
    try {
      debugPrint('开始初始化 P2P...');

      // 获取存储的设备名称（首次会自动生成随机名称）
      final deviceName = await StorageService.instance.getDeviceName();
      debugPrint('使用设备名称: $deviceName');

      // 获取应用文档目录，用于保存密钥对
      final appDocDir = await getApplicationDocumentsDirectory();
      final identityPath = '${appDocDir.path}/identity.key';
      debugPrint('密钥文件路径: $identityPath');

      // 创建 P2P 配置
      final config = P2PInitConfig(
        deviceName: deviceName,
        identityPath: identityPath,
        // 可选：自定义配置
        // listenAddresses: ['/ip4/0.0.0.0/tcp/0'],
        // protocolVersion: '/localp2p/1.0.0',
        // heartbeatIntervalSecs: 10,
        // maxFailures: 3,
      );

      await P2PManager.instance.init(config);
      debugPrint('✓ init 成功，获取节点信息...');

      final localPeerId = P2PManager.instance.getLocalPeerId();
      final storedDeviceName = P2PManager.instance.getDeviceName();

      setState(() {
        _isInitialized = true;
        _localPeerId = localPeerId;
        _deviceName = storedDeviceName;
        _initError = null;
      });

      debugPrint('✓ Peer ID: $_localPeerId');
      debugPrint('✓ Device Name: $_deviceName');
      debugPrint('开始调用 start...');
      await P2PManager.instance.start();
      debugPrint('✓ start 调用完成');
    } catch (e, stackTrace) {
      debugPrint('✗ 初始化异常: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _initError = '初始化失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_initError == null) ...[
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF3D8A5A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '正在初始化...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '正在加载 P2P 模块，请稍候...',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ] else ...[
                  Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  Text('初始化失败', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      _initError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '请确保:\n'
                    '• 设备已授予必要权限\n'
                    '• 库文件正确安装\n'
                    '• 网络连接正常',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _initError = null;
                      });
                      _initP2P();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D8A5A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              const DeviceListScreen(),
              const ChatPlaceholderScreen(),
              const FilePlaceholderScreen(),
              const SettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        border: Border(top: BorderSide(color: Color(0xFFCCCCCC), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabItem(0, Icons.devices_outlined, '设备'),
              _buildTabItem(1, Icons.chat_bubble_outline, '聊天'),
              _buildTabItem(2, Icons.folder_outlined, '文件'),
              _buildTabItem(3, Icons.settings_outlined, '设置'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? const Color(0xFF3D8A5A)
        : const Color(0xFF999999);

    return SizedBox(
      width: 64,
      height: 60,
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 选中时显示圆形背景，未选中时直接显示图标
            if (isSelected)
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFF3D8A5A),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(icon, size: 18, color: Colors.white)),
              )
            else
              Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

// Placeholder screens for non-implemented tabs
class ChatPlaceholderScreen extends StatelessWidget {
  const ChatPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '选择一个设备开始聊天',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class FilePlaceholderScreen extends StatelessWidget {
  const FilePlaceholderScreen({super.key});

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
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
