import 'package:flutter/material.dart';
import '../bridge/bridge.dart';

class DeviceCard extends StatelessWidget {
  final P2PBridgeNodeInfo node;
  final VoidCallback? onTap;
  final VoidCallback? onChatTap;

  const DeviceCard({super.key, required this.node, this.onTap, this.onChatTap});

  String _shortenPeerId(String peerId) {
    if (peerId.length > 12) {
      return '${peerId.substring(0, 10)}...';
    }
    return peerId;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case '在线':
      case 'online':
        return const Color(0xFF3D8A5A);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x08000000),
            offset: const Offset(0, 2),
            blurRadius: 12,
          ),
        ],
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
                // Device Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDECEA),
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
                      // 状态信息
                      Row(
                        children: [
                          if (node.status != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                  node.status!,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.status!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.normal,
                                  color: _getStatusColor(node.status!),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${_shortenPeerId(node.peerId)} • 在线',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              color: Color(0xFF9C9B99),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Status Indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3D8A5A),
                    shape: BoxShape.circle,
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
                      color: const Color(0xFFEDECEA),
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
}
