import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge/bridge.dart';
import 'bridge/frb_generated.dart';
import 'services/log_service.dart';

/// P2P 初始化配置
///
/// 用于在初始化时传递各种配置参数
class P2PInitConfig {
  /// 设备名称（必需）
  final String deviceName;

  /// 密钥对保存路径（可选，用于持久化 Peer ID）
  /// 如果为空，则每次启动生成新的随机 Peer ID
  /// 如果指定路径，则首次生成密钥对并保存，后续启动加载保存的密钥对
  final String? identityPath;

  /// 监听地址（可选，默认 "/ip4/0.0.0.0/tcp/0"）
  final List<String>? listenAddresses;

  /// 协议版本（可选，默认 "/localp2p/1.0.0"）
  final String? protocolVersion;

  /// 心跳间隔（秒，可选，默认 10）
  final int? heartbeatIntervalSecs;

  /// 心跳失败阈值（可选，默认 3）
  final int? maxFailures;

  P2PInitConfig({
    required this.deviceName,
    this.identityPath,
    this.listenAddresses,
    this.protocolVersion,
    this.heartbeatIntervalSecs,
    this.maxFailures,
  });
}

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
  StreamSubscription<P2PBridgeEvent>? _eventStreamSubscription;
  late P2PLogHelper _log;

  // 私有构造函数
  P2PManager._() {
    _log = P2PLogHelper();
  }

  /// 获取单例实例
  static P2PManager get instance {
    _instance ??= P2PManager._();
    return _instance!;
  }

  /// 初始化 P2P 模块
  Future<void> init(P2PInitConfig config) async {
    _log.rustCall('init', params: {'deviceName': config.deviceName});
    final stopwatch = Stopwatch()..start();

    // 先检查 Rust 端是否已初始化
    if (_isRustInitialized()) {
      _log.i('Rust 已初始化，同步状态...');
      debugPrint('Rust 已初始化，同步状态...');
      _syncState();
      _log.performance('init (already initialized)', stopwatch.elapsed);
      return;
    }

    // 初始化 flutter_rust_bridge
    _log.d('初始化 flutter_rust_bridge...');
    try {
      await RustLib.init();
      _log.d('flutter_rust_bridge 初始化成功');
    } catch (e, stackTrace) {
      _log.rustError('RustLib.init()', e, stackTrace);
      rethrow;
    }

    // 调用 Rust 初始化函数
    try {
      RustLib.instance.api.localp2PFfiBridgeP2PInit(
        deviceName: config.deviceName,
        identityPath: config.identityPath ?? '',
      );
      _initialized = true;
      _log.rustReturn('init', result: 'initialized=$_initialized');
      _log.performance('init', stopwatch.elapsed);
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PInit', e, stackTrace);
      throw Exception('Failed to initialize P2P: $e');
    }
  }

  /// 检查 Rust 端是否已初始化
  bool _isRustInitialized() {
    try {
      _log.t('检查 Rust 初始化状态...');
      // 尝试调用新的检查函数
      // 如果函数不存在（旧版本），捕获异常并返回 false
      final result = RustLib.instance.api.localp2PFfiBridgeP2PIsInitialized();
      _log.rustReturn('p2pIsInitialized', result: result);
      return result;
    } catch (e) {
      // 函数可能不存在，假设未初始化
      _log.w('p2pIsInitialized 调用失败: $e');
      debugPrint('p2pIsInitialized 调用失败: $e');
      return false;
    }
  }

  /// 同步 Rust 端状态到 Dart
  void _syncState() {
    _log.stateChange('未同步', '已同步');
    debugPrint('同步 Rust 状态到 Dart...');
    _initialized = true;

    // 恢复 Stream 订阅（如果未运行）
    if (_eventStreamSubscription == null) {
      _log.d('恢复事件 Stream 订阅...');
      _startEventStream();
    }
  }

  /// 重启事件流（用于应用从后台恢复时）
  ///
  /// 当应用从后台返回前台时，Stream 订阅可能处于中断状态
  /// 此方法会：
  /// 1. 重新订阅事件流（确保能接收日志）
  /// 2. 立即重启 discovery 服务（无条件）
  ///
  /// 使用无条件重启的原因：
  /// - 智能检查（先检查再重启）会导致连接恢复慢
  /// - 直接重启可以快速恢复 mDNS 和设备发现
  /// - 虽然会破坏正常工作的连接，但恢复后可以快速重新发现
  void resumeEventStream() {
    if (!_initialized) {
      _log.w('resumeEventStream 但未初始化');
      return;
    }

    _log.i('resumeEventStream: 应用恢复，立即重启 discovery...');

    // 1. 先重新订阅 Stream（确保能接收日志）
    _log.i('重启事件 Stream 订阅');
    _restartEventStream();

    // 2. 立即重启 discovery 服务（无条件）
    // 因为 Android 在后台会暂停 mDNS，恢复后需要立即重启
    _log.i('从后台恢复，立即重启 discovery');
    debugPrint('从后台恢复，立即重启 P2P discovery...');

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
      _log.i('P2P discovery 重启成功');
      debugPrint('✓ P2P discovery 重启成功');
    } catch (e, stackTrace) {
      _log.e('重启 P2P discovery 失败: $e', e, stackTrace);
      debugPrint('✗ 重启 P2P discovery 失败: $e');
    }
  }

  /// 检查 discovery 线程是否真的活着
  bool _isDiscoveryThreadAlive() {
    try {
      final result = RustLib.instance.api
          .localp2PFfiBridgeP2PIsDiscoveryThreadAlive();
      _log.rustReturn('p2pIsDiscoveryThreadAlive', result: result);
      return result;
    } catch (e) {
      _log.w('p2pIsDiscoveryThreadAlive 调用失败: $e');
      debugPrint('p2pIsDiscoveryThreadAlive 调用失败: $e');
      return false;
    }
  }

  /// 重启事件流订阅（内部方法）
  void _restartEventStream() {
    // 取消之前的订阅
    _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;

    // 启动新的订阅
    _startEventStream();
  }

  /// 事件流
  Stream<P2PEvent> get eventStream => _eventController.stream;

  /// 启动 P2P 服务
  Future<void> start() async {
    _log.rustCall('start');
    final stopwatch = Stopwatch()..start();

    if (!_initialized) {
      _log.e('调用 start 但未初始化');
      throw Exception('Not initialized');
    }

    // 检查是否已在运行
    if (_isRustRunning()) {
      _log.i('Rust 服务已在运行，仅恢复 Stream 订阅');
      debugPrint('Rust 服务已在运行，仅恢复 Stream 订阅');
      _startEventStream();
      _log.performance('start (already running)', stopwatch.elapsed);
      return;
    }

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PStart();
      _log.rustReturn('start', result: 'started');
      // 启动事件 Stream 订阅（推荐方式）
      _startEventStream();
      _log.performance('start', stopwatch.elapsed);
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PStart', e, stackTrace);
      throw Exception('Failed to start P2P: $e');
    }
  }

  /// 检查 Rust 端是否已运行
  bool _isRustRunning() {
    try {
      _log.t('检查 Rust 运行状态...');
      final result = RustLib.instance.api.localp2PFfiBridgeP2PIsRunning();
      _log.rustReturn('p2pIsRunning', result: result);
      return result;
    } catch (e) {
      _log.w('p2pIsRunning 调用失败: $e');
      debugPrint('p2pIsRunning 调用失败: $e');
      return false;
    }
  }

  /// 启动事件 Stream 订阅（Stream 模式）
  void _startEventStream() {
    // 取消之前的订阅（如果有）
    _eventStreamSubscription?.cancel();

    _log.d('启动事件 Stream 订阅');
    try {
      // 获取事件 Stream
      final eventStream = RustLib.instance.api
          .localp2PFfiBridgeP2PSetEventStream();

      // 订阅 Stream
      _eventStreamSubscription = eventStream.listen(
        (event) {
          _log.t('收到 Stream 事件，类型: ${event.eventType}');
          _handleEvent(event);
        },
        onError: (error) {
          _log.e('Stream 错误: $error');
          debugPrint('Event stream error: $error');
        },
        onDone: () {
          _log.w('Stream 结束');
          debugPrint('Event stream ended');
        },
      );
    } catch (e, stackTrace) {
      _log.e('Failed to start event stream: $e', e, stackTrace);
      debugPrint('Failed to start event stream: $e');
    }
  }

  void _handleEvent(P2PBridgeEvent event) {
    _log.t('处理事件类型: ${event.eventType}');

    switch (event.eventType) {
      case 1: // NodeDiscovered
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _log.node('discovered', peerId);
          _eventController.add(NodeDiscoveredEvent(peerId));
        } else {
          _log.w('NodeDiscovered 事件但无法解析 peerId: ${event.data}');
        }
        break;

      case 3: // NodeVerified
        final peerId = _extractPeerId(event.data);
        final displayName = _extractDisplayName(event.data);
        if (peerId != null && displayName != null) {
          _log.node('verified', peerId, details: {'displayName': displayName});
          _eventController.add(NodeVerifiedEvent(peerId, displayName));
        } else {
          _log.w('NodeVerified 事件但无法解析: ${event.data}');
        }
        break;

      case 4: // NodeOffline
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _log.node('offline', peerId);
          _eventController.add(NodeOfflineEvent(peerId));
        } else {
          _log.w('NodeOffline 事件但无法解析 peerId: ${event.data}');
        }
        break;

      case 5: // UserInfoReceived
        final peerId = _extractPeerId(event.data);
        final deviceName = _extractDeviceName(event.data);
        final nickname = _extractNickname(event.data);
        final status = _extractStatus(event.data);
        final avatarUrl = _extractAvatarUrl(event.data);
        if (peerId != null && deviceName != null) {
          _log.node(
            'userInfo',
            peerId,
            details: {
              'deviceName': deviceName,
              'nickname': nickname,
              'status': status,
            },
          );
          _eventController.add(
            UserInfoReceivedEvent(
              peerId,
              deviceName,
              nickname: nickname,
              status: status,
              avatarUrl: avatarUrl,
            ),
          );
        } else {
          _log.w('UserInfoReceived 事件但无法解析: ${event.data}');
        }
        break;

      case 6: // MessageReceived
        final from = _extractFrom(event.data);
        final content = _extractContent(event.data);
        final timestamp = _extractTimestamp(event.data);
        if (from != null && content != null) {
          _log.message('RECEIVED', from, content);
          _eventController.add(
            MessageReceivedEvent(from, content, timestamp ?? 0),
          );
        } else {
          _log.w('MessageReceived 事件但无法解析: ${event.data}');
        }
        break;

      case 7: // MessageSent
        final to = _extractTo(event.data);
        final messageId = _extractMessageId(event.data);
        if (to != null && messageId != null) {
          _log.message('SENT', to, 'messageId=$messageId');
          _eventController.add(MessageSentEvent(to, messageId));
        } else {
          _log.w('MessageSent 事件但无法解析: ${event.data}');
        }
        break;

      case 8: // PeerTyping
        final from = _extractFrom(event.data);
        final isTyping = _extractIsTyping(event.data);
        if (from != null && isTyping != null) {
          _log.d('Peer typing: $from isTyping=$isTyping');
          _eventController.add(PeerTypingEvent(from, isTyping));
        } else {
          _log.w('PeerTyping 事件但无法解析: ${event.data}');
        }
        break;

      case 9: // Rust 日志
        final level = _extractLogLevel(event.data);
        final target = _extractLogTarget(event.data);
        final message = _extractLogMessage(event.data);
        if (level != null && target != null && message != null) {
          _handleRustLog(level, target, message);
        } else {
          _log.w('Rust 日志事件但无法解析: ${event.data}');
        }
        break;

      default:
        _log.w('未知事件类型: ${event.eventType}, data: ${event.data}');
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

  /// 处理 Rust 日志
  void _handleRustLog(String level, String target, String message) {
    // 使用 LogService 输出到日志文件
    final logService = LogService.instance;

    // 根据级别选择合适的日志方法
    switch (level.toUpperCase()) {
      case 'ERROR':
        logService.e('[$target] $message');
        break;
      case 'WARN':
        logService.w('[$target] $message');
        break;
      case 'INFO':
        logService.i('[$target] $message');
        break;
      case 'DEBUG':
        logService.d('[$target] $message');
        break;
      case 'TRACE':
        logService.t('[$target] $message');
        break;
      default:
        logService.i('[$target] $message');
    }

    // 同时输出到控制台（方便调试）
    debugPrint('🔶 [$level] $target: $message');
  }

  String? _extractLogLevel(String data) {
    final match = RegExp(r'"level":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractLogTarget(String data) {
    final match = RegExp(r'"target":"([^"]*)"').firstMatch(data);
    return match?.group(1);
  }

  String? _extractLogMessage(String data) {
    // 匹配 message 字段，处理转义字符
    final match = RegExp(r'"message":"((?:[^"\\]|\\.)*)"').firstMatch(data);
    if (match == null) return null;
    // 将转义字符转换回原始字符
    return match.group(1)?.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }

  /// 停止 P2P 服务
  Future<void> stop() async {
    _log.rustCall('stop');

    if (!_initialized) {
      _log.w('调用 stop 但未初始化');
      return;
    }

    // 取消 Stream 订阅
    _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PStop();
      _log.rustReturn('stop', result: 'stopped');
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PStop', e, stackTrace);
      throw Exception('Failed to stop P2P: $e');
    }
  }

  /// 清理资源
  void cleanup() {
    _log.rustCall('cleanup');

    // 取消 Stream 订阅
    _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;

    if (_initialized) {
      try {
        RustLib.instance.api.localp2PFfiBridgeP2PCleanup();
        _log.rustReturn('cleanup', result: 'cleaned');
      } catch (e) {
        _log.w('Cleanup error (ignoring): $e');
        // 忽略清理错误
      }
      _initialized = false;
    }
    _eventController.close();

    // 清理 flutter_rust_bridge
    try {
      RustLib.dispose();
      _log.d('RustLib disposed');
    } catch (e) {
      _log.w('RustLib.dispose error: $e');
    }
  }

  /// 获取本地 Peer ID
  String getLocalPeerId() {
    if (!_initialized) {
      _log.e('getLocalPeerId 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取本地 Peer ID');
    final result = RustLib.instance.api.localp2PFfiBridgeP2PGetLocalPeerId();
    _log.d('本地 Peer ID: $result');
    return result;
  }

  /// 获取设备名称
  String getDeviceName() {
    if (!_initialized) {
      _log.e('getDeviceName 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取设备名称');
    final result = RustLib.instance.api.localp2PFfiBridgeP2PGetDeviceName();
    _log.d('设备名称: $result');
    return result;
  }

  /// 获取已验证的节点列表
  List<P2PBridgeNodeInfo> getVerifiedNodes() {
    if (!_initialized) {
      _log.e('getVerifiedNodes 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取已验证节点列表');
    final result = RustLib.instance.api.localp2PFfiBridgeP2PGetVerifiedNodes();
    _log.d('已验证节点数: ${result.length}');
    return result;
  }

  /// 发送消息给指定节点
  void sendMessage(String targetPeerId, String message) {
    if (!_initialized) {
      _log.e('sendMessage 但未初始化');
      throw Exception('Not initialized');
    }

    _log.message('SEND', targetPeerId, message);
    _log.rustCall(
      'sendMessage',
      params: {'targetPeerId': targetPeerId, 'message': message},
    );

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PSendMessage(
        targetPeerId: targetPeerId,
        message: message,
      );
      _log.rustReturn('sendMessage', result: 'sent');
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PSendMessage', e, stackTrace);
      rethrow;
    }
  }

  /// 广播消息给多个节点
  void broadcastMessage(List<String> targetPeerIds, String message) {
    if (!_initialized) {
      _log.e('broadcastMessage 但未初始化');
      throw Exception('Not initialized');
    }

    _log.d('广播消息给 ${targetPeerIds.length} 个节点');
    _log.message('BROADCAST', targetPeerIds.join(','), message);
    _log.rustCall(
      'broadcastMessage',
      params: {'targetPeerIds': targetPeerIds, 'message': message},
    );

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PBroadcastMessage(
        targetPeerIds: targetPeerIds,
        message: message,
      );
      _log.rustReturn('broadcastMessage', result: 'broadcasted');
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PBroadcastMessage', e, stackTrace);
      rethrow;
    }
  }

  /// 获取指定节点的用户信息
  P2PBridgeNodeInfo? getUserInfo(String peerId) {
    if (!_initialized) {
      _log.e('getUserInfo 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取用户信息: $peerId');

    // TODO: 实现 getUserInfo API
    // 暂时从所有节点中查找
    final nodes = getVerifiedNodes();
    try {
      final result = nodes.firstWhere((n) => n.peerId == peerId);
      _log.d('找到用户信息: ${result.deviceName}');
      return result;
    } catch (e) {
      _log.w('未找到用户信息: $peerId');
      return null;
    }
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;
}
