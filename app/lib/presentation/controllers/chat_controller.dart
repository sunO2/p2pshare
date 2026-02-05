import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../p2p_manager.dart';
import '../../../bridge/frb_generated.dart';
import '../../../bridge/types.dart';
import '../../../services/p2p_event_bus.dart' as eb;
import '../../services/log_service.dart';
import '../../data/models/chat_message_model.dart';
import 'package:uuid/uuid.dart';

/// 聊天控制器
///
/// 管理：消息列表、发送消息、在线状态、历史消息加载
class ChatController extends GetxController
    with GetTickerProviderStateMixin {
  // ========== 参数 ==========

  /// 对方 Peer ID
  final String peerId = Get.parameters['peerId'] ?? '';

  /// 对方名称
  final String peerName = Get.parameters['peerName'] ?? 'Unknown';

  // ========== 状态变量 ==========

  /// 消息列表
  final messages = <ChatMessageData>[].obs;

  /// 是否正在加载历史消息
  final isLoadingHistory = false.obs;

  /// 是否还有更多历史消息
  final hasMore = true.obs;

  /// 在线状态
  final isOnline = true.obs;

  /// 状态文本
  final statusText = '在线'.obs;

  // ========== 控制器 ==========

  late TextEditingController messageController;
  late ScrollController scrollController;

  // ========== 订阅 ==========

  StreamSubscription<eb.P2PEvent>? statusSubscription;
  StreamSubscription<eb.P2PEvent>? extendedMessageSubscription;

  // ========== 配置 ==========

  final int pageSize = 20;
  bool autoLoadTriggered = false;

  // ========== 依赖注入 ==========

  final LogService _log = Get.find<LogService>();
  final Uuid _uuid = const Uuid();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[ChatController] onInit - peerId: $peerId, peerName: $peerName');

    // 防止重复初始化（onInit 可能被多次调用）
    if (!_lateInitialized) {
      messageController = TextEditingController();
      scrollController = ScrollController();
      _lateInitialized = true;
    }

    loadCurrentStatus();
    loadHistoricalMessages();
    listenToEventBus();
    setupScrollListener();
  }

  // 是否已初始化 late 字段
  bool _lateInitialized = false;

  @override
  void onReady() {
    super.onReady();
    _log.i('[ChatController] onReady');
  }

  @override
  void onClose() {
    _log.i('[ChatController] onClose');
    statusSubscription?.cancel();
    extendedMessageSubscription?.cancel();
    messageController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ========== 消息加载 ==========

  /// 加载历史消息
  Future<void> loadHistoricalMessages({bool loadMore = false}) async {
    if (isLoadingHistory.value) return;
    if (loadMore && !hasMore.value) return;

    _log.i('[ChatController] 加载历史消息 ${loadMore ? "(加载更多)" : ""}');
    isLoadingHistory.value = true;

    try {
      final beforeTimestamp = loadMore && messages.isNotEmpty
          ? messages.last.timestamp
          : null;

      final result = await RustLib.instance.api
          .localp2PFfiBridgeP2PGetMessagesByPeer(
            peerId: peerId,
            limit: pageSize,
            beforeTimestamp: beforeTimestamp,
          );

      _log.i('[ChatController] 返回 ${result.length} 条消息');

      final newMessages = result
          .map((msg) => ChatMessageData.fromJson(msg, _getLocalPeerId()))
          .toList();

      if (loadMore) {
        messages.addAll(newMessages);
      } else {
        messages.assignAll(newMessages);
      }

      hasMore.value = result.length >= pageSize;

      if (loadMore) {
        Future.delayed(const Duration(milliseconds: 500), () {
          autoLoadTriggered = false;
        });
      }

      _log.i('[ChatController] 已加载 ${messages.length} 条消息');
    } catch (e, stackTrace) {
      _log.e('[ChatController] 加载历史消息失败: $e', e, stackTrace);
      autoLoadTriggered = false;
    } finally {
      isLoadingHistory.value = false;
    }
  }

  /// 获取本地 Peer ID
  String _getLocalPeerId() {
    try {
      return P2PManager.instance.getLocalPeerId();
    } catch (e) {
      return '';
    }
  }

  // ========== 消息发送 ==========

  /// 发送消息
  Future<void> sendMessage(
    String text, {
    Map<String, dynamic>? extra,
  }) async {
    if (text.trim().isEmpty && extra == null) return;

    try {
      // 构造消息
      final messageType = (extra == null)
          ? MessageType.text
          : _getMessageTypeFromExtra(extra);

      // content 字段：文本消息直接传文本，其他类型传空或描述
      final content = (messageType == MessageType.text)
          ? text
          : '';

      // extra 字段：序列化为 JSON 字符串
      final extraJson = (extra != null)
          ? jsonEncode(extra)
          : null;

      await RustLib.instance.api.localp2PFfiBridgeP2PSendMessageEx(
        targetPeerId: peerId,
        messageType: messageType,
        content: content,
        extra: extraJson,
      );

      messageController.clear();

      // 立即添加到本地消息列表
      messages.insert(
        0,
        ChatMessageData(
          id: _uuid.v4(), // 临时 ID
          conversationId: '',
          senderPeerId: _getLocalPeerId(),
          messageType: messageType,
          content: content,
          extra: extra != null ? MessageExtra(extra) : null,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isSelf: true,
        ),
      );
    } catch (e, stackTrace) {
      _log.e('[ChatController] 发送消息失败: $e', e, stackTrace);
      Get.snackbar(
        '发送失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// 从 extra 推断消息类型
  int _getMessageTypeFromExtra(Map<String, dynamic> extra) {
    final mimeType = extra['mimeType'] as String?;
    if (mimeType == null) return MessageType.text;

    if (mimeType.startsWith('image/')) return MessageType.image;
    if (mimeType.startsWith('video/')) return MessageType.video;
    if (mimeType.startsWith('audio/')) return MessageType.audio;
    return MessageType.file;
  }

  /// 模拟发送文件消息
  Future<void> sendFileMessage() async {
    // 模拟文件数据
    final fileExtra = {
      'fileId': _uuid.v4(),
      'fileName': '示例文档.pdf',
      'fileSize': 1024000, // 1MB
      'mimeType': 'application/pdf',
    };

    await sendMessage('', extra: fileExtra);
  }

  /// 模拟发送图片消息
  Future<void> sendImageMessage() async {
    final imageExtra = {
      'fileId': _uuid.v4(),
      'fileName': '示例图片.jpg',
      'fileSize': 204800, // 200KB
      'mimeType': 'image/jpeg',
      'width': 1920,
      'height': 1080,
    };

    await sendMessage('', extra: imageExtra);
  }

  /// 模拟发送视频消息
  Future<void> sendVideoMessage() async {
    final videoExtra = {
      'fileId': _uuid.v4(),
      'fileName': '示例视频.mp4',
      'fileSize': 5120000, // 5MB
      'mimeType': 'video/mp4',
      'duration': 60, // 60秒
      'width': 1280,
      'height': 720,
    };

    await sendMessage('', extra: videoExtra);
  }

  // ========== 事件监听 ==========

  /// 设置滚动监听
  void setupScrollListener() {
    scrollController.addListener(() {
      if (!scrollController.hasClients) return;

      final position = scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final current = position.pixels;
      final distanceFromTop = maxScroll - current;

      if (hasMore.value &&
          !isLoadingHistory.value &&
          !autoLoadTriggered &&
          distanceFromTop < 300) {
        _log.i('[ChatController] 触发自动加载更多');
        autoLoadTriggered = true;
        loadHistoricalMessages(loadMore: true);
      }

      if (distanceFromTop > 500) {
        autoLoadTriggered = false;
      }
    });
  }

  /// 将 Map<String, dynamic> 转换为 MessageJson
  MessageJson _convertToMessageJson(Map<String, dynamic> data) {
    return MessageJson(
      id: data['id'] as String? ?? '',
      conversationId: data['conversationId'] as String? ?? '',
      senderPeerId: data['senderPeerId'] as String? ?? '',
      messageType: data['messageType'] as int? ?? 1,
      content: data['content'] as String? ?? '',
      timestamp: data['timestamp'] as int? ?? 0,
      replyToId: data['replyToId'] as String?,
      status: data['status'] as int? ?? 0,
      isDeleted: data['isDeleted'] as bool? ?? false,
      isRevoked: data['isRevoked'] as bool? ?? false,
      extra: data['extra'] as String?,
    );
  }

  /// 监听事件总线
  void listenToEventBus() {
    _log.i('[ChatController] 开始监听事件总线 - peerId: $peerId');

    // 🔥 只订阅 online 和 offline 事件（不订阅所有事件）
    statusSubscription = eb.P2PEventBus.instance
        .on(peerId: peerId)
        .where((event) => event.type == 'online' || event.type == 'offline')
        .listen((event) {
      _log.d('[ChatController] 状态事件: ${event.type}, data: ${event.data}');
      if (event.type == 'offline') {
        isOnline.value = false;
        statusText.value = '离线';
      } else {
        // online 事件，从 data 中获取 status
        final status = event.data?['status'];
        if (status != null && status is String) {
          final statusStr = status.toLowerCase();
          isOnline.value = statusStr != '离线' && statusStr != 'offline';
          statusText.value = status;
        } else {
          isOnline.value = true;
          statusText.value = '在线';
        }
      }
    });

    _log.i('[ChatController] 状态订阅已创建');

    // 🔥 监听扩展消息事件（包含 extra 字段）
    extendedMessageSubscription = eb.P2PEventBus.instance
        .on(peerId: peerId, type: 'extended_message')
        .listen((event) {
      _log.i('[ChatController] 🔥 收到扩展消息事件: type=${event.type}, peerId=${event.peerId}');

      final messageData = event.data;
      _log.d('[ChatController] 消息数据类型: ${messageData.runtimeType}');

      if (messageData is Map<String, dynamic>) {
        try {
          _log.d('[ChatController] 消息数据: $messageData');
          final msg = ChatMessageData.fromJson(
            _convertToMessageJson(messageData),
            _getLocalPeerId(),
          );
          _log.i('[ChatController] 消息解析成功，插入到列表: ${msg.id}');
          messages.insert(0, msg);
        } catch (e, stackTrace) {
          _log.e('[ChatController] 解析扩展消息失败: $e', e, stackTrace);
        }
      } else {
        _log.w('[ChatController] 消息数据格式错误，期望 Map<String, dynamic>，实际: ${messageData.runtimeType}');
      }
    });

    _log.i('[ChatController] 扩展消息订阅已创建');
  }

  // ========== 状态加载 ==========

  /// 加载当前状态
  void loadCurrentStatus() {
    // 🔥 不再使用 getCurrentData()，因为它会被消息事件污染
    // 改为直接查询 EventBus 的 isOnline 方法
    isOnline.value = eb.P2PEventBus.instance.isOnline(peerId);
    statusText.value = isOnline.value ? '在线' : '离线';

    _log.d('[ChatController] 初始状态加载: ${statusText.value}');
  }

  // ========== 导航操作 ==========

  /// 打开设备详情
  void openDeviceDetail() {
    Get.toNamed(
      '/device-detail',
      parameters: {'peerId': peerId},
    );
  }

  /// 打开设备设置
  void openSettings() {
    Get.toNamed(
      '/peer-settings',
      parameters: {
        'peerId': peerId,
        'peerName': peerName,
      },
    );
  }
}
