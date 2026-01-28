import 'package:flutter/material.dart';
import '../p2p_manager.dart';
import '../services/log_service.dart';
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
    // 初始化日志服务
    _initLogService();
    _initP2P();
  }

  /// 初始化日志服务
  Future<void> _initLogService() async {
    try {
      await LogService.instance.init();
      debugPrint('日志服务已初始化');
    } catch (e) {
      debugPrint('日志服务初始化失败: $e');
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
  void _syncP2PState() {
    try {
      if (P2PManager.instance.isInitialized) {
        setState(() {
          _isInitialized = true;
          _localPeerId = P2PManager.instance.getLocalPeerId();
          _deviceName = P2PManager.instance.getDeviceName();
          _initError = null;
        });
      }
    } catch (e) {
      debugPrint('同步 P2P 状态失败: $e');
    }
  }

  Future<void> _initP2P() async {
    try {
      debugPrint('开始初始化 P2P...');

      await P2PManager.instance.init('我的设备');
      debugPrint('✓ init 成功，获取节点信息...');

      final localPeerId = P2PManager.instance.getLocalPeerId();
      final deviceName = P2PManager.instance.getDeviceName();

      setState(() {
        _isInitialized = true;
        _localPeerId = localPeerId;
        _deviceName = deviceName;
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
        border: Border(
          top: BorderSide(color: Color(0xFFCCCCCC), width: 1),
        ),
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(icon, size: 18, color: isSelected ? Colors.white : color),
              ),
            ),
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
