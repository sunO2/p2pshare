import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/unified_app_bar.dart';
import '../services/p2p_event_bus.dart' as eb;
import 'chat_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String peerId;

  const DeviceDetailScreen({super.key, required this.peerId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  P2PBridgeNodeInfo? _nodeInfo;
  eb.P2PEventSubscription<eb.P2PEvent>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _loadNodeInfo();
    _listenToStatusChanges();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
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
              addresses: [],
              protocolVersion: '',
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
            addresses: [],
            protocolVersion: '',
          );
        });
      }
    }
  }

  /// 使用 EventBus 监听指定设备的在线状态变化（带状态缓存）
  void _listenToStatusChanges() {
    // 使用 subscribe 方法，它会返回一个可以直接使用的 P2PEventSubscription
    _statusSubscription = eb.P2PEventBus.instance.subscribe(
      peerId: widget.peerId,
      onData: (event) {
        if (!mounted) return;
        debugPrint('[EventBus] Device ${widget.peerId} status changed: ${event.type}');
        // 重新加载节点信息以更新 UI
        _loadNodeInfo();
      },
    );
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
              const UnifiedAppBar(title: '设备详情'),

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Info Card - 可滚动
          Expanded(
            child: SingleChildScrollView(
              child: _buildDeviceInfoCard(),
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons - 固定在底部
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          _buildPeerIdSection(),
          const SizedBox(height: 16),
          _buildAddressesSection(),
          const SizedBox(height: 16),
          _buildProtocolVersionSection(),
          const SizedBox(height: 16),
          _buildLastSeenSection(),
        ],
      ),
    );
  }

  Widget _buildPeerIdSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Peer ID', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: widget.peerId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Peer ID 已复制')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.peerId,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressesSection() {
    final addresses = _nodeInfo?.addresses ?? [];

    if (addresses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('地址', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: addresses.map((addr) => _buildAddressTag(addr)).toList(),
        ),
      ],
    );
  }

  Widget _buildAddressTag(String address) {
    // 解析地址类型
    String label = 'IPv4';
    Color labelColor = const Color(0xFF3D8A5A);

    if (address.startsWith('/ip6')) {
      label = 'IPv6';
      labelColor = const Color(0xFF6C5CE7);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
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
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatAddress(address),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _formatAddress(String address) {
    // 将 /ip4/192.168.1.100/tcp/50001 格式化为 192.168.1.100:50001
    final regex = RegExp(r'^/(ip[46])/([^/]+)/tcp/(\d+)$');
    final match = regex.firstMatch(address);
    if (match != null) {
      final ip = match.group(2)!;
      final port = match.group(3)!;
      return '$ip:$port';
    }
    return address;
  }

  Widget _buildProtocolVersionSection() {
    final protocolVersion = _nodeInfo?.protocolVersion ?? '';

    if (protocolVersion.isEmpty) {
      return const SizedBox.shrink();
    }

    // 使用 / 拆分协议版本，过滤掉空字符串
    final parts = protocolVersion.split('/').where((part) => part.isNotEmpty).toList();

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('协议版本', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: parts.map((part) => _buildProtocolPart(part)).toList(),
        ),
      ],
    );
  }

  Widget _buildProtocolPart(String part) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Text(
        part,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF424242),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLastSeenSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最后活跃', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text('刚刚', style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    final status = _nodeInfo?.status;
    final isOffline = status != null && (status.toLowerCase() == '离线' || status.toLowerCase() == 'offline');

    // 状态颜色
    final Color statusColor;
    final Color backgroundColor;
    final String statusText;

    if (isOffline) {
      statusColor = const Color(0xFFD32F2F);
      backgroundColor = const Color(0xFFFFEBEE);
      statusText = '离线';
    } else if (status != null) {
      switch (status.toLowerCase()) {
        case '在线':
        case 'online':
          statusColor = const Color(0xFF3D8A5A);
          backgroundColor = const Color(0xFFC8F0D8);
          statusText = status;
          break;
        case '忙碌':
        case 'busy':
          statusColor = const Color(0xFFF57C00);
          backgroundColor = const Color(0xFFFFE0B2);
          statusText = status;
          break;
        case '离开':
        case 'away':
          statusColor = const Color(0xFFF9A825);
          backgroundColor = const Color(0xFFFFF9C4);
          statusText = status;
          break;
        default:
          statusColor = const Color(0xFF3D8A5A);
          backgroundColor = const Color(0xFFC8F0D8);
          statusText = status;
          break;
      }
    } else {
      // 默认在线
      statusColor = const Color(0xFF3D8A5A);
      backgroundColor = const Color(0xFFC8F0D8);
      statusText = '在线';
    }

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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: statusColor),
          ),
        ],
      ),
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
