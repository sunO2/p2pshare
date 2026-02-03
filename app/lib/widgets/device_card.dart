import 'package:flutter/material.dart';
import '../bridge/bridge.dart';
import '../core/theme/app_theme.dart';

class DeviceCard extends StatelessWidget {
  final P2PBridgeNodeInfo node;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onChatTap;

  const DeviceCard({
    super.key,
    required this.node,
    this.onTap,
    this.onAvatarTap,
    this.onChatTap,
  });

  Color _getStatusColor(BuildContext context, String? status) {
    final theme = context.customTheme;
    if (status == null) return theme.statusGreen;

    switch (status.toLowerCase()) {
      case '在线':
      case 'online':
        return theme.statusGreen;
      case '离线':
      case 'offline':
        return theme.statusRed;
      case '忙碌':
      case 'busy':
        return theme.statusOrange;
      case '离开':
      case 'away':
        return const Color(0xFFF9A825);
      default:
        return theme.iconColor;
    }
  }

  String _getStatusText(String? status) {
    if (status == null) return '在线';
    final statusStr = status.toLowerCase();
    if (statusStr == 'offline') return '离线';
    return status;
  }

  Color _getStatusBackgroundColor(BuildContext context, String? status) {
    final theme = context.customTheme;
    if (status == null) return theme.statusGreenBg;

    switch (status.toLowerCase()) {
      case '在线':
      case 'online':
        return theme.statusGreenBg;
      case '离线':
      case 'offline':
        return theme.statusRed.withOpacity(0.1);
      case '忙碌':
      case 'busy':
        return theme.statusOrange.withOpacity(0.2);
      case '离开':
      case 'away':
        return const Color(0xFFFFF9C4);
      default:
        return theme.dividerColor.withOpacity(0.3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.customTheme;
    final statusColor = _getStatusColor(context, node.status);
    final statusText = _getStatusText(node.status);
    final statusBackgroundColor = _getStatusBackgroundColor(context, node.status);

    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                // Device Icon - 可点击进入详情
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.iconColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Device Info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 显示昵称（如果有）或设备名称
                      Text(
                        node.nickname ?? node.deviceName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.normal,
                          color: theme.iconColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 状态指示器（和列表头部统一但更小）
                      _buildStatusIndicator(
                        context,
                        statusText,
                        statusColor,
                        statusBackgroundColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Chat Button
                GestureDetector(
                  onTap: onChatTap,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: theme.iconColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建状态指示器（和列表头部统一但更小）
  Widget _buildStatusIndicator(
    BuildContext context,
    String text,
    Color statusColor,
    Color backgroundColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.normal,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}
