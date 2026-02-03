import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/settings_controller.dart';
import '../../../widgets/unified_app_bar.dart';
import '../../../core/theme/app_theme.dart';

/// 设置页面视图
class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

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
        appBar: const UnifiedAppBar(title: '设置', showBackButton: false),
        body: _buildContent(context),
      ),
    );
  }

  /// 构建内容
  Widget _buildContent(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      color: theme.scaffoldBackground,
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          // Profile Card
          _buildProfileCard(context),
          const SizedBox(height: 20),

          // Device Settings
          Text('设备设置', style: context.textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildDeviceSettingsCard(context),
          const SizedBox(height: 20),

          // User Profile Settings
          Text('用户资料', style: context.textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildUserProfileCard(context),
          const SizedBox(height: 20),

          // App Settings
          Text('应用设置', style: context.textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildAppSettingsCard(context),
          const SizedBox(height: 20),

          // Debug Settings
          Text('调试', style: context.textTheme.displaySmall),
          const SizedBox(height: 12),
          _buildDebugCard(context),
        ],
      ),
    );
  }

  /// 构建个人资料卡片
  Widget _buildProfileCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final deviceName = controller.deviceName.value;
      final peerId = controller.localPeerId.value;

      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.statusGreen,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName,
                    style: context.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.shortenPeerId(peerId),
                    style: context.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// 构建设备设置卡片
  Widget _buildDeviceSettingsCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final deviceName = controller.deviceName.value;
      final peerId = controller.localPeerId.value;

      return Container(
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildSettingsRow(
              context,
              '设备名称',
              deviceName,
              onTap: () => _showEditDialog(
                context,
                '设备名称',
                deviceName,
                isDeviceName: true,
              ),
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context,
              'Peer ID',
              controller.shortenPeerId(peerId),
              showArrow: false,
            ),
          ],
        ),
      );
    });
  }

  /// 构建用户资料卡片
  Widget _buildUserProfileCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final nickname = controller.nickname.value;
      final status = controller.status.value;

      return Container(
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildSettingsRow(
              context,
              '昵称',
              nickname,
              onTap: () => _showEditDialog(
                context,
                '昵称',
                nickname == '未设置' ? '' : nickname,
                isNickname: true,
              ),
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context,
              '状态',
              status,
              onTap: () => _showStatusDialog(context),
            ),
          ],
        ),
      );
    });
  }

  /// 构建应用设置卡片
  Widget _buildAppSettingsCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final notifications = controller.notificationsEnabled.value;
      final autoScan = controller.autoScanEnabled.value;

      return Container(
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildToggleRow(
              context,
              '通知',
              notifications,
              onChanged: (value) => controller.toggleNotifications(value),
            ),
            _buildDivider(context),
            _buildToggleRow(
              context,
              '自动扫描设备',
              autoScan,
              onChanged: (value) => controller.toggleAutoScan(value),
            ),
          ],
        ),
      );
    });
  }

  /// 构建调试卡片
  Widget _buildDebugCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final logSize = controller.logFileSize.value;

      return Container(
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildSettingsRow(
              context,
              '日志文件大小',
              controller.formatFileSize(logSize),
              showArrow: false,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context,
              '查看日志',
              '按日期查看日志',
              onTap: controller.showLogs,
            ),
            _buildDivider(context),
            _buildSettingsRow(
              context,
              '清空日志',
              '清空所有日志',
              onTap: controller.clearLogs,
            ),
          ],
        ),
      );
    });
  }

  /// 构建设置行
  Widget _buildSettingsRow(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    final theme = context.customTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(16),
        bottom: Radius.circular(16),
      ),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Text(label, style: context.textTheme.titleLarge),
            const Spacer(),
            Text(
              value,
              style: context.textTheme.bodyLarge?.copyWith(
                color: label == '状态'
                    ? theme.statusGreen
                    : theme.iconColor,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 12),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: theme.iconColorLight,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建开关行
  Widget _buildToggleRow(
    BuildContext context,
    String label,
    bool value, {
    required ValueChanged<bool> onChanged,
  }) {
    final theme = context.customTheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Text(label, style: context.textTheme.titleLarge),
          const Spacer(),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value
                    ? theme.statusGreen
                    : theme.dividerColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(100),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分隔线
  Widget _buildDivider(BuildContext context) {
    final theme = context.customTheme;
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 18),
      color: theme.dividerColor,
    );
  }

  /// 显示编辑对话框
  void _showEditDialog(
    BuildContext context,
    String title,
    String currentValue, {
    bool isDeviceName = false,
    bool isNickname = false,
  }) {
    final textController = TextEditingController(text: currentValue);

    Get.dialog(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: title == '昵称' ? '请输入昵称（可选）' : '请输入$title',
          ),
          maxLength: title == '设备名称' ? 20 : 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newValue = textController.text.trim();
              Get.back();

              if (isDeviceName) {
                await controller.editDeviceName(newValue);
              } else if (isNickname) {
                await controller.editNickname(newValue);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示状态选择对话框
  void _showStatusDialog(BuildContext context) {
    final theme = context.customTheme;
    final statuses = ['在线', '忙碌', '离开', '隐身'];

    Get.dialog(
      AlertDialog(
        backgroundColor: theme.cardBackground,
        title: Text('选择状态', style: TextStyle(color: theme.iconColor)),
        content: Obx(() => Column(
              mainAxisSize: MainAxisSize.min,
              children: statuses.map((status) {
                return ListTile(
                  title: Text(status, style: TextStyle(color: theme.iconColor)),
                  trailing: controller.status.value == status
                      ? Icon(Icons.check, color: theme.statusGreen)
                      : null,
                  onTap: () async {
                    Get.back();
                    await controller.selectStatus(status);
                  },
                );
              }).toList(),
            )),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('取消', style: TextStyle(color: theme.statusGreen)),
          ),
        ],
      ),
    );
  }
}
