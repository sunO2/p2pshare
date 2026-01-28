import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/unified_app_bar.dart';
import 'chat_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String peerId;

  const DeviceDetailScreen({super.key, required this.peerId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  P2PBridgeNodeInfo? _nodeInfo;

  @override
  void initState() {
    super.initState();
    _loadNodeInfo();
  }

  void _loadNodeInfo() {
    try {
      final nodes = P2PManager.instance.getVerifiedNodes();
      if (mounted) {
        setState(() {
          _nodeInfo = nodes.firstWhere(
            (node) => node.peerId == widget.peerId,
            orElse: () => P2PBridgeNodeInfo(
              peerId: widget.peerId,
              displayName: 'Unknown',
              deviceName: 'Unknown',
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Failed to load node info: $e');
      if (mounted) {
        setState(() {
          _nodeInfo = P2PBridgeNodeInfo(
            peerId: widget.peerId,
            displayName: 'Unknown',
            deviceName: 'Unknown',
          );
        });
      }
    }
  }

  String _shortenPeerId(String peerId) {
    if (peerId.length > 16) {
      return '${peerId.substring(0, 14)}...';
    }
    return peerId;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header - use UnifiedAppBar
              const UnifiedAppBar(
                title: '设备详情',
              ),

              // Content
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      color: const Color(0xFFF8F8F6),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Device Info Card
          _buildDeviceInfoCard(),
          const SizedBox(height: 20),

          // Action Buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    final nodeInfo = _nodeInfo;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Device Info Header
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFEDECEA),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D6C6A),
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
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    _buildStatusIndicator(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Divider
          Container(height: 1, color: const Color(0xFFE5E4E1)),
          const SizedBox(height: 16),

          // Device Details
          _buildDetailRow('Peer ID', _shortenPeerId(widget.peerId)),
          const SizedBox(height: 16),
          _buildDetailRow('地址', '/ip4/192.168.1.100/tcp/50001'),
          const SizedBox(height: 16),
          _buildDetailRow('协议版本', '/localp2p/1.0.0'),
          const SizedBox(height: 16),
          _buildDetailRow('最后活跃', '刚刚'),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFC8F0D8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF3D8A5A),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '在线',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFF3D8A5A)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Chat Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    peerId: widget.peerId,
                    deviceName: _nodeInfo?.deviceName ?? 'Unknown',
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D8A5A),
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
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('文件传输功能开发中...')));
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3D8A5A),
              side: const BorderSide(color: Color(0xFF3D8A5A), width: 2),
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
