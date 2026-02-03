import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/unified_app_bar.dart';
import '../core/theme/app_theme.dart';
import '../services/p2p_event_bus.dart' as eb;

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
        debugPrint(
          '[EventBus] Device ${widget.peerId} status changed: ${event.type}',
        );
        // 重新加载节点信息以更新 UI
        _loadNodeInfo();
      },
    );
  }

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
    final theme = context.customTheme;
    return Container(
      color: theme.scaffoldBackground,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Info Card - 可滚动
          Expanded(child: SingleChildScrollView(child: _buildDeviceInfoCard())),
          const SizedBox(height: 20),

          // Action Buttons - 固定在底部
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    final theme = context.customTheme;
    final nodeInfo = _nodeInfo;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardBackground,
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
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: theme.iconColor,
                      ),
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
          Container(height: 1, color: theme.dividerColor),
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
    final theme = context.customTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Peer ID', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: widget.peerId));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Peer ID 已复制')));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.searchBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.peerId,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: theme.iconColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressesSection() {
    final theme = context.customTheme;
    final addresses = _nodeInfo?.addresses ?? [];

    if (addresses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('地址', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
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
    final theme = context.customTheme;
    // 解析地址类型
    String label = 'IPv4';
    Color labelColor = theme.statusGreen;

    if (address.startsWith('/ip6')) {
      label = 'IPv6';
      labelColor = const Color(0xFF6C5CE7);
    }

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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.iconColor),
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
    final theme = context.customTheme;
    final protocolVersion = _nodeInfo?.protocolVersion ?? '';

    if (protocolVersion.isEmpty) {
      return const SizedBox.shrink();
    }

    // 使用 / 拆分协议版本，过滤掉空字符串
    final parts = protocolVersion
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('协议版本', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: theme.iconColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLastSeenSection() {
    final theme = context.customTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最后活跃', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.iconColorLight)),
        const SizedBox(height: 4),
        Text('刚刚', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: theme.iconColor)),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    final theme = context.customTheme;
    final status = _nodeInfo?.status;
    final isOffline =
        status != null &&
        (status.toLowerCase() == '离线' || status.toLowerCase() == 'offline');

    // 状态颜色
    final Color statusColor;
    final Color backgroundColor;
    final String statusText;

    if (isOffline) {
      statusColor = theme.statusRed;
      backgroundColor = theme.statusRed.withOpacity(0.1);
      statusText = '离线';
    } else if (status != null) {
      switch (status.toLowerCase()) {
        case '在线':
        case 'online':
          statusColor = theme.statusGreen;
          backgroundColor = theme.statusGreenBg;
          statusText = status;
          break;
        case '忙碌':
        case 'busy':
          statusColor = theme.statusOrange;
          backgroundColor = theme.statusOrange.withOpacity(0.2);
          statusText = status;
          break;
        case '离开':
        case 'away':
          statusColor = const Color(0xFFF9A825);
          backgroundColor = const Color(0xFFFFF9C4);
          statusText = status;
          break;
        default:
          statusColor = theme.statusGreen;
          backgroundColor = theme.statusGreenBg;
          statusText = status;
          break;
      }
    } else {
      // 默认在线
      statusColor = theme.statusGreen;
      backgroundColor = theme.statusGreenBg;
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final theme = context.customTheme;
    return Column(
      children: [
        // Chat Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              Get.toNamed(
                '/chat',
                parameters: {
                  'peerId': widget.peerId,
                  'peerName': _nodeInfo?.deviceName ?? 'Unknown',
                },
              );
            },
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
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('文件传输功能开发中...')));
            },
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
