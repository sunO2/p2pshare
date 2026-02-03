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

  late final TextEditingController messageController;
  late final ScrollController scrollController;

  // ========== 订阅 ==========

  eb.P2PEventSubscription<eb.P2PEvent>? statusSubscription;
  StreamSubscription<eb.P2PEvent>? messageSubscription;
  StreamSubscription? p2pManagerSubscription;

  // ========== 配置 ==========

  final int pageSize = 20;
  bool autoLoadTriggered = false;

  // ========== 依赖注入 ==========

  final LogService _log = Get.find<LogService>();

  // ========== 生命周期 ==========

  @override
  void onInit() {
    super.onInit();
    _log.i('[ChatController] onInit - peerId: $peerId, peerName: $peerName');

    messageController = TextEditingController();
    scrollController = ScrollController();

    loadCurrentStatus();
    loadHistoricalMessages();
    listenToEvents();
    listenToEventBus();
    setupScrollListener();
  }

  @override
  void onReady() {
    super.onReady();
    _log.i('[ChatController] onReady');
  }

  @override
  void onClose() {
    _log.i('[ChatController] onClose');
    statusSubscription?.cancel();
    messageSubscription?.cancel();
    p2pManagerSubscription?.cancel();
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
          ? messages.last.timestamp.millisecondsSinceEpoch
          : null;

      final result = await RustLib.instance.api
          .localp2PFfiBridgeP2PGetMessagesByPeer(
            peerId: peerId,
            limit: pageSize,
            beforeTimestamp: beforeTimestamp,
          );

      _log.i('[ChatController] 返回 ${result.length} 条消息');

      final newMessages = result
          .map((msg) => _parseMessageJson(msg))
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

  /// 解析消息 JSON
  ChatMessageData _parseMessageJson(MessageJson msg) {
    String displayText = '';
    try {
      final contentJson = jsonDecode(msg.content);
      if (msg.messageType == 1) {
        displayText = contentJson['text'] ?? '';
      } else if (msg.messageType == 2) {
        displayText = '[图片]';
      } else if (msg.messageType == 3) {
        displayText = '[视频]';
      } else if (msg.messageType == 4) {
        displayText = '[文件]';
      } else if (msg.messageType == 5) {
        displayText = '[音频]';
      } else {
        displayText = '[未知消息]';
      }
    } catch (e) {
      displayText = msg.content;
    }

    final isSelf = msg.senderPeerId == _getLocalPeerId();

    return ChatMessageData(
      message: displayText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestamp.toInt()),
      isSelf: isSelf,
    );
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
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await P2PManager.instance.sendMessage(peerId, text);
    } catch (e) {
      _log.e('[ChatController] 发送消息失败: $e', e);
      Get.snackbar(
        '发送失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    messageController.clear();

    // 立即添加到本地消息列表
    messages.insert(
      0,
      ChatMessageData(
        message: text,
        timestamp: DateTime.now(),
        isSelf: true,
      ),
    );
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

  /// 监听 P2P 事件
  void listenToEvents() {
    p2pManagerSubscription = P2PManager.instance.eventStream.listen((event) {
      if (event is MessageReceivedEvent && event.from == peerId) {
        messages.insert(
          0,
          ChatMessageData(
            message: event.message,
            timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
            isSelf: false,
          ),
        );
      } else if (event is MessageSentEvent && event.to == peerId) {
        messages.insert(
          0,
          ChatMessageData(
            message: '(sent)',
            timestamp: DateTime.now(),
            isSelf: true,
          ),
        );
      }
    });
  }

  /// 监听事件总线
  void listenToEventBus() {
    statusSubscription = eb.P2PEventBus.instance.subscribe(
      peerId: peerId,
      onData: (event) {
        if (event.type == 'online' || event.type == 'offline') {
          final status = event.data?['status'];
          if (event.type == 'offline') {
            isOnline.value = false;
            statusText.value = '离线';
          } else if (status != null) {
            final statusStr = status.toString().toLowerCase();
            isOnline.value = statusStr != '离线' && statusStr != 'offline';
            statusText.value = status ?? '在线';
          } else {
            isOnline.value = true;
            statusText.value = '在线';
          }
        }
      },
    );

    messageSubscription = eb.P2PEventBus.instance
        .on(peerId: peerId, type: 'message')
        .listen((event) {
      final messageData = event.data;
      if (messageData is Map<String, dynamic>) {
        final message = messageData['message'] as String?;
        final timestamp = messageData['timestamp'] as int?;
        if (message != null) {
          messages.insert(
            0,
            ChatMessageData(
              message: message,
              timestamp: timestamp != null
                  ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                  : DateTime.now(),
              isSelf: false,
            ),
          );
        }
      }
    });
  }

  // ========== 状态加载 ==========

  /// 加载当前状态
  void loadCurrentStatus() {
    final currentData = eb.P2PEventBus.instance.getCurrentData(peerId);
    if (currentData != null) {
      final status = currentData['status'];
      if (status != null) {
        final statusStr = status.toString().toLowerCase();
        isOnline.value = statusStr != '离线' && statusStr != 'offline';
        statusText.value = isOnline.value ? (status ?? '在线') : '离线';
      }
    } else {
      isOnline.value = eb.P2PEventBus.instance.isOnline(peerId);
      statusText.value = isOnline.value ? '在线' : '离线';
    }
  }

  // ========== 导航操作 ==========

  /// 打开设备详情
  void openDeviceDetail() {
    Get.toNamed(
      '/device-detail',
      parameters: {'peerId': peerId},
    );
  }
}
