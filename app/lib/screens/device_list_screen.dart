import 'dart:async';
import 'package:flutter/material.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/device_card.dart';
import '../services/p2p_event_bus.dart' as eb;
import 'chat_screen.dart';
import 'device_detail_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final List<P2PBridgeNodeInfo> _nodes = [];
  String _searchQuery = '';
  bool _isRefreshing = false;
  eb.P2PEventSubscription<eb.P2PEvent>? _eventBusSubscription;
  StreamSubscription? _p2pManagerSubscription;

  @override
  void initState() {
    super.initState();
    _loadNodes();
    _listenToEvents();
    _listenToEventBus();
  }

  @override
  void dispose() {
    _eventBusSubscription?.cancel();
    _p2pManagerSubscription?.cancel();
    super.dispose();
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
    return Column(
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatScreen(peerId: node.peerId, peerName: node.deviceName),
      ),
    );
  }
}
