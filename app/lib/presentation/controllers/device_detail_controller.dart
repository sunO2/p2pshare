import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../services/p2p_event_bus.dart' as eb;
import '../../../services/log_service.dart';
import '../../../p2p_manager.dart';
import '../../../bridge/bridge.dart';

/// 设备详情控制器
///
/// 负责：设备信息加载、状态监听、复制操作
class DeviceDetailController extends GetxController {
  // ========== 参数 ==========

  /// 对方 Peer ID（从路由参数获取）
  final String peerId = Get.parameters['peerId'] ?? '';

  // ========== 状态变量 ==========

  /// 设备节点信息
  final Rxn<P2PBridgeNodeInfo> nodeInfo = Rxn<P2PBridgeNodeInfo>();

  /// 是否正在加载
  final isLoading = true.obs;

  /// 是否在线
  final isOnline = true.obs;

  /// 状态文本
  final statusText = '在线'.obs;

  // ========== 订阅 ==========

  eb.P2PEventSubscription<eb.P2PEvent>? statusSubscription;

  // ========== 依赖注入 ==========

  final LogService _log = Get.find<LogService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[DeviceDetailController] onInit - peerId: $peerId');

    if (peerId.isEmpty) {
      _log.e('[DeviceDetailController] Peer ID 为空');
      Get.back();
      return;
    }

