import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge/bridge.dart';
import 'bridge/frb_generated.dart';

// P2P 事件类型（兼容旧的事件系统）
class P2PEvent {}

class NodeDiscoveredEvent extends P2PEvent {
  final String peerId;
  NodeDiscoveredEvent(this.peerId);
}

class NodeExpiredEvent extends P2PEvent {
  final String peerId;
  NodeExpiredEvent(this.peerId);
}

class NodeVerifiedEvent extends P2PEvent {
  final String peerId;
  final String displayName;
  NodeVerifiedEvent(this.peerId, this.displayName);
}

class NodeOfflineEvent extends P2PEvent {
  final String peerId;
  NodeOfflineEvent(this.peerId);
}

class MessageReceivedEvent extends P2PEvent {
  final String from;
  final String message;
  final int timestamp;
  MessageReceivedEvent(this.from, this.message, this.timestamp);
}

class MessageSentEvent extends P2PEvent {
  final String to;
  final String messageId;
  MessageSentEvent(this.to, this.messageId);
}

class PeerTypingEvent extends P2PEvent {
  final String from;
  final bool isTyping;
  PeerTypingEvent(this.from, this.isTyping);
}

class UserInfoReceivedEvent extends P2PEvent {
  final String peerId;
  final String deviceName;
  final String? nickname;
  final String? status;
  final String? avatarUrl;
  UserInfoReceivedEvent(
    this.peerId,
    this.deviceName, {
    this.nickname,
    this.status,
    this.avatarUrl,
  });
}

/// P2P 服务管理器
///
/// 使用 flutter_rust_bridge 与 Rust 后端通信
class P2PManager {
  static P2PManager? _instance;
  bool _initialized = false;
  final _eventController = StreamController<P2PEvent>.broadcast();
  Timer? _pollTimer;

  // 私有构造函数
  P2PManager._();

  /// 获取单例实例
  static P2PManager get instance {
    _instance ??= P2PManager._();
    return _instance!;
  }

  /// 初始化 P2P 模块
  Future<void> init(String deviceName) async {
    if (_initialized) {
      throw Exception('Already initialized');
    }

    // 初始化 flutter_rust_bridge
    await RustLib.init();

    // 调用 Rust 初始化函数
    try {
      RustLib.instance.api.localp2PFfiBridgeP2PInit(deviceName: deviceName);
      _initialized = true;
    } catch (e) {
      throw Exception('Failed to initialize P2P: $e');
    }
  }

  /// 事件流
  Stream<P2PEvent> get eventStream => _eventController.stream;

