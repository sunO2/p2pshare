import 'package:flutter/material.dart';
import '../bridge/bridge.dart';

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

  Color _getStatusColor(String? status) {
    if (status == null) return const Color(0xFF3D8A5A); // 默认在线

    switch (status.toLowerCase()) {
      case '在线':
      case 'online':
        return const Color(0xFF3D8A5A);
      case '离线':
      case 'offline':
        return const Color(0xFFD32F2F);
      case '忙碌':
      case 'busy':
        return const Color(0xFFF57C00);
      case '离开':
      case 'away':
        return const Color(0xFFF9A825);
      default:
        return const Color(0xFF6D6C6A);
    }
  }

  String _getStatusText(String? status) {
    if (status == null) return '在线';
    final statusStr = status.toLowerCase();
    if (statusStr == 'offline') return '离线';
    return status;
  }

  Color _getStatusBackgroundColor(String? status) {
    if (status == null) return const Color(0xFFC8F0D8);

    switch (status.toLowerCase()) {
      case '在线':
      case 'online':
        return const Color(0xFFC8F0D8);
      case '离线':
      case 'offline':
        return const Color(0xFFFFEBEE);
      case '忙碌':
      case 'busy':
        return const Color(0xFFFFE0B2);
      case '离开':
      case 'away':
        return const Color(0xFFFFF9C4);
      default:
        return const Color(0xFFE8E8E6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(node.status);
    final statusText = _getStatusText(node.status);
    final statusBackgroundColor = _getStatusBackgroundColor(node.status);

    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCCCCCC)),
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
                      color: const Color(0xFFE8E8E6),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D6C6A),
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.normal,
                          color: Color(0xFF1A1918),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 状态指示器（和列表头部统一但更小）
                      _buildStatusIndicator(statusText, statusColor, statusBackgroundColor),
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
                      color: const Color(0xFFE8E8E6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Color(0xFF6D6C6A),
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
  Widget _buildStatusIndicator(String text, Color statusColor, Color backgroundColor) {
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
