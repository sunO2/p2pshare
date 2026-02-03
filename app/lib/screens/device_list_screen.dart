import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/device_card.dart';
import '../services/p2p_event_bus.dart' as eb;
import 'device_detail_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen>
    with TickerProviderStateMixin {
  final List<P2PBridgeNodeInfo> _nodes = [];
  String _searchQuery = '';
  bool _isRefreshing = false;
  eb.P2PEventSubscription<eb.P2PEvent>? _eventBusSubscription;
  StreamSubscription? _p2pManagerSubscription;

  // 🔥 服务状态相关（事件推送模式）
  final Map<String, ServiceStatusData> _serviceStatus = {};
  int _connectedPeers = 0;
  int _discoveredPeers = 0;

  // 🔥 广播信息悬浮浮层显示状态
  bool _showBroadcastInfoPopup = false;

  // 🔥 Info 按钮占位符 GlobalKey，用于定位
  final GlobalKey _infoPlaceholderKey = GlobalKey();

  // 🔥 Stack GlobalKey，用于浮层定位
  final GlobalKey _stackKey = GlobalKey();

  // 🔥 Info 按钮位置缓存（避免每帧计算）
  Offset? _infoButtonPosition;
  bool _infoButtonPositionCalculated = false;

  // 🔥 广播信息
  BroadcastInfoJson? _broadcastInfo;

  // 🔥 缩放动画控制器
  late AnimationController _popupAnimationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadNodes();
    _listenToEvents();
    _listenToEventBus();

    // 🔥 初始加载服务状态
    _loadInitialServiceStatus();

    // 🔥 初始化动画控制器
    _popupAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _popupAnimationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    _p2pManagerSubscription?.cancel();
    _popupAnimationController.dispose();
    super.dispose();
  }

  /// 🔥 初始加载服务状态（仅一次，之后通过事件更新）
  void _loadInitialServiceStatus() {
    try {
      final systemStatus = P2PManager.instance.getSystemStatus();
      if (mounted) {
        setState(() {
          // 转换 ServiceStatusJson -> ServiceStatusData
          _serviceStatus['mDNS'] = ServiceStatusData(
            name: systemStatus.mdnsService.name,
            health: systemStatus.mdnsService.health.name,
            isRunning: systemStatus.mdnsService.isRunning,
            message: systemStatus.mdnsService.message,
          );
          _serviceStatus['Connection'] = ServiceStatusData(
            name: systemStatus.connectionService.name,
            health: systemStatus.connectionService.health.name,
            isRunning: systemStatus.connectionService.isRunning,
            message: systemStatus.connectionService.message,
          );
          _connectedPeers = systemStatus.connectedPeers;
          _discoveredPeers = systemStatus.discoveredPeers;
        });
      }
    } catch (e) {
      debugPrint('Failed to load initial service status: $e');
    }
  }

  void _loadNodes() {
    try {
      final nodes = P2PManager.instance.getVerifiedNodes();
      if (mounted) {
        setState(() {
          _nodes.clear();
          _nodes.addAll(nodes);
        });
      }
    } catch (e) {
      debugPrint('Failed to load nodes: $e');
    }
  }

  Future<void> _refreshDevices() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      // 触发主动刷新
      await P2PManager.instance.triggerRefresh();

      // 重新加载设备列表
      await Future.delayed(const Duration(milliseconds: 500));
      _loadNodes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刷新成功'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint('Failed to refresh devices: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _listenToEvents() {
    _p2pManagerSubscription = P2PManager.instance.eventStream.listen((event) {
      if (!mounted) return;

      if (event is NodeVerifiedEvent ||
          event is NodeOfflineEvent ||
          event is UserInfoReceivedEvent) {
        _loadNodes();
      }

      // 🔥 监听服务状态变化事件
      if (event is ServiceStatusChangedEvent) {
        final statusEvent = event;
        setState(() {
          _serviceStatus[statusEvent.service] = statusEvent.status;
          // 更新设备数量统计
          _connectedPeers = _nodes.where((n) {
            final status = n.status?.toLowerCase();
            return status != '离线' && status != 'offline';
          }).length;
          _discoveredPeers = _nodes.length;
        });
        debugPrint(
          '[ServiceStatus] ${statusEvent.service}: ${statusEvent.status.health}',
        );
      }
    });
  }

  /// 使用 EventBus 监听所有设备的在线/离线状态变化（带状态缓存）
  void _listenToEventBus() {
    // 监听所有 online/offline 事件，立即获取当前缓存的最新状态
    _eventBusSubscription = eb.P2PEventBus.instance.subscribe(
      type: 'online',
      onData: (event) {
        if (!mounted) return;
        debugPrint('[EventBus] Device online: ${event.peerId}');
        _loadNodes();
      },
      errorCallback: (error) {
        debugPrint('[EventBus] Error: $error');
      },
    );

    // 同时监听 offline 事件
    eb.P2PEventBus.instance.onType('offline').listen((event) {
      if (!mounted) return;
      debugPrint('[EventBus] Device offline: ${event.peerId}');
      _loadNodes();
    });
  }

  List<P2PBridgeNodeInfo> get _filteredNodes {
    if (_searchQuery.isEmpty) return _nodes;
    return _nodes
        .where(
          (node) =>
              node.deviceName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              node.displayName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // 首次布局后计算 info 按钮位置
    if (!_infoButtonPositionCalculated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateInfoButtonPosition();
      });
    }

    return Stack(
      key: _stackKey,
      children: [
        // 主内容
        Column(
          children: [
            // Header Section
            _buildHeaderSection(),

            // Content
            Expanded(
              child: _filteredNodes.isEmpty
                  ? _buildEmptyState()
                  : _buildDeviceList(),
            ),
          ],
        ),
        // 🔥 广播信息悬浮浮层
        if (_showBroadcastInfoPopup) _buildBroadcastInfoPopup(context),
        // 🔥 Info 按钮（Positioned 放在 Stack 末尾，z-index 最高）
        if (_infoButtonPosition != null) _buildPositionedInfoButton(),
      ],
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Top Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('我的设备', style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(height: 4),
                  Text(
                    '发现 ${_nodes.length} 个设备',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      // Navigate to settings
                      // Already on home, just switch tab
                    },
                    child: const Icon(
                      Icons.settings_outlined,
                      size: 20,
                      color: Color(0xFF6D6C6A),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 🔥 服务状态显示
          _buildServiceStatusSection(),
          const SizedBox(height: 16),

          // Search Bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCCCCC)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    decoration: const InputDecoration(
                      hintText: '搜索设备...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF9C9B99),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('在线设备', style: Theme.of(context).textTheme.displaySmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusIndicator(_nodes.length),
                  const SizedBox(width: 12),
                  // 刷新按钮
                  InkWell(
                    onTap: _isRefreshing ? null : _refreshDevices,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _isRefreshing
                            ? Colors.grey[300]
                            : const Color(0xFFC8F0D8).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isRefreshing
                              ? Colors.grey[400]!
                              : const Color(0xFF3D8A5A).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 16,
                            color: _isRefreshing
                                ? Colors.grey[500]
                                : const Color(0xFF3D8A5A),
                          ),
                          if (_isRefreshing) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.grey[500]!,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(int count) {
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '正在扫描局域网内的设备...' : '未找到匹配的设备',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredNodes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final node = _filteredNodes[index];
        return DeviceCard(
          node: node,
          onTap: () => _openChat(node),
          onAvatarTap: () => _openDeviceDetail(node),
          onChatTap: () => _openChat(node),
        );
      },
    );
  }

  void _openDeviceDetail(P2PBridgeNodeInfo node) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(peerId: node.peerId),
      ),
    );
  }

  void _openChat(P2PBridgeNodeInfo node) {
    Get.toNamed(
      '/chat',
      parameters: {
        'peerId': node.peerId,
        'peerName': node.deviceName,
      },
    );
  }

  /// 🔥 构建服务状态显示组件
  Widget _buildServiceStatusSection() {
    if (_serviceStatus.isEmpty) {
      return const SizedBox.shrink();
    }

    final mdnsStatus = _serviceStatus['mDNS'];
    final connectionStatus = _serviceStatus['Connection'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_ethernet, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                '服务状态',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              // 🔥 Info 按钮占位符（用于定位）
              SizedBox(
                key: _infoPlaceholderKey,
                width: 28,
                height: 28,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 服务状态卡片
          Row(
            children: [
              if (mdnsStatus != null)
                Expanded(
                  child: _buildServiceStatusCard(
                    title: 'mDNS',
                    status: mdnsStatus,
                  ),
                ),
              if (mdnsStatus != null && connectionStatus != null)
                const SizedBox(width: 12),
              if (connectionStatus != null)
                Expanded(
                  child: _buildServiceStatusCard(
                    title: '连接',
                    status: connectionStatus,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 🔥 构建单个服务状态卡片
  Widget _buildServiceStatusCard({
    required String title,
    required ServiceStatusData status,
  }) {
    // 根据健康状态选择颜色
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (!status.isRunning) {
      statusColor = const Color(0xFFD32F2F); // Red
      statusText = '未运行';
      statusIcon = Icons.error_outline;
    } else {
      switch (status.health) {
        case 'healthy':
          statusColor = const Color(0xFF3D8A5A); // Green
          statusText = '正常';
          statusIcon = Icons.check_circle_outline;
          break;
        case 'degraded':
          statusColor = const Color(0xFFF57C00); // Orange
          statusText = '降级';
          statusIcon = Icons.warning_outlined;
          break;
        case 'unhealthy':
          statusColor = const Color(0xFFD32F2F); // Red
          statusText = '异常';
          statusIcon = Icons.error_outline;
          break;
        default:
          statusColor = const Color(0xFF9E9E9E); // Grey
          statusText = '未知';
          statusIcon = Icons.help_outline;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (status.message != null) ...[
            const SizedBox(height: 2),
            Text(
              status.message!,
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// 🔥 构建广播信息悬浮浮层（无蒙层，从按钮缩放展开）
  Widget _buildBroadcastInfoPopup(BuildContext context) {
    // 如果没有广播信息，显示加载中
    if (_broadcastInfo == null) {
      return const Positioned(child: SizedBox.shrink());
    }

    // 获取 Stack 和占位符的 RenderBox
    final RenderBox? stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? placeholderBox =
        _infoPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox == null || placeholderBox == null) {
      return const Positioned(child: SizedBox.shrink());
    }

    // 获取占位符相对于 Stack 的位置（使用 globalToLocal 转换）
    final placeholderGlobalPosition = placeholderBox.localToGlobal(Offset.zero);
    final placeholderLocalPosition = stackBox.globalToLocal(placeholderGlobalPosition);
    final placeholderSize = placeholderBox.size;

    final info = _broadcastInfo!;
    const popupWidth = 320.0;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Positioned(
          // 🔥 位置：往右 16，往上 16
          left: placeholderLocalPosition.dx + placeholderSize.width - popupWidth + 16,
          top: placeholderLocalPosition.dy - 16,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                  width: popupWidth,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏
                      Row(
                        children: [
                          Icon(Icons.wifi_tethering,
                              color: const Color(0xFF3D8A5A), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            '广播信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Peer ID
                      _buildInfoRow(
                        icon: Icons.fingerprint,
                        label: 'Peer ID',
                        value: info.peerId,
                        isLast: false,
                      ),
                      const SizedBox(height: 12),
                      // 设备名称
                      _buildInfoRow(
                        icon: Icons.router,
                        label: '设备名称',
                        value: info.deviceName,
                        isLast: false,
                      ),
                      const SizedBox(height: 12),
                      // 🔥 端口信息（区分 IPv4 和 IPv6）
                      _buildPortsSection(info.addresses),
                      const SizedBox(height: 12),
                      // 🔥 IP 地址列表（区分 IPv4 和 IPv6，支持换行）
                      _buildIPsSection(info.addresses),
                      const SizedBox(height: 12),
                      // 提示信息
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3D8A5A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: const Color(0xFF3D8A5A)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'mDNS 广播用于发现同一网络中的其他设备',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF3D8A5A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ),
        );
      },
    );
  }

  /// 🔥 从地址列表中提取端口信息
  ///
  /// 地址格式示例：
  /// - IPv4: /ip4/192.168.1.100/tcp/12345
  /// - IPv6: /ip6/::1/tcp/23456
  ///
  /// 返回: (IPv4 端口列表, IPv6 端口列表)
  static (List<int>, List<int>) _extractPorts(List<String> addresses) {
    final ipv4Ports = <int>[];
    final ipv6Ports = <int>[];

    for (final addr in addresses) {
      // 解析 multiaddr 格式: /ip4/xxx/tcp/port 或 /ip6/xxx/tcp/port
      final parts = addr.split('/');
      if (parts.length >= 5) {
        final protocol = parts[1]; // ip4 或 ip6
        final transport = parts[3]; // tcp 或 udp
        final portStr = parts[4]; // 端口号

        if (transport == 'tcp') {
          final port = int.tryParse(portStr);
          if (port != null && port > 0) {
            if (protocol == 'ip4') {
              if (!ipv4Ports.contains(port)) {
                ipv4Ports.add(port);
              }
            } else if (protocol == 'ip6') {
              if (!ipv6Ports.contains(port)) {
                ipv6Ports.add(port);
              }
            }
          }
        }
      }
    }

    // 排序以便显示
    ipv4Ports.sort();
    ipv6Ports.sort();

    return (ipv4Ports, ipv6Ports);
  }

  /// 🔥 构建端口信息区域（区分 IPv4 和 IPv6）
  Widget _buildPortsSection(List<String> addresses) {
    final (ipv4Ports, ipv6Ports) = _extractPorts(addresses);

    // 如果都没有端口，显示未知
    if (ipv4Ports.isEmpty && ipv6Ports.isEmpty) {
      return _buildInfoRow(
        icon: Icons.settings_ethernet,
        label: '监听端口',
        value: '未知',
        isLast: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 端口标题行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D8A5A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.settings_ethernet, size: 16, color: Color(0xFF3D8A5A)),
            ),
            const SizedBox(width: 12),
            Text(
              '监听端口',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // IPv4 端口
        if (ipv4Ports.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Text(
                    'IPv4',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ipv4Ports.map((p) => p.toString()).join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (ipv6Ports.isNotEmpty) const SizedBox(height: 4),
        ],
        // IPv6 端口
        if (ipv6Ports.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'IPv6',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ipv6Ports.map((p) => p.toString()).join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 🔥 构建信息行
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF3D8A5A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF3D8A5A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 🔥 从地址列表中提取 IP 地址
  ///
  /// 地址格式示例：
  /// - IPv4: /ip4/192.168.1.100/tcp/12345
  /// - IPv6: /ip6/::1/tcp/23456 或 /ip6/fe80::1/tcp/23456
  ///
  /// 返回: (IPv4 地址列表, IPv6 地址列表)
  static (List<String>, List<String>) _extractIPs(List<String> addresses) {
    final ipv4Addresses = <String>[];
    final ipv6Addresses = <String>[];

    for (final addr in addresses) {
      // 解析 multiaddr 格式: /ip4/xxx/tcp/port 或 /ip6/xxx/tcp/port
      final parts = addr.split('/');
      if (parts.length >= 2) {
        final protocol = parts[1]; // ip4 或 ip6

        if (protocol == 'ip4' && parts.length > 2) {
          final ip = parts[2];
          if (ip.isNotEmpty && !ipv4Addresses.contains(ip)) {
            ipv4Addresses.add(ip);
          }
        } else if (protocol == 'ip6' && parts.length > 2) {
          final ip = parts[2];
          if (ip.isNotEmpty && !ipv6Addresses.contains(ip)) {
            ipv6Addresses.add(ip);
          }
        }
      }
    }

    // 排序以便显示
    ipv4Addresses.sort();
    ipv6Addresses.sort();

    return (ipv4Addresses, ipv6Addresses);
  }

  /// 🔥 构建 IP 地址信息区域（区分 IPv4 和 IPv6，支持换行）
  Widget _buildIPsSection(List<String> addresses) {
    final (ipv4Addresses, ipv6Addresses) = _extractIPs(addresses);

    // 如果都没有 IP 地址，显示未知
    if (ipv4Addresses.isEmpty && ipv6Addresses.isEmpty) {
      return _buildInfoRow(
        icon: Icons.router,
        label: 'IP 地址',
        value: '未知',
        isLast: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // IP 地址标题行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D8A5A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.router, size: 16, color: Color(0xFF3D8A5A)),
            ),
            const SizedBox(width: 12),
            Text(
              'IP 地址',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // IPv4 地址
        if (ipv4Addresses.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ipv4Addresses.map((ip) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Text(
                        'IPv4',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          if (ipv6Addresses.isNotEmpty) const SizedBox(height: 4),
        ],
        // IPv6 地址（支持换行）
        if (ipv6Addresses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ipv6Addresses.map((ip) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.purple.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'IPv6',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ip,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// 🔥 计算 info 按钮位置（基于占位符）
  void _calculateInfoButtonPosition() {
    final RenderBox? stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? placeholderBox =
        _infoPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox == null || placeholderBox == null) {
      return;
    }

    // 获取占位符相对于 Stack 的位置
    final placeholderGlobalPosition = placeholderBox.localToGlobal(Offset.zero);
    final placeholderLocalPosition = stackBox.globalToLocal(placeholderGlobalPosition);

    if (mounted) {
      setState(() {
        _infoButtonPosition = placeholderLocalPosition;
        _infoButtonPositionCalculated = true;
      });
    }
  }

  /// 🔥 构建 Positioned 的 Info 按钮（z-index 最高）
  Widget _buildPositionedInfoButton() {
    if (_infoButtonPosition == null) {
      return const Positioned(child: SizedBox.shrink());
    }

    return Positioned(
      left: _infoButtonPosition!.dx,
      top: _infoButtonPosition!.dy,
      child: InkWell(
        onTap: () async {
          // 获取广播信息（异步调用，避免阻塞 UI）
          try {
            final info = await P2PManager.instance.getBroadcastInfo();

            // 如果浮层已显示，播放关闭动画
            if (_showBroadcastInfoPopup) {
              await _popupAnimationController.reverse();
              if (mounted) {
                setState(() {
                  _showBroadcastInfoPopup = false;
                });
              }
              return;
            }

            // 显示浮层并播放打开动画
            setState(() {
              _broadcastInfo = info;
              _showBroadcastInfoPopup = true;
            });
            _popupAnimationController.forward();
          } catch (e) {
            debugPrint('Failed to get broadcast info: $e');
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 28,
          height: 28,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
