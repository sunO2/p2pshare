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

  /// 弹出框 Key（用于获取实际尺寸）
  final popupKey = GlobalKey();

  /// Info 按钮位置
  final Rxn<Offset> infoButtonPosition = Rxn<Offset>();

  /// 动画缩放原点（基于弹出框实际尺寸动态计算）
  final Rxn<FractionalOffset> popupScaleAlignment = Rxn<FractionalOffset>();

  // ========== 动画控制器 ==========

  late AnimationController popupAnimationController;
  late Animation<double> scaleAnimation;

  // ========== 订阅 ==========

  eb.P2PEventSubscription<eb.P2PEvent>? eventBusSubscription;
  eb.P2PEventSubscription<eb.P2PEvent>? serviceReadySubscription;
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

    // 监听服务启动完成事件
    listenToServiceReady();

    // 监听其他事件
    listenToEvents();
    listenToEventBus();
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
    serviceReadySubscription?.cancel();
    p2pManagerSubscription?.cancel();
    popupAnimationController.dispose();
    super.onClose();
  }

  // ========== 服务监听 ==========

  /// 监听服务启动完成事件
  void listenToServiceReady() {
    _log.i('[DeviceController] 开始监听服务启动完成事件');
    serviceReadySubscription = eb.P2PEventBus.instance.subscribe(
      peerId: '_system_',
      type: 'service_ready',
      onData: (event) {
        _log.i('[DeviceController] 收到服务启动完成事件');
        // 服务启动完成后再加载数据
        loadNodes();
        loadInitialServiceStatus();
      },
      errorCallback: (error) {
        _log.e('[DeviceController] 服务监听错误: $error');
      },
    );
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

      _log.i('[服务状态初始化] mDNS: ${systemStatus.mdnsService.health.name} (running: ${systemStatus.mdnsService.isRunning})');
      _log.i('[服务状态初始化] Connection: ${systemStatus.connectionService.health.name} (running: ${systemStatus.connectionService.isRunning})');
      _log.i('[服务状态初始化] connectedPeers: ${systemStatus.connectedPeers}, discoveredPeers: ${systemStatus.discoveredPeers}');

      // ⚠️ 注意：mDNS 状态由 Flutter 端通过 ServiceStatusChangedEvent 单独管理
      // 不在这里覆盖，避免与 Flutter mDNS 服务状态冲突
      // 如果 mDNS 状态还没有初始化，设置一个默认的"等待启动"状态
      if (!serviceStatus.containsKey('mDNS')) {
        serviceStatus['mDNS'] = ServiceStatusData(
          name: 'mDNS',
          health: 'unhealthy',
          isRunning: false,
          message: '等待启动...',
        );
      }

      serviceStatus['Connection'] = ServiceStatusData(
        name: systemStatus.connectionService.name,
        health: systemStatus.connectionService.health.name,
        isRunning: systemStatus.connectionService.isRunning,
        message: systemStatus.connectionService.message,
      );

      connectedPeers.value = systemStatus.connectedPeers;
      discoveredPeers.value = systemStatus.discoveredPeers;

      _log.i('服务状态加载完成');

      // ⭐ 服务状态加载后，在下一帧计算 info 按钮位置
      // 此时占位符已经被渲染到屏幕上
      WidgetsBinding.instance.addPostFrameCallback((_) {
        calculateInfoButtonPosition();
      });
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

        // ⭐ 当服务状态更新时，重新计算 info 按钮位置
        // 这确保了首次设置服务状态后，占位符已渲染，可以正确计算位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          calculateInfoButtonPosition();
        });
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

      // ⭐ 先让弹出框渲染，然后计算实际尺寸和 alignment，最后开始动画
      WidgetsBinding.instance.addPostFrameCallback((_) {
        calculatePopupScaleAlignment();
        popupAnimationController.forward();
      });
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

  /// ⭐ 计算弹出框动画缩放原点（从 info 按钮中心展开）
  void calculatePopupScaleAlignment() {
    final RenderBox? stackBox =
        stackKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? placeholderBox =
        infoPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? popupBox =
        popupKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox == null || placeholderBox == null || popupBox == null) {
      return;
    }

    const popupWidth = 320.0;

    // 获取占位符相对于 Stack 的位置
    final placeholderGlobalPosition = placeholderBox.localToGlobal(Offset.zero);
    final placeholderLocalPosition = stackBox.globalToLocal(placeholderGlobalPosition);
    final placeholderSize = placeholderBox.size;

    // Info 按钮中心点位置
    final placeholderCenter = Offset(
      placeholderLocalPosition.dx + placeholderSize.width / 2,
      placeholderLocalPosition.dy + placeholderSize.height / 2,
    );

    // 弹出框左上角位置
    final popupLeft = placeholderLocalPosition.dx + placeholderSize.width - popupWidth + 16;
    final popupTop = placeholderLocalPosition.dy - 16;

    // info 按钮中心相对于弹出框左上角的偏移
    final offsetX = placeholderCenter.dx - popupLeft;
    final offsetY = placeholderCenter.dy - popupTop;

    // 获取弹出框实际高度
    final popupHeight = popupBox.size.height;

    // 转换为 FractionalOffset
    popupScaleAlignment.value = FractionalOffset(
      offsetX / popupWidth,
      offsetY / popupHeight,
    );

    _log.d('[PopupScaleAlignment] offset=($offsetX, $offsetY), size=($popupWidth, $popupHeight), alignment=(${offsetX / popupWidth}, ${offsetY / popupHeight})');
  }
}
