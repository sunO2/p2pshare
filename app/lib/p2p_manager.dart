import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';
import 'bridge/bridge.dart' as bridge;
import 'bridge/frb_generated.dart';
import 'bridge/third_party/localp2p_ffi/bridge.dart' as frb_bridge;
import 'services/log_service.dart';
import 'services/flutter_mdns_service.dart';
import 'services/p2p_event_bus.dart';

/// P2P 初始化配置
///
/// 用于在初始化时传递各种配置参数
class P2PInitConfig {
  /// 设备名称（必需）
  final String deviceName;

  /// 🔥 工作目录（可选）
  ///
  /// 所有数据（数据库、日志、证书）将存储在此目录下的子目录中：
  /// - `{workDir}/data/` - 数据库文件（chat.db, devices.db）
  /// - `{workDir}/logs/` - 日志文件
  /// - `{workDir}/certs/` - 证书文件（identity.key）
  ///
  /// 如果为空，将使用应用默认目录
  /// 建议使用外部存储目录，方便调试和备份
  final String? workDir;

  /// 🔥 已弃用：请使用 workDir 代替
  /// 保留此字段是为了向后兼容，内部会自动转换为 workDir
  @Deprecated('Use workDir instead')
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
    this.workDir,
    this.identityPath,
    this.listenAddresses,
    this.protocolVersion,
    this.heartbeatIntervalSecs,
    this.maxFailures,
  });

  /// 🔥 获取实际的工作目录路径
  ///
  /// 优先使用 workDir，如果没有则从 identityPath 提取父目录
  String? get effectiveWorkDir {
    if (workDir != null && workDir!.isNotEmpty) {
      return workDir;
    }
    if (identityPath != null && identityPath!.isNotEmpty) {
      // 从 identityPath 提取父目录（向后兼容）
      final path = Uri.file(identityPath!).path;
      final lastSlash = path.lastIndexOf('/');
      if (lastSlash > 0) {
        return path.substring(0, lastSlash);
      }
    }
    return null;
  }
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

/// VPN 检测事件 - 需要启动 Flutter mDNS 辅助服务
class VpnDetectedEvent extends P2PEvent {
  final List<String> vpnInterfaces;
  final String? physicalInterface;
  final String localPeerId;
  final int port;
  final String serviceType;

  VpnDetectedEvent({
    required this.vpnInterfaces,
    this.physicalInterface,
    required this.localPeerId,
    required this.port,
    required this.serviceType,
  });

  @override
  String toString() {
    return 'VpnDetectedEvent(vpn: $vpnInterfaces, physical: $physicalInterface, port: $port)';
  }
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

/// 🔥 服务状态数据
class ServiceStatusData {
  final String name;
  final String health; // "healthy", "degraded", "unhealthy"
  final bool isRunning;
  final String? message;

  ServiceStatusData({
    required this.name,
    required this.health,
    required this.isRunning,
    this.message,
  });

  factory ServiceStatusData.fromJson(Map<String, dynamic> json) {
    return ServiceStatusData(
      name: json['name'] as String,
      health: json['health'] as String,
      isRunning: json['is_running'] as bool,
      message: json['message'] as String?,
    );
  }
}

/// 🔥 服务状态变化事件
class ServiceStatusChangedEvent extends P2PEvent {
  final String service; // "mDNS" or "Connection"
  final ServiceStatusData status;

  ServiceStatusChangedEvent({required this.service, required this.status});
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

  // 保存配置用于重启
  P2PInitConfig? _savedConfig;

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
    // 保存配置用于后续重启
    _savedConfig = config;

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
      // 🔥 使用 effectiveWorkDir 作为工作目录
      final workDir = config.effectiveWorkDir ?? '';
      _log.i('使用工作目录: $workDir');
      
