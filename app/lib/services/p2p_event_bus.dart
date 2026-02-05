import 'dart:async';
import 'package:logger/logger.dart';

/// P2P 事件（通用）
class P2PEvent {
  final String peerId;
  final String type;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  P2PEvent({
    required this.peerId,
    required this.type,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  T getData<T>(String key, [T? defaultValue]) {
    if (data == null) return defaultValue as T;
    if (!data!.containsKey(key)) return defaultValue as T;
    return data![key] as T;
  }

  bool hasData(String key) => data?.containsKey(key) ?? false;

  @override
  String toString() =>
      'P2PEvent(peerId: $peerId, type: $type, data: $data, timestamp: $timestamp)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is P2PEvent &&
          other.peerId == peerId &&
          other.type == type &&
          other.timestamp == timestamp);

  @override
  int get hashCode => peerId.hashCode ^ type.hashCode ^ timestamp.hashCode;
}

/// 增强的 StreamSubscription，带当前状态查询
class P2PEventSubscription<T> {
  final StreamSubscription<T> _subscription;
  final String? _peerId;
  final String? _type;
  final P2PEventBus _eventBus;

  P2PEventSubscription(
    this._subscription,
    this._peerId,
    this._type,
    this._eventBus,
  );

  /// 获取当前状态（缓存值）
  T? get currentState {
    if (_peerId != null && _type != null) {
      // 返回该 peerId 的该类型最新事件的 data
      final event = _eventBus.getLatestEvent(_peerId, _type);
      return event as T?;
    }
    if (_peerId != null) {
      // 返回该 peerId 的最新事件
      final event = _eventBus.getLatestEventByPeer(_peerId);
      return event as T?;
    }
    return null;
  }

  /// 获取当前状态的数据
  Map<String, dynamic>? get currentData {
    final event = currentState as P2PEvent?;
    return event?.data;
  }

  /// 检查当前是否在线
  bool get isOnline {
    // 🔥 使用 EventBus 的独立状态缓存（不依赖 currentData）
    if (_peerId == null) return false;
    return _eventBus.isOnline(_peerId);
  }

  Future<void> cancel() => _subscription.cancel();

  Future<E> asFuture<E>([E? futureValue]) =>
      _subscription.asFuture(futureValue);

  void onData(void Function(T)? handleData) => _subscription.onData(handleData);

  void onError(Function? handleError) => _subscription.onError(handleError);

  void onDone(void Function()? handleDone) => _subscription.onDone(handleDone);
}

/// P2P 状态缓存
class _P2PStateCache {
  final Map<String, P2PEvent> _latestByPeer = {};
  final Map<String, P2PEvent> _latestByPeerAndType = {};

  /// 🔥 单独缓存用户在线状态（不被消息事件覆盖）
  final Map<String, String?> _userStatus = {};

  void update(String peerId, String type, P2PEvent event) {
    _latestByPeer[peerId] = event;
    _latestByPeerAndType['$peerId:$type'] = event;

    // 🔥 如果是状态相关事件（online/offline/info_changed），单独缓存 status
    if (type == 'online' || type == 'offline' || type == 'info_changed') {
      if (event.data?.containsKey('status') == true) {
        final status = event.data!['status'];
        if (status is String) {
          _userStatus[peerId] = status;
        }
      }
    }
  }

  P2PEvent? getByPeer(String peerId) => _latestByPeer[peerId];

  P2PEvent? getByPeerAndType(String peerId, String type) =>
      _latestByPeerAndType['$peerId:$type'];

  /// 🔥 获取缓存的用户在线状态（独立于事件缓存）
  String getUserStatus(String peerId) => _userStatus[peerId] ?? '';

  void removePeer(String peerId) {
    _latestByPeer.remove(peerId);
    _latestByPeerAndType.removeWhere(
      (key, value) => key.startsWith('$peerId:'),
    );
    _userStatus.remove(peerId);
  }

  Map<String, dynamic> toJson() => {
    'byPeer': _latestByPeer.map((k, v) => MapEntry(k, v.toString())),
    'byPeerAndType': _latestByPeerAndType.map(
      (k, v) => MapEntry(k, v.toString()),
    ),
  };
}

/// 增强的 P2P 事件总线（带状态缓存）
class P2PEventBus {
  P2PEventBus._() {
    // 监听全局事件流，更新缓存
    stream.listen((event) {
      _cache.update(event.peerId, event.type, event);
    });
  }

