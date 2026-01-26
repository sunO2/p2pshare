import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../native/p2p_ffi.dart';
import 'device_list_screen.dart';
import 'chat_screen.dart';
import 'device_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  P2PService? _p2p;
  bool _isInitialized = false;
  String? _localPeerId;
  String? _deviceName;
  int _currentIndex = 0;

  // Tab pages
  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _initP2P();
  }

  Future<void> _initP2P() async {
    try {
      final lib = ffi.DynamicLibrary.open(_getLibraryPath());
      _p2p = P2PService(lib);

      final success = _p2p!.init('我的设备');
      if (success) {
        setState(() {
          _isInitialized = true;
          _localPeerId = _p2p!.getLocalPeerId();
          _deviceName = _p2p!.getDeviceName();
        });

        _p2p!.start();
      }
    } catch (e) {
      debugPrint('Failed to initialize P2P: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  String _getLibraryPath() {
    if (Platform.isAndroid) {
      return 'liblocalp2p_ffi.so';
    } else if (Platform.isLinux) {
      return 'liblocalp2p_ffi.so';
    } else if (Platform.isMacOS) {
      return 'liblocalp2p_ffi.dylib';
    } else if (Platform.isWindows) {
      return 'localp2p_ffi.dll';
    }
    throw Exception('Unsupported platform: ${Platform.operatingSystem}');
  }

  @override
  void dispose() {
    _p2p?.cleanup();
    super.dispose();
  }

  void _onPageTapped(int index, {String? peerId}) {
    setState(() {
      _currentIndex = index;
    });

    // Navigate to specific screens
    if (index == 1 && peerId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            p2p: _p2p!,
            peerId: peerId,
            deviceName: _deviceName ?? 'Unknown',
          ),
        ),
      );
    } else if (index == 2 && peerId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(
            p2p: _p2p!,
            peerId: peerId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D8A5A)),
              ),
              const SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        // Handle back button - exit app on home screen
        return Future.value(true);
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              DeviceListScreen(p2p: _p2p!),
              const ChatPlaceholderScreen(),
              const FilePlaceholderScreen(),
              SettingsScreen(p2p: _p2p!),
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            offset: Offset(0, -1),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 34),
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
    final color = isSelected ? const Color(0xFF3D8A5A) : const Color(0xFFA8A7A5);

    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
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
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '选择一个设备开始聊天',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
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
          Icon(
            Icons.folder_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '文件传输功能开发中...',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
