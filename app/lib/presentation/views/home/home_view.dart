import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/home_controller.dart';

/// 首页视图
///
/// 使用 GetView 自动绑定 Controller
class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        body: Obx(() {
          // 显示初始化加载状态
          if (!controller.isInitialized.value) {
            return _buildLoading(context);
          }
          // 显示主界面
          return IndexedStack(
            index: controller.currentIndex.value,
            children: controller.pages,
          );
        }),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  /// 构建加载界面
  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Obx(() {
        if (controller.initError.value == null) {
          // 加载中
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3D8A5A)),
              ),
              const SizedBox(height: 16),
              Text(
                '正在初始化...',
                style: context.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                '正在加载 P2P 模块，请稍候...',
                style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          );
        } else {
          // 初始化失败
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text('初始化失败', style: context.textTheme.titleLarge),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  controller.initError.value!,
                  style: context.textTheme.bodyMedium?.copyWith(color: Colors.red[700]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '请确保:\n'
                '• 设备已授予必要权限\n'
                '• 库文件正确安装\n'
                '• 网络连接正常',
                style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
          );
        }
      }),
    );
  }

  /// 构建底部导航栏
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
          child: Obx(() => Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabItem(0, Icons.devices_outlined, '设备'),
              _buildTabItem(1, Icons.chat_bubble_outline, '聊天'),
              _buildTabItem(2, Icons.folder_outlined, '文件'),
              _buildTabItem(3, Icons.settings_outlined, '设置'),
            ],
          )),
        ),
      ),
    );
  }

  /// 构建单个导航标签
  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = controller.currentIndex.value == index;
    final color = isSelected
        ? const Color(0xFF3D8A5A)
        : const Color(0xFF999999);

    return SizedBox(
      width: 64,
      height: 60,
      child: InkWell(
        onTap: () => controller.changeTab(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