  static P2PEventBus? _instance;
  static P2PEventBus get instance => _instance ??= P2PEventBus._();

  final Logger _log = Logger();
  final _cache = _P2PStateCache();
  final StreamController<P2PEvent> _controller =
      StreamController<P2PEvent>.broadcast();

  /// 全局事件流
  Stream<P2PEvent> get stream => _controller.stream;

  /// 发送事件
  void emit({
    required String peerId,
    required String type,
    Map<String, dynamic>? data,
  }) {
    final event = P2PEvent(peerId: peerId, type: type, data: data);
    _log.i('[EventBus] 🔥 Emitting: peerId=$peerId, type=$type');
    _controller.add(event);
  }

  void emitEvent(P2PEvent event) {
    _log.d('[EventBus] Emitting: $event');
    _controller.add(event);
  }

  /// 获取指定 peerId 和类型的最新事件
  P2PEvent? getLatestEvent(String peerId, String type) {
    return _cache.getByPeerAndType(peerId, type);
  }

  /// 获取指定 peerId 的最新事件
  P2PEvent? getLatestEventByPeer(String peerId) {
    return _cache.getByPeer(peerId);
  }

  /// 获取指定 peerId 的当前状态数据
  Map<String, dynamic>? getCurrentData(String peerId) {
    return getLatestEventByPeer(peerId)?.data;
  }

  /// 检查指定 peerId 是否在线
  bool isOnline(String peerId) {
    // 🔥 优先使用独立的状态缓存（不会被消息事件污染）
    final userStatus = _cache.getUserStatus(peerId);
    if (userStatus.isNotEmpty) {
      final statusLower = userStatus.toLowerCase();
      return statusLower != '离线' && statusLower != 'offline';
    }

    // 回退到事件缓存检查
    final event = getLatestEventByPeer(peerId);
    if (event == null) return false;
    if (event.type == 'offline') return false;

    return true;
  }

  /// 监听事件（支持多条件过滤）
  Stream<P2PEvent> on({String? peerId, String? type}) {
    return _controller.stream.where((e) {
      if (peerId != null && e.peerId != peerId) return false;
      if (type != null && e.type != type) return false;
      return true;
    });
  }

  /// 监听并自动获取当前状态（BehaviorSubject 模式）
  ///
  /// 新订阅者会立即收到当前状态，然后继续监听新事件
  ///
  /// ```dart
  /// final sub = P2PEventBus.instance.onWithLatest(
  ///   peerId: '12D3...abc',
  ///   type: 'message',
  /// ).listen((event) {
  ///   print('Message: ${event.data?['text']}');
  /// });
  ///
  /// // 获取当前状态
  /// print('Current: ${sub.currentState}');
  /// print('Is online: ${sub.isOnline}');
  /// ```
  P2PEventSubscription<P2PEvent> onWithLatest({String? peerId, String? type}) {
    // 创建流：先发送当前状态，然后发送新事件
    final latestEvent = (peerId != null && type != null)
        ? getLatestEvent(peerId, type)
        : (peerId != null)
        ? getLatestEventByPeer(peerId)
        : null;

    final baseStream = on(peerId: peerId, type: type);

    // 使用 async* 生成器创建流
    final stream = Stream<P2PEvent>.multi((controller) {
      if (latestEvent != null) {
        controller.add(latestEvent);
      }
      // 将后续事件转发到控制器
      baseStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    });

    final subscription = stream.listen(null);

    return P2PEventSubscription<P2PEvent>(subscription, peerId, type, this);
  }

  /// 监听并自动处理（带回调）
  P2PEventSubscription<P2PEvent> subscribe({
    String? peerId,
    String? type,
    required void Function(P2PEvent) onData,
    Function? errorCallback,
    void Function()? onDone,
  }) {
    final subscriptionWrapper = onWithLatest(peerId: peerId, type: type);
    subscriptionWrapper.onData(onData);
    if (errorCallback != null) subscriptionWrapper.onError(errorCallback);
    if (onDone != null) subscriptionWrapper.onDone(onDone);
    return subscriptionWrapper;
  }

