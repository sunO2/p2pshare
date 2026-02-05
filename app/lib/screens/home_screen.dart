import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../presentation/controllers/home_controller.dart';

/// 首页视图
///
/// 使用 GetX 架构，通过 GetView 绑定 HomeController
class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听错误状态
    return Obx(() {
      // 错误状态
      if (controller.initError.value != null) {
        return _buildErrorUI(context);
      }

      // 正常状态
      return PopScope(
        canPop: true,
        child: Scaffold(
          body: SafeArea(
            child: IndexedStack(
              index: controller.currentIndex.value,
              children: controller.pages,
            ),
          ),
          bottomNavigationBar: _buildBottomNavigationBar(context),
        ),
      );
    });
  }

  /// 构建 BottomNavigationBar
  Widget _buildBottomNavigationBar(BuildContext context) {
    return Obx(() => NavigationBar(
          height: 65,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedIndex: controller.currentIndex.value,
          onDestinationSelected: (index) {
            controller.changeTab(index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.devices_other),
              label: '设备',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: '对话',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              label: '文件',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ));
  }

  /// 构建错误 UI
  Widget _buildErrorUI(BuildContext context) {
    return Obx(() {
      final error = controller.initError.value;

      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 16),
                Text(
                  '初始化失败',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  error ?? '未知错误',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: controller.retryInit,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D8A5A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
