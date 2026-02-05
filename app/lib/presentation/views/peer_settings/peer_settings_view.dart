import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/peer_settings_controller.dart';
import '../../../widgets/unified_app_bar.dart';
import '../../../core/theme/app_theme.dart';

/// 设备设置视图
class PeerSettingsView extends GetView<PeerSettingsController> {
  const PeerSettingsView({super.key});

  @override
  String get tag => 'peer_settings_${Get.parameters['peerId'] ?? 'unknown'}';

  @override
  Widget build(BuildContext context) {
    final theme = context.customTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: theme.scaffoldBackground,
        statusBarIconBrightness: theme.scaffoldBackground == AppTheme.backgroundDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: theme.scaffoldBackground == AppTheme.backgroundDark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackground,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header
              const UnifiedAppBar(title: '设备设置'),

              // Content
              Expanded(child: _buildContent(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建内容区域
  Widget _buildContent(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      color: theme.scaffoldBackground,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 设备信息卡片
          _buildDeviceInfoCard(context),
          const SizedBox(height: 24),

          // 设置列表
          Expanded(
            child: Obx(() => _buildSettingsList(context)),
          ),

          // 底部按钮
          const SizedBox(height: 16),
          _buildBottomButtons(context),
        ],
      ),
    );
  }

  /// 构建设备信息卡片
  Widget _buildDeviceInfoCard(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.iconColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // 名称和 Peer ID
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.peerName,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: theme.iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _shortenPeerId(controller.peerId),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: theme.iconColorLight,
                  ),
                ),
              ],
            ),
          ),

          // 查看详情按钮
          IconButton(
            icon: Icon(
              Icons.info_outline,
              color: theme.iconColorLight,
            ),
            onPressed: controller.openDeviceDetail,
            tooltip: '查看详情',
          ),
        ],
      ),
    );
  }

  /// 构建设置列表
  Widget _buildSettingsList(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // 文件传输设置
          _buildSectionHeader(context, '文件传输'),
          const SizedBox(height: 8),
          _buildSettingCard(context, [
            _buildSwitchTile(
              context,
              title: '自动接收文件',
              subtitle: '对方发送文件时自动接收',
              icon: Icons.file_download,
              value: controller.config.value.autoReceiveFiles,
              onChanged: controller.toggleAutoReceiveFiles,
            ),
            _buildSwitchTile(
              context,
              title: '自动下载图片',
              subtitle: '自动下载接收到的图片',
              icon: Icons.image,
              value: controller.config.value.autoDownloadImages,
              onChanged: controller.toggleAutoDownloadImages,
            ),
          ]),

          const SizedBox(height: 24),

          // 剪切板设置
          _buildSectionHeader(context, '剪切板'),
          const SizedBox(height: 8),
          _buildSettingCard(context, [
            _buildSwitchTile(
              context,
              title: '自动复制剪切板',
              subtitle: '收到剪切板消息时自动复制',
              icon: Icons.content_copy,
              value: controller.config.value.autoCopyClipboard,
              onChanged: controller.toggleAutoCopyClipboard,
            ),
          ]),

          const SizedBox(height: 24),

          // 通知设置
          _buildSectionHeader(context, '通知'),
          const SizedBox(height: 8),
          _buildSettingCard(context, [
            _buildSwitchTile(
              context,
              title: '启用通知',
              subtitle: '接收消息时显示通知',
              icon: Icons.notifications,
              value: controller.config.value.notificationsEnabled,
              onChanged: controller.toggleNotifications,
            ),
            _buildSwitchTile(
              context,
              title: '消息提示音',
              subtitle: '收到消息时播放提示音',
              icon: Icons.volume_up,
              value: controller.config.value.messageSoundEnabled,
              onChanged: controller.toggleMessageSound,
            ),
            _buildSwitchTile(
              context,
              title: '消息振动',
              subtitle: '收到消息时振动',
              icon: Icons.vibration,
              value: controller.config.value.messageVibrationEnabled,
              onChanged: controller.toggleMessageVibration,
            ),
          ]),
        ],
      ),
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = context.customTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: context.textTheme.labelLarge?.copyWith(
          color: theme.statusGreen,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 构建设置卡片
  Widget _buildSettingCard(BuildContext context, List<Widget> children) {
    final theme = context.customTheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  /// 构建开关设置项
  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final theme = context.customTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: theme.iconColor,
                ),
              ),
              const SizedBox(width: 16),

              // 标题和副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: theme.iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: theme.iconColorLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // 开关
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: theme.statusGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建底部按钮
  Widget _buildBottomButtons(BuildContext context) {
    final theme = context.customTheme;
    return Row(
      children: [
        // 重置按钮
        Expanded(
          child: OutlinedButton(
            onPressed: controller.resetToDefault,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.statusRed,
              side: BorderSide(color: theme.statusRed, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('重置默认', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 16),

        // 保存按钮
        Expanded(
          child: Obx(() => ElevatedButton(
            onPressed: controller.isSaving.value ? null : controller.saveConfig,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.statusGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: theme.statusGreen.withOpacity(0.5),
            ),
            child: controller.isSaving.value
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          )),
        ),
      ],
    );
  }

  /// 缩短 Peer ID 显示
  String _shortenPeerId(String peerId) {
    if (peerId.length > 16) {
      return '${peerId.substring(0, 14)}...';
    }
    return peerId;
  }
}