  /// 启动 P2P 服务
  Future<void> start() async {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PStart();
      // 启动轮询以模拟事件（临时方案）
      _startPolling();
    } catch (e) {
      throw Exception('Failed to start P2P: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final events = RustLib.instance.api.localp2PFfiBridgeP2PPollEvents();
        for (final event in events) {
          _handleEvent(event);
        }
      } catch (e) {
        debugPrint('Failed to poll events: $e');
      }
    });
  }

  void _handleEvent(P2PBridgeEvent event) {
    switch (event.eventType) {
      case 1: // NodeDiscovered
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _eventController.add(NodeDiscoveredEvent(peerId));
        }
        break;
      case 3: // NodeVerified
        final peerId = _extractPeerId(event.data);
        final displayName = _extractDisplayName(event.data);
        if (peerId != null && displayName != null) {
          _eventController.add(NodeVerifiedEvent(peerId, displayName));
        }
        break;
      case 4: // NodeOffline
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _eventController.add(NodeOfflineEvent(peerId));
        }
        break;
      case 5: // UserInfoReceived
        final peerId = _extractPeerId(event.data);
        final deviceName = _extractDeviceName(event.data);
        final nickname = _extractNickname(event.data);
        final status = _extractStatus(event.data);
        final avatarUrl = _extractAvatarUrl(event.data);
        if (peerId != null && deviceName != null) {
          _eventController.add(
            UserInfoReceivedEvent(
              peerId,
              deviceName,
              nickname: nickname,
              status: status,
              avatarUrl: avatarUrl,
            ),
          );
        }
        break;
      case 6: // MessageReceived
        final from = _extractFrom(event.data);
        final content = _extractContent(event.data);
        final timestamp = _extractTimestamp(event.data);
        if (from != null && content != null) {
          _eventController.add(
            MessageReceivedEvent(from, content, timestamp ?? 0),
          );
        }
        break;
      case 7: // MessageSent
        final to = _extractTo(event.data);
        final messageId = _extractMessageId(event.data);
        if (to != null && messageId != null) {
          _eventController.add(MessageSentEvent(to, messageId));
        }
        break;
      case 8: // PeerTyping
        final from = _extractFrom(event.data);
        final isTyping = _extractIsTyping(event.data);
        if (from != null && isTyping != null) {
          _eventController.add(PeerTypingEvent(from, isTyping));
        }
        break;
    }
  }

  String? _extractPeerId(String data) {
    final match = RegExp(r'"peer_id":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractDisplayName(String data) {
    final match = RegExp(r'"display_name":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractFrom(String data) {
    final match = RegExp(r'"from":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractContent(String data) {
    final match = RegExp(r'"content":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  int? _extractTimestamp(String data) {
    final match = RegExp(r'"timestamp":(\d+)').firstMatch(data);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  String? _extractTo(String data) {
    final match = RegExp(r'"to":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractMessageId(String data) {
    final match = RegExp(r'"message_id":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  bool? _extractIsTyping(String data) {
    final match = RegExp(r'"is_typing":(true|false)').firstMatch(data);
    return match?.group(1) == 'true';
  }

  String? _extractDeviceName(String data) {
    final match = RegExp(r'"device_name":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractNickname(String data) {
    final match = RegExp(r'"nickname":"([^"]*)"').firstMatch(data);
    final value = match?.group(1);
    return (value == null || value == 'null') ? null : value;
  }

  String? _extractStatus(String data) {
    final match = RegExp(r'"status":"([^"]*)"').firstMatch(data);
    final value = match?.group(1);
    return (value == null || value == 'null') ? null : value;
  }

  String? _extractAvatarUrl(String data) {
    final match = RegExp(r'"avatar_url":"([^"]*)"').firstMatch(data);
    final value = match?.group(1);
    return (value == null || value == 'null') ? null : value;
  }

  /// 停止 P2P 服务
  Future<void> stop() async {
    if (!_initialized) {
      return;
    }

    _pollTimer?.cancel();
    try {
      RustLib.instance.api.localp2PFfiBridgeP2PStop();
    } catch (e) {
      throw Exception('Failed to stop P2P: $e');
    }
  }

  /// 清理资源
  void cleanup() {
    _pollTimer?.cancel();
    if (_initialized) {
      try {
        RustLib.instance.api.localp2PFfiBridgeP2PCleanup();
      } catch (e) {
        // 忽略清理错误
      }
      _initialized = false;
    }
    _eventController.close();

    // 清理 flutter_rust_bridge
    RustLib.dispose();
  }

  /// 获取本地 Peer ID
  String getLocalPeerId() {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    return RustLib.instance.api.localp2PFfiBridgeP2PGetLocalPeerId();
  }

  /// 获取设备名称
  String getDeviceName() {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    return RustLib.instance.api.localp2PFfiBridgeP2PGetDeviceName();
  }

  /// 获取已验证的节点列表
  List<P2PBridgeNodeInfo> getVerifiedNodes() {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    return RustLib.instance.api.localp2PFfiBridgeP2PGetVerifiedNodes();
  }

  /// 发送消息给指定节点
  void sendMessage(String targetPeerId, String message) {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    RustLib.instance.api.localp2PFfiBridgeP2PSendMessage(
      targetPeerId: targetPeerId,
      message: message,
    );
  }

  /// 广播消息给多个节点
  void broadcastMessage(
    List<String> targetPeerIds,
    String message,
  ) {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    RustLib.instance.api.localp2PFfiBridgeP2PBroadcastMessage(
      targetPeerIds: targetPeerIds,
      message: message,
    );
  }

  /// 获取指定节点的用户信息
  P2PBridgeNodeInfo? getUserInfo(String peerId) {
    if (!_initialized) {
      throw Exception('Not initialized');
    }

    // TODO: 实现 getUserInfo API
    // 暂时从所有节点中查找
    final nodes = getVerifiedNodes();
    try {
      return nodes.firstWhere((n) => n.peerId == peerId);
    } catch (e) {
      return null;
    }
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;
}
