import 'package:flutter/material.dart';
import '../p2p_manager.dart';
import '../bridge/bridge.dart';
import '../widgets/device_card.dart';
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

  @override
  void initState() {
    super.initState();
    _loadNodes();
    _listenToEvents();
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

  void _listenToEvents() {
    P2PManager.instance.eventStream.listen((event) {
      if (!mounted) return;

      if (event is NodeVerifiedEvent ||
          event is NodeOfflineEvent ||
          event is UserInfoReceivedEvent) {
        _loadNodes();
      }
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
              _buildStatusIndicator(_nodes.length),
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
          onTap: () => _openDeviceDetail(node),
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
            ChatScreen(peerId: node.peerId, deviceName: node.deviceName),
      ),
    );
  }
}
