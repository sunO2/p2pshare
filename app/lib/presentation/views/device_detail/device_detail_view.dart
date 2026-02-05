import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/device_detail_controller.dart';
import '../../../widgets/unified_app_bar.dart';
import '../../../core/theme/app_theme.dart';

/// 设备详情视图
class DeviceDetailView extends GetView<DeviceDetailController> {
  const DeviceDetailView({super.key});

  @override
  // 使用动态 tag，基于 peerId 生成唯一标识
  String get tag => 'device_detail_${Get.parameters['peerId'] ?? 'unknown'}';

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
              const UnifiedAppBar(title: '设备详情'),

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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Info Card - 可滚动
          Expanded(child: _buildDeviceInfoCard(context)),
          const SizedBox(height: 20),

          // Action Buttons - 固定在底部
          _buildActionButtons(context),
        ],
      ),
    );
  }

  /// 构建设备信息卡片
  Widget _buildDeviceInfoCard(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      // 显示加载状态
      if (controller.isLoading.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.statusGreen),
              ),
              const SizedBox(height: 16),
              Text(
                '加载设备信息...',
                style: TextStyle(color: theme.iconColor),
              ),
            ],
          ),
        );
      }

      final nodeInfo = controller.nodeInfo.value;

      if (nodeInfo == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.statusRed),
              const SizedBox(height: 16),
              Text(
                '设备信息加载失败',
                style: TextStyle(color: theme.iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                '设备可能已离线或不存在',
                style: TextStyle(color: theme.iconColorLight, fontSize: 12),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Info Header
              _buildDeviceHeader(context, nodeInfo),
              const SizedBox(height: 16),

              // Divider
              Container(height: 1, color: theme.dividerColor),
              const SizedBox(height: 16),

              // Device Details
              _buildPeerIdSection(context, nodeInfo),
              const SizedBox(height: 16),
              _buildAddressesSection(context, nodeInfo),
              const SizedBox(height: 16),
              _buildProtocolVersionSection(context, nodeInfo),
              const SizedBox(height: 16),
              _buildLastSeenSection(context),
            ],
          ),
          ),
        ),
      );
    });
  }

  /// 构建设备头部（头像 + 名称 + 状态）
  Widget _buildDeviceHeader(BuildContext context, dynamic nodeInfo) {
    final theme = context.customTheme;
    return Row(
      children: [
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
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nodeInfo?.deviceName ?? 'Unknown',
                style: context.textTheme.displaySmall?.copyWith(
                  color: theme.iconColor,
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusIndicator(context),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建状态指示器
  Widget _buildStatusIndicator(BuildContext context) {
    final theme = context.customTheme;
    return Obx(() {
      final isOnline = controller.isOnline.value;
      final statusText = controller.statusText.value;

      final statusColor = isOnline ? theme.statusGreen : theme.statusRed;
      final backgroundColor = isOnline
          ? theme.statusGreenBg
          : theme.statusRed.withOpacity(0.1);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: context.appTextTheme.labelSmall.copyWith(color: statusColor),
            ),
          ],
        ),
      );
    });
  }

  /// 构建 Peer ID 区域
  Widget _buildPeerIdSection(BuildContext context, dynamic nodeInfo) {
    final theme = context.customTheme;
    final peerId = controller.peerId;
    final shortPeerId = controller.shortenPeerId(peerId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Peer ID',
            style: context.textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPress: controller.copyPeerId,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.searchBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    shortPeerId,
                    style: context.textTheme.bodyMedium?.copyWith(color: theme.iconColor),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.content_copy,
                  size: 16,
                  color: theme.iconColorLight,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建地址区域
  Widget _buildAddressesSection(BuildContext context, dynamic nodeInfo) {
    final theme = context.customTheme;
    final addresses = nodeInfo?.addresses ?? <String>[];

    if (addresses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('地址',
            style: context.textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: addresses.map<Widget>((addr) => _buildAddressTag(context, addr)).toList(),
        ),
      ],
    );
  }

  /// 构建地址标签
  Widget _buildAddressTag(BuildContext context, String address) {
    final theme = context.customTheme;
    final addressType = controller.getAddressType(address);
    final formattedAddress = controller.formatAddress(address);
    final labelColor = Color(
      int.parse(addressType.color.replaceFirst('#', '0xFF')),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.searchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: labelColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              addressType.label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formattedAddress,
            style: context.textTheme.bodySmall?.copyWith(color: theme.iconColor),
          ),
        ],
      ),
    );
  }

  /// 构建协议版本区域
  Widget _buildProtocolVersionSection(BuildContext context, dynamic nodeInfo) {
    final theme = context.customTheme;
    final protocolVersion = nodeInfo?.protocolVersion ?? '';

    if (protocolVersion.isEmpty) {
      return const SizedBox.shrink();
    }

    final parts = controller.parseProtocolVersion(protocolVersion);

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('协议版本',
            style: context.textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: parts.map<Widget>((part) => _buildProtocolPart(context, part)).toList(),
        ),
      ],
    );
  }

  /// 构建协议部分标签
  Widget _buildProtocolPart(BuildContext context, String part) {
    final theme = context.customTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.searchBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(
        part,
        style: context.textTheme.bodySmall?.copyWith(
          color: theme.iconColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建最后活跃区域
  Widget _buildLastSeenSection(BuildContext context) {
    final theme = context.customTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最后活跃',
            style: context.textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 4),
        Obx(() => Text(
              controller.isOnline.value ? '刚刚活跃' : '离线',
              style: context.textTheme.bodyLarge?.copyWith(color: theme.iconColor),
            )),
      ],
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(BuildContext context) {
    final theme = context.customTheme;
    return Column(
      children: [
        // Chat Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: controller.openChat,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.statusGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text('发送消息', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),

        // File Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: controller.showFileTransferNotImplemented,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.statusGreen,
              side: BorderSide(color: theme.statusGreen, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('发送文件', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
