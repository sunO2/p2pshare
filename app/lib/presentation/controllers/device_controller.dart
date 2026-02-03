import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../data/providers/p2p_provider.dart';
import '../../services/log_service.dart';
import '../../../p2p_manager.dart';
import '../../../bridge/bridge.dart';
import '../../../services/p2p_event_bus.dart' as eb;

/// 设备列表控制器
///
/// 管理：设备列表、搜索、刷新、服务状态、广播信息
class DeviceController extends GetxController
    with GetTickerProviderStateMixin {
  // ========== 状态变量 ==========

  /// 设备列表
  final nodes = <P2PBridgeNodeInfo>[].obs;

  /// 搜索关键词
  final searchQuery = ''.obs;

  /// 是否正在刷新
  final isRefreshing = false.obs;

  /// 服务状态
  final serviceStatus = RxMap<String, ServiceStatusData>();

  /// 在线设备数量
  final connectedPeers = 0.obs;

  /// 发现的设备数量
  final discoveredPeers = 0.obs;

  /// 是否显示广播信息弹窗
  final showBroadcastInfoPopup = false.obs;

  /// 广播信息
  final Rxn<BroadcastInfoJson> broadcastInfo = Rxn<BroadcastInfoJson>();

  // ========== Keys ==========

  /// Info 按钮占位符 Key
  final infoPlaceholderKey = GlobalKey();

  /// Stack Key
  final stackKey = GlobalKey();

  /// Info 按钮位置
  final Rxn<Offset> infoButtonPosition = Rxn<Offset>();

  // ========== 动画控制器 ==========

  late AnimationController popupAnimationController;
  late Animation<double> scaleAnimation;

  // ========== 订阅 ==========

  eb.P2PEventSubscription<eb.P2PEvent>? eventBusSubscription;
  StreamSubscription? p2pManagerSubscription;

  // ========== 依赖注入 ==========

  final P2PProvider _p2p = Get.find<P2PProvider>();
  final LogService _log = Get.find<LogService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[DeviceController] onInit');

    // 初始化动画控制器
    popupAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: popupAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    // 加载设备列表
    loadNodes();

    // 监听事件
    listenToEvents();
    listenToEventBus();

    // 初始加载服务状态
    loadInitialServiceStatus();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[DeviceController] onReady');
  }

  @override
  void onClose() {
    _log.i('[DeviceController] onClose');
    eventBusSubscription?.cancel();
    p2pManagerSubscription?.cancel();
    popupAnimationController.dispose();
    super.onClose();
  }

  // ========== 数据加载 ==========

  /// 加载设备列表
  void loadNodes() {
    try {
      final nodeList = _p2p.manager.getVerifiedNodes();
      nodes.assignAll(nodeList);
      _updatePeerCounts();
      _log.i('加载设备列表: ${nodeList.length} 个设备');
    } catch (e) {
      _log.e('加载设备列表失败: $e', e);
    }
  }

  /// 更新设备数量统计
  void _updatePeerCounts() {
    connectedPeers.value = nodes.where((n) {
      final status = n.status?.toLowerCase();
      return status != '离线' && status != 'offline';
    }).length;
    discoveredPeers.value = nodes.length;
  }

  /// 初始加载服务状态
  void loadInitialServiceStatus() {
    try {
      final systemStatus = _p2p.manager.getSystemStatus();

      serviceStatus['mDNS'] = ServiceStatusData(
        name: systemStatus.mdnsService.name,
        health: systemStatus.mdnsService.health.name,
        isRunning: systemStatus.mdnsService.isRunning,
        message: systemStatus.mdnsService.message,
      );

      serviceStatus['Connection'] = ServiceStatusData(
        name: systemStatus.connectionService.name,
        health: systemStatus.connectionService.health.name,
        isRunning: systemStatus.connectionService.isRunning,
        message: systemStatus.connectionService.message,
      );

      connectedPeers.value = systemStatus.connectedPeers;
      discoveredPeers.value = systemStatus.discoveredPeers;

      _log.i('服务状态加载完成');
    } catch (e) {
      _log.e('加载服务状态失败: $e', e);
    }
  }

  // ========== 刷新操作 ==========

  /// 刷新设备列表
  Future<void> refreshDevices() async {
    if (isRefreshing.value) return;

    isRefreshing.value = true;

    try {
      // 触发刷新
      await _p2p.manager.triggerRefresh();

      // 等待设备发现
      await Future.delayed(const Duration(milliseconds: 500));

      // 重新加载
      loadNodes();

      Get.snackbar(
        '刷新成功',
        '设备列表已更新',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1),
      );
    } catch (e) {
      _log.e('刷新设备列表失败: $e', e);
      Get.snackbar(
        '刷新失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } finally {
      isRefreshing.value = false;
    }
  }

  // ========== 搜索操作 ==========

  /// 更新搜索关键词
  void updateSearchQuery(String query) {
    searchQuery.value = query;
  }

  /// 过滤后的设备列表
  List<P2PBridgeNodeInfo> get filteredNodes {
    if (searchQuery.value.isEmpty) return nodes;
    return nodes.where((node) {
      return node.deviceName.toLowerCase().contains(searchQuery.value.toLowerCase()) ||
          node.displayName.toLowerCase().contains(searchQuery.value.toLowerCase());
    }).toList();
  }

  // ========== 事件监听 ==========

  /// 监听 P2P 事件流
  void listenToEvents() {
    p2pManagerSubscription = _p2p.eventStream.listen((event) {
      if (event is NodeVerifiedEvent ||
          event is NodeOfflineEvent ||
          event is UserInfoReceivedEvent) {
        loadNodes();
      }

      if (event is ServiceStatusChangedEvent) {
        serviceStatus[event.service] = event.status;
        _updatePeerCounts();
        _log.i('[ServiceStatus] ${event.service}: ${event.status.health}');
      }
    });
  }

  /// 监听事件总线
  void listenToEventBus() {
    eventBusSubscription = eb.P2PEventBus.instance.subscribe(
      type: 'online',
      onData: (event) {
        _log.i('[EventBus] Device online: ${event.peerId}');
        loadNodes();
      },
      errorCallback: (error) {
        _log.e('[EventBus] Error: $error');
      },
    );

    eb.P2PEventBus.instance.onType('offline').listen((event) {
      _log.i('[EventBus] Device offline: ${event.peerId}');
      loadNodes();
    });
  }

  // ========== 导航操作 ==========

  /// 打开设备详情
  void openDeviceDetail(P2PBridgeNodeInfo node) {
    Get.toNamed(
      '/device-detail',
      parameters: {'peerId': node.peerId},
    );
  }

  /// 打开聊天
  void openChat(P2PBridgeNodeInfo node) {
    Get.toNamed(
      '/chat',
      parameters: {
        'peerId': node.peerId,
        'peerName': node.deviceName,
      },
    );
  }

  // ========== 广播信息弹窗 ==========

  /// 切换广播信息弹窗
  Future<void> toggleBroadcastInfoPopup() async {
    // 如果已显示，关闭
    if (showBroadcastInfoPopup.value) {
      await popupAnimationController.reverse();
      showBroadcastInfoPopup.value = false;
      return;
    }

    // 显示弹窗
    try {
      final info = await _p2p.manager.getBroadcastInfo();
      broadcastInfo.value = info;
      showBroadcastInfoPopup.value = true;
      popupAnimationController.forward();
    } catch (e) {
      _log.e('获取广播信息失败: $e', e);
    }
  }

  /// 关闭广播信息弹窗
  Future<void> closeBroadcastInfoPopup() async {
    await popupAnimationController.reverse();
    showBroadcastInfoPopup.value = false;
  }

  // ========== Info 按钮定位 ==========

  /// 计算 info 按钮位置（基于占位符）
  void calculateInfoButtonPosition() {
    final RenderBox? stackBox =
        stackKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? placeholderBox =
        infoPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox == null || placeholderBox == null) {
      return;
    }

    // 获取占位符相对于 Stack 的位置
    final placeholderGlobalPosition = placeholderBox.localToGlobal(Offset.zero);
    final placeholderLocalPosition = stackBox.globalToLocal(placeholderGlobalPosition);

    infoButtonPosition.value = placeholderLocalPosition;
  }
}