      RustLib.instance.api.localp2PFfiBridgeP2PInit(
        deviceName: config.deviceName,
        workDir: workDir,
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
  /// 1. 检查 Rust 服务是否还在运行
  /// 2. 如果服务停止，自动重启
  /// 3. 重新订阅事件流（确保能接收日志）
  /// 4. 触发刷新（重新广播 + 重新发现 + 重新连接）
  Future<void> resumeEventStream() async {
    _log.i('resumeEventStream: 应用恢复，检查 P2P 服务状态...');

    // 1. 先检查 Rust 服务是否还在运行
    if (!_isRustRunning()) {
      _log.w('Rust 服务已停止，尝试自动重启...');
      debugPrint('⚠️ Rust 服务已停止，尝试自动重启...');

      if (_savedConfig == null) {
        _log.e('无法重启：未保存初始化配置');
        debugPrint('✗ 无法重启：未保存初始化配置');
        _initialized = false;
        return;
      }

      try {
        // 重新初始化和启动
        await _restartService();
        _log.i('Rust 服务重启成功');
        debugPrint('✓ Rust 服务重启成功');
      } catch (e, stackTrace) {
        _log.e('Rust 服务重启失败: $e', e, stackTrace);
        debugPrint('✗ Rust 服务重启失败: $e');
        _initialized = false;
        return;
      }
    } else {
      _log.i('Rust 服务正在运行，继续恢复流程');
    }

    if (!_initialized) {
      _log.w('resumeEventStream 但未初始化');
      return;
    }

    // 2. 重新订阅 Stream（确保能接收日志）
    _log.i('重启事件 Stream 订阅');
    _restartEventStream();

    // 3. 触发刷新（和刷新按钮一样的逻辑）
    _log.i('从后台恢复，触发 P2P 刷新');
    debugPrint('从后台恢复，触发 P2P 刷新...');

    try {
      RustLib.instance.api.localp2PFfiBridgeP2PTriggerRefresh();
      _log.i('P2P 刷新触发成功');
      debugPrint('✓ P2P 刷新触发成功');
    } catch (e, stackTrace) {
      _log.e('触发 P2P 刷新失败: $e', e, stackTrace);
      debugPrint('✗ 触发 P2P 刷新失败: $e');
    }
  }

  /// 重启 P2P 服务（内部方法）
  Future<void> _restartService() async {
    _log.i('重启 P2P 服务...');

    // 取消旧的事件流
    _eventStreamSubscription?.cancel();
    _eventStreamSubscription = null;
    _initialized = false;

    // 重新初始化
    await init(_savedConfig!);

    // 重新启动
    await start();
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
      // ⚠️ 关键修复：先订阅事件流，再调用 start()
      // 这样才能收到 start() 执行期间的日志
      _startEventStream();

      RustLib.instance.api.localp2PFfiBridgeP2PStart();
      _log.rustReturn('start', result: 'started');
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
          // 转发到 EventBus
          P2PEventBus.instance.emit(
            peerId: peerId,
            type: 'discovery',
            data: {'stage': 'discovered'},
          );
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
          // 转发到 EventBus - 节点上线
          P2PEventBus.instance.emit(
            peerId: peerId,
            type: 'online',
            data: {'displayName': displayName},
          );
        } else {
          _log.w('NodeVerified 事件但无法解析: ${event.data}');
        }
        break;

      case 4: // NodeOffline
        final peerId = _extractPeerId(event.data);
        if (peerId != null) {
          _log.node('offline', peerId);
          _eventController.add(NodeOfflineEvent(peerId));
          // 转发到 EventBus
          P2PEventBus.instance.emit(peerId: peerId, type: 'offline');
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

          // 检查状态是否为离线
          final isOffline =
              status != null &&
              (status.toLowerCase() == '离线' ||
                  status.toLowerCase() == 'offline');

          // 转发到 EventBus - 如果不是离线，发送 online 事件
          if (!isOffline) {
            P2PEventBus.instance.emit(
              peerId: peerId,
              type: 'online',
              data: {
                'deviceName': deviceName,
                'nickname': nickname,
                'status': status,
                'avatarUrl': avatarUrl,
              },
            );
          }

          // 转发到 EventBus - 设备信息变更
          P2PEventBus.instance.emit(
            peerId: peerId,
            type: 'info_changed',
            data: {
              'deviceName': deviceName,
              'nickname': nickname,
              'status': status,
              'avatarUrl': avatarUrl,
            },
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
          // 转发到 EventBus
          P2PEventBus.instance.emit(
            peerId: from,
            type: 'message',
            data: {
              'text': content,
              'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
              'isFromMe': false,
            },
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
          // 转发到 EventBus
          P2PEventBus.instance.emit(
            peerId: to,
            type: 'message_sent',
            data: {
              'messageId': messageId,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
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
          // 转发到 EventBus
          P2PEventBus.instance.emit(
            peerId: from,
            type: 'typing',
            data: {'isTyping': isTyping},
          );
        } else {
          _log.w('PeerTyping 事件但无法解析: ${event.data}');
        }
        break;

      case 10: // CONNECTION_STARTED (原 MDNS_STARTED)
        _log.i('📡 连接服务启动事件: ${event.data}');
        _handleConnectionStarted(event.data);
        break;

      case 11: // SERVICE_STATUS
        _log.i('📊 服务状态变化: ${event.data}');
        _handleServiceStatusChanged(event.data);
        break;

      case 12: // SERVICE_READY
        _log.i('🎉 所有服务启动完成: ${event.data}');
        _handleServiceReady(event.data);
        break;

      // ⚠️ case 9 (Rust 日志) 已移除 - Rust 日志现在直接写入文件
      // 不再通过 FRB 桥接传递

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
      case 'CONNECTION_STARTED':
        // 📡 特殊处理：连接服务启动事件（异步执行）
        unawaited(_handleConnectionStarted(message));
        logService.i('[$target] $message');
        break;
      case 'SERVICE_STATUS':
        // 🔥 特殊处理：服务状态变化事件
        _handleServiceStatusChanged(message);
        logService.i('[$target] $message');
        break;
      default:
        logService.i('[$target] $message');
    }

    // 同时输出到控制台（方便调试）
    debugPrint('🔶 [$level] $target: $message');
  }

  /// 🔥 处理服务状态变化事件
  void _handleServiceStatusChanged(String message) {
    _log.i('📊 收到服务状态变化事件');

    try {
      final data = _parseJsonOrNull(message);
      if (data == null) {
        _log.e('无法解析服务状态数据: $message');
        return;
      }

      final service = data['service'] as String?;
      if (service == null) {
        _log.e('服务状态数据缺少 service 字段: $message');
        return;
      }

      // 发送服务状态变化事件到事件流
      _eventController.add(
        ServiceStatusChangedEvent(
          service: service,
          status: ServiceStatusData.fromJson(data),
        ),
      );

      _log.d('服务状态变化: $service -> ${data['health']}');
    } catch (e, stackTrace) {
      _log.e('处理服务状态事件失败: $e', e, stackTrace);
    }
  }

  /// 处理连接服务启动事件（启动 Flutter mDNS 服务）
  ///
  /// Rust 端连接服务启动后，Flutter 端需要：
  /// 1. 启动 mDNS 广播（让其他设备能发现本设备）
  /// 2. 启动 mDNS 设备浏览（发现网络中的其他设备）
  /// 3. 将发现的设备发送给 Rust 端进行连接
  /// 4. 发送 mDNS 服务状态到 UI（更新服务卡片）
  Future<void> _handleConnectionStarted(String message) async {
    _log.i('📡 [mDNS] 收到连接服务启动事件，启动 Flutter mDNS 服务');
    _log.i('📡 [mDNS] 原始消息: $message');

    try {
      // 解析 JSON 数据
      // 格式：{"local_peer_id":"...","device_name":"...","port":12345,"service_type":"...","addresses":[...]}
      final data = _parseJsonOrNull(message);
      if (data == null) {
        _log.e('❌ [mDNS] 无法解析连接服务启动数据: $message');
        return;
      }

      _log.i('✅ [mDNS] JSON 解析成功: $data');

      final localPeerId = data['local_peer_id'] as String? ?? '';
      final deviceName = data['device_name'] as String? ?? '';
      final port = data['port'] as int? ?? 0;
      final serviceType = data['service_type'] as String? ?? '';
      final addresses = data['addresses'] as List<dynamic>?;

      _log.i('📋 [mDNS] 参数解析:');
      _log.i('  - Peer ID: $localPeerId');
      _log.i('  - Device Name: $deviceName');
      _log.i('  - Port: $port');
      _log.i('  - Service Type: $serviceType');
      _log.i('  - Addresses: $addresses');

      // ⭐ 启动完整的 Flutter mDNS 服务（广播 + 浏览）
      _log.i('🚀 [mDNS] 启动 Flutter mDNS 完整服务（广播 + 浏览）...');
      await _startFlutterMdns(
        name: localPeerId,
        port: port,
        serviceType: serviceType,
      );
      _log.i('✅ [mDNS] Flutter mDNS 服务启动完成');
      _log.i('📡 [mDNS] Flutter 负责 mDNS（广播 + 浏览），Rust 负责连接');

      // ⭐ 同时启动 Rust 端的 mDNS 浏览服务，确保设备发现正常工作
      _log.i('🔄 [mDNS] 启动 Rust 端 mDNS 浏览服务...');
      await restartDiscovery();
      _log.i('✅ [mDNS] Rust 端 mDNS 浏览服务启动完成');

      // ⚠️ 注意：服务状态由 _startFlutterMdns 在服务启动后发送
    } catch (e, stackTrace) {
      _log.e('❌ [mDNS] 处理连接服务启动事件失败: $e', e, stackTrace);
    }
  }

  /// 启动 Flutter mDNS 辅助服务
  Future<void> _startFlutterMdns({
    required String name,
    required int port,
    required String serviceType,
  }) async {
    _log.i('[Flutter mDNS] 启动辅助服务: $name@$port ($serviceType)');

    try {
      final mdnsService = FlutterMdnsService.instance;

      // 如果已经在运行，先停止
      if (mdnsService.isRunning) {
        _log.d('[Flutter mDNS] 服务已在运行，先停止');
        await mdnsService.stop();
      }

      // 启动完整的 mDNS 服务（注册 + 浏览）
      final success = await mdnsService.start(
        name: name,
        port: port,
        serviceType: serviceType,
        onDeviceFound: (service) {
          _log.i('[Flutter mDNS] 发现设备: ${service.name}');
          _handleFlutterMdnsDiscovery(service);
        },
        onDeviceLost: (peerId) {
          _log.i('[Flutter mDNS] 设备离线: $peerId');
          _handleFlutterMdnsDeviceLost(peerId);
        },
      );

      // ⭐ 发送 mDNS 服务状态到 UI（更新服务卡片）
      // 在服务真正启动后发送状态，确保状态准确
      _sendMdnsServiceStatusToFlutter(isRunning: success);

      if (success) {
        _log.i('[Flutter mDNS] 辅助服务启动成功');
      } else {
        _log.e('[Flutter mDNS] 辅助服务启动失败');
      }
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 启动失败: $e', e, stackTrace);
      // 启动失败时发送失败状态
      _sendMdnsServiceStatusToFlutter(isRunning: false);
    }
  }

  /// 仅启动 Flutter mDNS 广播（注册服务，不浏览设备）
  ///
  /// 用途：
  /// - 当 Rust 端已经处理 mDNS 设备浏览时，Flutter 只需要辅助广播
  /// - 避免重复的设备浏览（Rust 和 Flutter 都在浏览会产生重复）
  Future<void> _startFlutterMdnsBroadcastOnly({
    required String name,
    required int port,
    required String serviceType,
  }) async {
    _log.i('[Flutter mDNS] 启动辅助广播服务（仅广播，不浏览）');
    _log.i('[Flutter mDNS] Peer ID: $name, Port: $port, Service: $serviceType');

    try {
      final mdnsService = FlutterMdnsService.instance;

      // 如果已经在运行，先停止
      if (mdnsService.isRunning) {
        _log.d('[Flutter mDNS] 服务已在运行，先停止');
        await mdnsService.stop();
      }

      _log.d('[Flutter mDNS] 准备调用 registerService...');

      // ⭐ 只注册服务（发送广播），不浏览（不接收设备）
      final success = await mdnsService.registerService(
        name: name,
        port: port,
        serviceType: serviceType,
      );

      _log.d('[Flutter mDNS] registerService 返回: $success');

      if (success) {
        _log.i('[Flutter mDNS] ✓ 广播注册成功');
        _log.i('[Flutter mDNS] Rust 端将负责设备浏览和连接');
        debugPrint('✓ [Flutter mDNS] 广播注册成功');
      } else {
        _log.e('[Flutter mDNS] ✗ 广播注册失败');
        debugPrint('✗ [Flutter mDNS] 广播注册失败');
      }
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 启动失败: $e', e, stackTrace);
    }
  }

  /// 验证 Peer ID 格式是否有效
  ///
  /// libp2p Peer ID 应该：
  /// - 不为空
  /// - 以标准前缀 "12D3KooW" 开头（Identity V0）
  /// - 只包含 Base58 字符（不含空格、0、O、I、l 等）
  bool _isValidPeerId(String peerId) {
    if (peerId.isEmpty) return false;

    // 基本检查：不包含空格
    if (peerId.contains(' ')) {
      return false;
    }

    // 检查标准前缀（libp2p Identity V0）
    if (!peerId.startsWith('12D3KooW')) {
      return false;
    }

    // 检查长度（libp2p Peer ID 通常是 50+ 字符）
    if (peerId.length < 20) {
      return false;
    }

    // Base58 字符集（排除容易混淆的字符）
    final base58Chars = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    if (!base58Chars.hasMatch(peerId)) {
      return false;
    }

    return true;
  }

  /// 处理 Flutter mDNS 发现的设备
  void _handleFlutterMdnsDiscovery(Service service) {
    try {
      // nsd 的 Service 对象包含:
      // - name (服务名称/Peer ID)
      // - host (主机名)
      // - port
      // - addresses (IP 地址列表 InternetAddress)
      final name = service.name ?? '';
      final host = service.host ?? '';
      final port = service.port ?? 0;
      final addresses = service.addresses;

      _log.i(
        '[Flutter mDNS] 发现设备: name=$name, host=$host, port=$port, addresses=$addresses',
      );

      // ⭐ 过滤：跳过自己的 Peer ID
      // 因为 Rust 端仍在广播，Flutter mDNS 会收到自己的广播
      final localPeerId = getLocalPeerId();
      if (name == localPeerId) {
        _log.d('[Flutter mDNS] 跳过自己的广播: $name');
        return;
      }

      // ⭐ 验证 Peer ID 格式
      // libp2p Peer ID 应该是 Base58 编码，不包含空格等特殊字符
      // 标准前缀是 12D3KooW
      if (!_isValidPeerId(name)) {
        _log.w('[Flutter mDNS] 跳过无效的 Peer ID: "$name" (包含非法字符或格式不正确)');
        return;
      }

      // ⭐ 构造 multiaddr 格式
      String? address;

      // 优先使用 addresses 列表（包含 IPv4 和 IPv6 地址）
      if (addresses != null && addresses.isNotEmpty) {
        // 首先尝试找 IPv4 地址（优先）
        for (var addr in addresses) {
          final ip = addr.address;
          _log.d('[Flutter mDNS] 检查地址: $ip');

          // 跳过 localhost 和回环地址
          if (ip == '127.0.0.1' || ip == '::1') {
            continue;
          }

          // 简单判断 IPv4（不包含冒号）vs IPv6（包含冒号）
          if (!ip.contains(':')) {
            address = '/ip4/$ip/tcp/$port';
            _log.i('[Flutter mDNS] 使用 IPv4 地址: $address');
            break; // 找到 IPv4，直接使用
          }
        }

        // 如果没有找到 IPv4，尝试使用 IPv6
        if (address == null) {
          for (var addr in addresses) {
            final ip = addr.address;
            _log.d('[Flutter mDNS] 检查 IPv6 地址: $ip');

            // 跳过 localhost 和回环地址
            if (ip == '::1' || ip.startsWith('fe80:')) {
              continue;
            }

            // 使用 IPv6
            if (ip.contains(':')) {
              address = '/ip6/$ip/tcp/$port';
              _log.i('[Flutter mDNS] 使用 IPv6 地址: $address');
              break;
            }
          }
        }
      }

      // 如果没有找到地址，尝试使用 host
      if (address == null && host.isNotEmpty && host != 'localhost') {
        // 简单的 IPv4/IPv6 判断
        if (host.contains(':')) {
          address = '/ip6/$host/tcp/$port';
          _log.d('[Flutter mDNS] 使用 host (IPv6): $address');
        } else {
          address = '/ip4/$host/tcp/$port';
          _log.d('[Flutter mDNS] 使用 host (IPv4): $address');
        }
      }

      // 如果仍然没有有效地址，记录警告
      if (address == null) {
        _log.w('[Flutter mDNS] 未获取到有效 IP 地址，跳过此设备');
        return;
      }

      // ⭐ 调用 Rust 端的接口，让 Rust 去连接
      _log.i('[Flutter mDNS] 通知 Rust 端连接到: $name at $address');

      try {
        // 调用生成的 FRB 函数（在 third_party/localp2p_ffi/bridge.dart 中定义）
        frb_bridge.p2PReportExternalDiscovery(peerId: name, address: address);
        _log.i('[Flutter mDNS] 已通知 Rust 端');
      } catch (e, stackTrace) {
        _log.e('[Flutter mDNS] 通知 Rust 失败: $e', e, stackTrace);
      }

      debugPrint('[Flutter mDNS] 发现设备: $name at $address');
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 处理发现事件失败: $e', e, stackTrace);
    }
  }

  /// 处理 Flutter mDNS 设备离线
  void _handleFlutterMdnsDeviceLost(String peerId) {
    try {
      _log.i('[Flutter mDNS] 设备离线: $peerId');

      // ⭐ 过滤：跳过自己的 Peer ID
      final localPeerId = getLocalPeerId();
      if (peerId == localPeerId) {
        _log.d('[Flutter mDNS] 跳过自己的离线事件: $peerId');
        return;
      }

      // ⭐ 通知 Rust 端设备离线
      _log.i('[Flutter mDNS] 通知 Rust 端设备离线: $peerId');

      try {
        // 调用生成的 FRB 函数（在 third_party/localp2p_ffi/bridge.dart 中定义）
        frb_bridge.p2PReportExternalDeviceLost(peerId: peerId);
        _log.i('[Flutter mDNS] 已通知 Rust 端设备离线');
      } catch (e, stackTrace) {
        _log.e('[Flutter mDNS] 通知 Rust 设备离线失败: $e', e, stackTrace);
      }

      debugPrint('[Flutter mDNS] 设备离线: $peerId');
    } catch (e, stackTrace) {
      _log.e('[Flutter mDNS] 处理离线事件失败: $e', e, stackTrace);
    }
  }

  /// 📡 发送 mDNS 服务状态到 Flutter UI（更新服务卡片）
  ///
  /// 此函数向事件流发送 mDNS 服务状态变化事件，
  /// UI 层会监听此事件并更新 mDNS 服务卡片的状态显示
  void _sendMdnsServiceStatusToFlutter({required bool isRunning}) {
    _log.i('📊 [mDNS] 发送 mDNS 服务状态到 UI: running=$isRunning');

    try {
      // 构造服务状态数据
      final statusData = ServiceStatusData(
        name: 'mDNS',
        health: isRunning ? 'healthy' : 'unhealthy',
        isRunning: isRunning,
        message: isRunning ? 'Flutter mDNS 服务运行中' : 'Flutter mDNS 服务未运行',
      );

      // 发送服务状态变化事件
      _eventController.add(
        ServiceStatusChangedEvent(
          service: 'mDNS',
          status: statusData,
        ),
      );

      _log.i('✅ [mDNS] 服务状态已发送到 UI');
    } catch (e, stackTrace) {
      _log.e('[mDNS] 发送服务状态失败: $e', e, stackTrace);
    }
  }

  /// 🔥 处理 Rust 端发送的服务启动完成事件
  ///
  /// 当 Rust 连接服务启动完成后，Rust 会发送 SERVICE_READY 事件
  /// Flutter 收到此事件后，通过 EventBus 广播给所有订阅者
  ///
  /// 使用示例：
  /// ```dart
  /// P2PEventBus.instance.onServiceReady.listen((event) {
  ///   // 服务已完全启动，可以安全地调用依赖服务的功能
  ///   print('All services ready!');
  /// });
  /// ```
  void _handleServiceReady(String message) {
    _log.i('🎉 [Service] 处理服务启动完成事件');

    try {
      // 解析 Rust 事件数据
      final data = _parseJsonOrNull(message);
      if (data == null) {
        _log.w('[Service] 无法解析服务启动完成事件: $message');
        return;
      }

      // 通过 EventBus 发送服务启动完成事件
      P2PEventBus.instance.emit(
        peerId: '_system_',
        type: 'service_ready',
        data: {
          'timestamp': DateTime.now().toIso8601String(),
          'local_peer_id': data['local_peer_id'],
          'device_name': data['device_name'],
          'port': data['port'],
          'addresses': data['addresses'],
          'services': {
            'connection': true, // Rust 连接服务已启动
            // 注意：mDNS 服务状态由 Flutter 端单独管理
          },
          'message': '所有服务已完全启动',
        },
      );

      _log.i('✅ [Service] 服务启动完成事件已发送到 EventBus');
    } catch (e, stackTrace) {
      _log.e('[Service] 处理服务启动完成事件失败: $e', e, stackTrace);
    }
  }

  /// 安全解析 JSON（返回 null 而不是抛出异常）
  Map<String, dynamic>? _parseJsonOrNull(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      // 尝试处理嵌套格式（如果日志有额外的包装）
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (e) {
      // 尝试从日志消息中提取 JSON 部分
      // 格式可能是：[INFO] [mdns] {"key":"value"}
      final jsonMatch = RegExp(r'\{[^}]*\}').firstMatch(jsonString);
      if (jsonMatch != null) {
        try {
          final decoded = jsonDecode(jsonMatch.group(0)!);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {
          // 忽略
        }
      }
      return null;
    }
  }

  /// ⚠️ 已移除 _extractLogLevel - Rust 日志不再通过 FRB 桥接传递
  /// ⚠️ 已移除 _extractLogTarget - Rust 日志不再通过 FRB 桥接传递
  /// ⚠️ 已移除 _extractLogMessage - Rust 日志不再通过 FRB 桥接传递

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

  /// 🔥 获取本地 Peer ID（异步版本，避免阻塞 UI）
  Future<String> getLocalPeerIdAsync() async {
    if (!_initialized) {
      _log.e('getLocalPeerIdAsync 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取本地 Peer ID (异步)');
    final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetLocalPeerIdAsync();
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
  List<bridge.P2PBridgeNodeInfo> getVerifiedNodes() {
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
  ///
  /// 🔄 改为异步：使用 async/await 避免阻塞 UI
  Future<void> sendMessage(String targetPeerId, String message) async {
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
  ///
  /// 🔄 改为异步：使用 async/await 避免阻塞 UI
  Future<void> broadcastMessage(
    List<String> targetPeerIds,
    String message,
  ) async {
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
  bridge.P2PBridgeNodeInfo? getUserInfo(String peerId) {
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

  /// 主动触发刷新
  ///
  /// 触发 mDNS 重新广播和重新发现，并尝试重新连接到所有已知节点
  ///
  /// 🔄 改为异步：避免阻塞 UI
  Future<void> triggerRefresh() async {
    if (!_initialized) {
      _log.e('triggerRefresh 但未初始化');
      throw Exception('Not initialized');
    }

    _log.i('主动触发刷新');
    _log.rustCall('triggerRefresh');

    try {
      await RustLib.instance.api.localp2PFfiBridgeP2PTriggerRefreshAsync();
      _log.rustReturn('triggerRefresh', result: 'refreshed');
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PTriggerRefreshAsync', e, stackTrace);
      rethrow;
    }
  }

  /// 🔥 重启 mDNS 浏览服务
  ///
  /// 只重启 mDNS 部分，不影响 TCP 连接
  /// 适用于从后台恢复时，确保 mDNS 浏览服务正常工作
  Future<void> restartDiscovery() async {
    if (!_initialized) {
      _log.e('restartDiscovery 但未初始化');
      throw Exception('Not initialized');
    }

    _log.i('🔄 重启 mDNS 浏览服务');
    _log.rustCall('restartDiscovery');

    try {
      await RustLib.instance.api.localp2PFfiBridgeP2PRestartDiscovery();
      _log.rustReturn('restartDiscovery', result: 'restarted');
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PRestartDiscovery', e, stackTrace);
      rethrow;
    }
  }

  /// 🔥 获取系统状态
  ///
  /// 返回当前所有服务的运行状态和健康状态
  SystemStatusJson getSystemStatus() {
    if (!_initialized) {
      _log.e('getSystemStatus 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取系统状态');

    try {
      final result = RustLib.instance.api.localp2PFfiBridgeP2PGetSystemStatus();
      _log.d(
        '系统状态: mDNS=${result.mdnsService.health}, Connection=${result.connectionService.health}',
      );
      // 转换 bridge 类型为本地类型（BigInt -> int）
      return SystemStatusJson.fromBridge(result);
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PGetSystemStatus', e, stackTrace);
      rethrow;
    }
  }

  /// 🔥 获取系统状态（异步版本，避免阻塞 UI）
  ///
  /// 返回当前所有服务的运行状态和健康状态
  Future<SystemStatusJson> getSystemStatusAsync() async {
    if (!_initialized) {
      _log.e('getSystemStatusAsync 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取系统状态 (异步)');

    try {
      final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetSystemStatusAsync();
      _log.d(
        '系统状态: mDNS=${result.mdnsService.health}, Connection=${result.connectionService.health}',
      );
      // 转换 bridge 类型为本地类型（BigInt -> int）
      return SystemStatusJson.fromBridge(result);
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PGetSystemStatusAsync', e, stackTrace);
      rethrow;
    }
  }

  /// 🔥 获取广播信息
  ///
  /// 返回当前设备的广播信息（Peer ID、设备名称、监听端口、IP 地址列表）
  ///
  /// 🔄 改为异步：避免锁竞争导致 UI 卡顿
  Future<bridge.BroadcastInfoJson> getBroadcastInfo() async {
    if (!_initialized) {
      _log.e('getBroadcastInfo 但未初始化');
      throw Exception('Not initialized');
    }

    _log.t('获取广播信息');

    try {
      final result = await RustLib.instance.api.localp2PFfiBridgeP2PGetBroadcastInfo();
      _log.d(
        '广播信息: peerId=${result.peerId}, deviceName=${result.deviceName}, port=${result.port}',
      );
      return result;
    } catch (e, stackTrace) {
      _log.rustError('localp2PFfiBridgeP2PGetBroadcastInfo', e, stackTrace);
      rethrow;
    }
  }
}

// Type aliases for bridge types (for backward compatibility)
typedef ServiceHealthJson = bridge.ServiceHealthJson;
typedef ServiceStatusJson = bridge.ServiceStatusJson;
typedef P2PBridgeEvent = bridge.P2PBridgeEvent;
// Note: P2PBridgeNodeInfo is not aliased to avoid conflicts with direct imports
// BroadcastInfoJson is used directly from bridge.dart

/// 🔥 系统状态（包装器，将 BigInt 转换为 int）
class SystemStatusJson {
  final ServiceStatusJson mdnsService;
  final ServiceStatusJson connectionService;
  final int connectedPeers;
  final int discoveredPeers;

  SystemStatusJson({
    required this.mdnsService,
    required this.connectionService,
    required this.connectedPeers,
    required this.discoveredPeers,
  });

  /// 从 bridge 的 SystemStatusJson 转换
  factory SystemStatusJson.fromBridge(bridge.SystemStatusJson bridge) {
    return SystemStatusJson(
      mdnsService: bridge.mdnsService,
      connectionService: bridge.connectionService,
      connectedPeers: bridge.connectedPeers.toInt(),
      discoveredPeers: bridge.discoveredPeers.toInt(),
    );
  }

  /// 判断系统是否健康
  bool get isHealthy {
    return mdnsService.isRunning &&
        connectionService.isRunning &&
        mdnsService.health == ServiceHealthJson.healthy &&
        connectionService.health == ServiceHealthJson.healthy;
  }
}