    loadNodeInfo();
    listenToStatusChanges();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[DeviceDetailController] onReady');
  }

  @override
  void onClose() {
    _log.i('[DeviceDetailController] onClose');
    statusSubscription?.cancel();
    super.onClose();
  }

  // ========== 数据加载 ==========

  /// 加载节点信息
  void loadNodeInfo() {
    try {
      _log.d('[DeviceDetailController] 加载节点信息: $peerId');

      // 方法1: 从已验证节点列表获取
      final nodes = P2PManager.instance.getVerifiedNodes();
      _log.d('[DeviceDetailController] 已验证节点数量: ${nodes.length}');

      // 查找匹配的节点
      P2PBridgeNodeInfo? foundNode;
      try {
        foundNode = nodes.firstWhere(
          (n) => n.peerId == peerId,
        );
      } catch (e) {
        _log.w('[DeviceDetailController] 未找到匹配的节点: $peerId');
        foundNode = null;
      }

      // 方法2: 如果没找到，尝试从 EventBus 缓存获取最新数据
      if (foundNode == null) {
        _log.d('[DeviceDetailController] 尝试从 EventBus 缓存获取');
        final currentData = eb.P2PEventBus.instance.getCurrentData(peerId);
        if (currentData != null && currentData.isNotEmpty) {
          _log.d('[DeviceDetailController] EventBus 缓存数据: $currentData');
          // 从 EventBus 数据构造节点信息
          foundNode = _createNodeInfoFromEventBus(currentData);
        }
      }

      if (foundNode != null) {
        nodeInfo.value = foundNode;
        _updateOnlineStatus(foundNode.status);
        _log.d('[DeviceDetailController] 节点信息加载成功: ${foundNode.deviceName}, 地址数量: ${foundNode.addresses.length}');
      } else {
        // 创建空节点
        final unknownNode = _createUnknownNodeInfo();
        nodeInfo.value = unknownNode;
        _log.w('[DeviceDetailController] 使用未知节点信息');
      }
    } catch (e, stackTrace) {
      _log.e('[DeviceDetailController] 加载节点信息失败: $e', e, stackTrace);
      nodeInfo.value = _createUnknownNodeInfo();
    } finally {
      isLoading.value = false;
    }
  }

  /// 从 EventBus 数据创建节点信息
  P2PBridgeNodeInfo _createNodeInfoFromEventBus(Map<String, dynamic> data) {
    // 尝试从 EventBus 数据中提取信息
    final deviceName = data['deviceName']?.toString() ?? 'Unknown';
    final displayName = data['displayName']?.toString() ?? deviceName;
    final nickname = data['nickname']?.toString();
    final status = data['status']?.toString();
    final avatarUrl = data['avatarUrl']?.toString();

    // 地址需要从其他地方获取，暂时为空
    final addresses = <String>[];

    return P2PBridgeNodeInfo(
      peerId: peerId,
      displayName: displayName,
      deviceName: deviceName,
      nickname: nickname,
      status: status,
      avatarUrl: avatarUrl,
      addresses: addresses,
      protocolVersion: '',
    );
  }

  /// 创建未知节点信息
  P2PBridgeNodeInfo _createUnknownNodeInfo() {
    return P2PBridgeNodeInfo(
      peerId: peerId,
      displayName: 'Unknown',
      deviceName: 'Unknown',
      addresses: [],
      protocolVersion: '',
    );
  }

  /// 更新在线状态
  void _updateOnlineStatus(String? status) {
    if (status == null || status.isEmpty) {
      isOnline.value = true;
      statusText.value = '在线';
      return;
    }

    final statusLower = status.toLowerCase();
    isOnline.value = statusLower != '离线' && statusLower != 'offline';
    statusText.value = status;
  }

  // ========== 事件监听 ==========

  /// 监听状态变化
  void listenToStatusChanges() {
    statusSubscription = eb.P2PEventBus.instance.subscribe(
      peerId: peerId,
      onData: (event) {
        _log.d('[DeviceDetailController] 状态变化: ${event.type}');
        // 重新加载节点信息
        loadNodeInfo();
      },
    );
  }

  // ========== UI 操作 ==========

  /// 复制 Peer ID 到剪贴板
  void copyPeerId() {
    Clipboard.setData(ClipboardData(text: peerId));
    Get.snackbar(
      '已复制',
      'Peer ID 已复制到剪贴板',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
    _log.d('[DeviceDetailController] Peer ID 已复制');
  }

  /// 跳转到聊天页面
  void openChat() {
    final deviceName = nodeInfo.value?.deviceName ?? 'Unknown';
    Get.toNamed(
      '/chat',
      parameters: {
        'peerId': peerId,
        'peerName': deviceName,
      },
    );
    _log.d('[DeviceDetailController] 打开聊天: $peerId');
  }

  /// 显示发送文件功能（暂未实现）
  void showFileTransferNotImplemented() {
    Get.snackbar(
      '提示',
      '文件传输功能开发中...',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  // ========== 工具方法 ==========

  /// 格式化地址
  ///
  /// 将 /ip4/192.168.1.100/tcp/50001 格式化为 192.168.1.100:50001
  String formatAddress(String address) {
    final regex = RegExp(r'^/(ip[46])/([^/]+)/tcp/(\d+)$');
    final match = regex.firstMatch(address);
    if (match != null) {
      final ip = match.group(2)!;
      final port = match.group(3)!;
      return '$ip:$port';
    }
    return address;
  }

  /// 获取地址类型标签
  AddressType getAddressType(String address) {
    if (address.startsWith('/ip6')) {
      return AddressType.ipv6;
    }
    return AddressType.ipv4;
  }

  /// 解析协议版本
  List<String> parseProtocolVersion(String protocolVersion) {
    if (protocolVersion.isEmpty) return [];
    return protocolVersion
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
  }

  /// 缩短 Peer ID 显示
  String shortenPeerId(String peerId) {
    if (peerId.length > 16) {
      return '${peerId.substring(0, 14)}...';
    }
    return peerId;
  }
}

/// 地址类型枚举
enum AddressType {
  ipv4,
  ipv6,
}

/// 地址类型扩展
extension AddressTypeExtension on AddressType {
  String get label {
    switch (this) {
      case AddressType.ipv4:
        return 'IPv4';
      case AddressType.ipv6:
        return 'IPv6';
    }
  }

  String get color {
    switch (this) {
      case AddressType.ipv4:
        return '#3D8A5A'; // statusGreen
      case AddressType.ipv6:
        return '#6C5CE7'; // purple
    }
  }
}