  /// 合并多个 peerId 的同类事件
  ///
  /// ```dart
  /// P2PEventBus.instance.mergePeers(
  ///   peerIds: ['12D3...abc', '12D3...def'],
  ///   type: 'message',
  /// ).listen((events) {
  ///   // events 是所有 peerId 最新事件的列表
  ///   for (final event in events) {
  ///     print('${event.peerId}: ${event.data}');
  ///   }
  /// });
  /// ```
  Stream<List<P2PEvent>> mergePeers({
    required List<String> peerIds,
    required String type,
  }) {
    final streams = peerIds.map((peerId) => on(peerId: peerId, type: type));
    return _mergeStreams(streams.toList());
  }

  /// 合并多个事件类型
  Stream<List<P2PEvent>> mergeTypes({
    String? peerId,
    required List<String> types,
  }) {
    final streams = types.map((type) => on(peerId: peerId, type: type));
    return _mergeStreams(streams.toList());
  }

  Stream<List<P2PEvent>> _mergeStreams(List<Stream<P2PEvent>> streams) {
    final controller = StreamController<List<P2PEvent>>();
    final subscriptions = <StreamSubscription<P2PEvent>>[];
    final latestEvents = <P2PEvent?>[];
    final receivedCount = <int>[];

    for (var i = 0; i < streams.length; i++) {
      latestEvents.add(null);
      receivedCount.add(0);

      subscriptions.add(
        streams[i].listen((event) {
          latestEvents[i] = event;
          receivedCount[i]++;

          // 当所有流都至少收到一个事件后，发送合并事件
          if (receivedCount.every((count) => count > 0)) {
            controller.add(latestEvents.whereType<P2PEvent>().toList());
          }
        }),
      );
    }

    // 当所有订阅取消时关闭控制器
    Future.wait(subscriptions.map((s) => s.asFuture())).then((_) {
      if (!controller.isClosed) {
        controller.close();
      }
    });

    return controller.stream;
  }

  // ========== 便捷方法 ==========

  Stream<P2PEvent> onPeer(String peerId) => on(peerId: peerId);
  Stream<P2PEvent> onType(String type) => on(type: type);
  Stream<P2PEvent> onWhere(bool Function(P2PEvent) test) =>
      _controller.stream.where(test);

  Stream<P2PEvent> onPeerOnline(String peerId) =>
      on(peerId: peerId, type: 'online');
  Stream<P2PEvent> onPeerOffline(String peerId) =>
      on(peerId: peerId, type: 'offline');
  Stream<P2PEvent> onMessage(String peerId) =>
      on(peerId: peerId, type: 'message');
  Stream<P2PEvent> onTyping(String peerId) =>
      on(peerId: peerId, type: 'typing');
  Stream<P2PEvent> onInfoChanged(String peerId) =>
      on(peerId: peerId, type: 'info_changed');
  Stream<P2PEvent> onNicknameChanged(String peerId) => onInfoChanged(
    peerId,
  ).where((e) => e.getData<String>('field') == 'nickname');
  Stream<P2PEvent> onStatusChanged(String peerId) => onInfoChanged(
    peerId,
  ).where((e) => e.getData<String>('field') == 'status');

  Stream<P2PEvent> get onAnyPeerOnline => onType('online');
  Stream<P2PEvent> get onAnyPeerOffline => onType('offline');
  Stream<P2PEvent> get onAnyMessage => onType('message');
  Stream<P2PEvent> get onAnyTyping => onType('typing');

  // ========== 服务相关事件 ==========

  /// 🔥 监听所有服务启动完成事件
  /// 当 Rust 连接服务和 Flutter mDNS 服务都启动完成后触发
  /// 由于 EventBus 有最后事件缓存，新订阅者会立即收到当前状态
  ///
  /// 使用示例：
  /// ```dart
  /// P2PEventBus.instance.onServiceReady.listen((event) {
  ///   // 服务已完全启动，可以安全地调用依赖服务的功能
  ///   print('All services ready: ${event.data}');
  /// });
  /// ```
  Stream<P2PEvent> get onServiceReady => on(peerId: '_system_', type: 'service_ready');

  Stream<P2PEvent> once({String? peerId, String? type}) =>
      on(peerId: peerId, type: type).take(1);

  /// 移除指定 peerId 的缓存状态
  void removePeer(String peerId) {
    _cache.removePeer(peerId);
    _log.d('[EventBus] Removed peer from cache: $peerId');
  }

  void dispose() {
    _controller.close();
    _log.i('[EventBus] Event bus disposed');
  }
}
