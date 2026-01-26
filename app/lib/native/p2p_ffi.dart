import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// ============================================================
// 类型定义
// ============================================================

/// P2P 错误代码
abstract final class P2PErrorCode {
  static const int success = 0;
  static const int notInitialized = -1;
  static const int invalidArgument = -2;
  static const int sendFailed = -3;
  static const int nodeNotVerified = -4;
  static const int outOfMemory = -5;
  static const int unknown = -99;
}

/// P2P 事件类型
abstract final class P2PEventType {
  static const int nodeDiscovered = 1;
  static const int nodeExpired = 2;
  static const int nodeVerified = 3;
  static const int nodeOffline = 4;
  static const int userInfoReceived = 5;
  static const int messageReceived = 6;
  static const int messageSent = 7;
  static const int peerTyping = 8;
}

/// P2P 句柄
base class P2PHandle extends ffi.Struct {
  @ffi.Int32()
  external int _private;
}

/// P2P 事件数据
base class P2PEventData extends ffi.Struct {
  @ffi.Int32()
  external int eventType;

  external ffi.Pointer<ffi.Char> peerId;
  external ffi.Pointer<ffi.Char> displayName;
  external ffi.Pointer<ffi.Char> message;
  external ffi.Pointer<ffi.Char> messageId;

  @ffi.Bool()
  external bool isTyping;

  @ffi.Int64()
  external int timestamp;

  /// 获取 Peer ID
  String get peerIdString {
    final ptr = peerId;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  /// 获取显示名称
  String get displayNameString {
    final ptr = displayName;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  /// 获取消息内容
  String get messageString {
    final ptr = message;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  /// 获取消息 ID
  String get messageIdString {
    final ptr = messageId;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  /// 获取时间戳
  DateTime get timestampDateTime {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}

/// 节点信息结构
base class NodeInfo extends ffi.Struct {
  external ffi.Pointer<ffi.Char> peerId;
  external ffi.Pointer<ffi.Char> displayName;
  external ffi.Pointer<ffi.Char> deviceName;

  @ffi.Size()
  external int addressCount;

  external ffi.Pointer<ffi.Pointer<ffi.Char>> addresses;
}

/// 节点信息数据类
class NodeInfoData {
  final String peerId;
  final String displayName;
  final String deviceName;

  NodeInfoData({
    required this.peerId,
    required this.displayName,
    required this.deviceName,
  });

  @override
  String toString() => 'NodeInfo(peerId: $peerId, displayName: $displayName, deviceName: $deviceName)';
}

// ============================================================
// P2P 事件
// ============================================================

abstract class P2PEvent {}

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

class UserInfoReceivedEvent extends P2PEvent {
  final String peerId;
  final String displayName;
  UserInfoReceivedEvent(this.peerId, this.displayName);
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

// ============================================================
// 全局事件控制器（用于回调）
// ============================================================

final _globalEventController = StreamController<P2PEvent>.broadcast();

// ============================================================
// FFI 函数签名
// ============================================================

typedef InitNative = P2PHandle Function(ffi.Pointer<ffi.Char> deviceName, ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut);
typedef StartNative = ffi.Int32 Function(P2PHandle handle, ffi.Pointer<ffi.NativeFunction<EventCallbackNative>> callback, ffi.Pointer<ffi.Void> userData);
typedef StopNative = ffi.Int32 Function(P2PHandle handle);
typedef CleanupNative = ffi.Void Function(P2PHandle handle);

typedef GetLocalPeerIdNative = ffi.Int32 Function(P2PHandle handle, ffi.Pointer<ffi.Char> out, ffi.Size outLen);
typedef GetDeviceNameNative = ffi.Int32 Function(P2PHandle handle, ffi.Pointer<ffi.Char> out, ffi.Size outLen);
typedef GetVerifiedNodesNative = ffi.Int32 Function(P2PHandle handle, ffi.Pointer<ffi.Pointer<NodeInfo>> out, ffi.Pointer<ffi.Size> outLen);
typedef FreeNodeListNative = ffi.Void Function(ffi.Pointer<NodeInfo> nodes, ffi.Size len);

typedef SendMessageNative = ffi.Int32 Function(
  P2PHandle handle,
  ffi.Pointer<ffi.Char> targetPeerId,
  ffi.Pointer<ffi.Char> message,
  ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut,
);

typedef BroadcastMessageNative = ffi.Int32 Function(
  P2PHandle handle,
  ffi.Pointer<ffi.Pointer<ffi.Char>> targetPeerIds,
  ffi.Size targetCount,
  ffi.Pointer<ffi.Char> message,
  ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut,
);

typedef FreeErrorNative = ffi.Void Function(ffi.Pointer<ffi.Char> error);

// Dart 类型定义
typedef InitDart = P2PHandle Function(ffi.Pointer<ffi.Char> deviceName, ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut);
typedef StartDart = int Function(P2PHandle handle, ffi.Pointer<ffi.NativeFunction<EventCallbackNative>> callback, ffi.Pointer<ffi.Void> userData);
typedef StopDart = int Function(P2PHandle handle);
typedef CleanupDart = void Function(P2PHandle handle);

typedef GetLocalPeerIdDart = int Function(P2PHandle handle, ffi.Pointer<ffi.Char> out, int outLen);
typedef GetDeviceNameDart = int Function(P2PHandle handle, ffi.Pointer<ffi.Char> out, int outLen);
typedef GetVerifiedNodesDart = int Function(P2PHandle handle, ffi.Pointer<ffi.Pointer<NodeInfo>> out, ffi.Pointer<ffi.Uint64> outLen);
typedef FreeNodeListDart = void Function(ffi.Pointer<NodeInfo> nodes, int len);

typedef SendMessageDart = int Function(
  P2PHandle handle,
  ffi.Pointer<ffi.Char> targetPeerId,
  ffi.Pointer<ffi.Char> message,
  ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut,
);

typedef BroadcastMessageDart = int Function(
  P2PHandle handle,
  ffi.Pointer<ffi.Pointer<ffi.Char>> targetPeerIds,
  int targetCount,
  ffi.Pointer<ffi.Char> message,
  ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut,
);

typedef FreeErrorDart = void Function(ffi.Pointer<ffi.Char> error);

// 回调函数类型
typedef EventCallbackNative = ffi.Void Function(P2PEventData eventData, ffi.Pointer<ffi.Void> userData);

// ============================================================
// P2P Service
// ============================================================

class P2PService {
  final ffi.DynamicLibrary _lib;

  late final InitDart _init;
  late final StartDart _start;
  late final StopDart _stop;
  late final CleanupDart _cleanup;
  late final GetLocalPeerIdDart _getLocalPeerId;
  late final GetDeviceNameDart _getDeviceName;
  late final GetVerifiedNodesDart _getVerifiedNodes;
  late final FreeNodeListDart _freeNodeList;
  late final SendMessageDart _sendMessage;
  late final BroadcastMessageDart _broadcastMessage;
  late final FreeErrorDart _freeError;

  P2PHandle? _handle;
  final _eventController = StreamController<P2PEvent>.broadcast();
  ffi.Pointer<ffi.NativeFunction<EventCallbackNative>>? _callbackPointer;
  StreamSubscription<P2PEvent>? _globalSubscription;

  Stream<P2PEvent> get eventStream => _eventController.stream;

  P2PService(this._lib) {
    // 加载函数
    _init = _lib.lookup<ffi.NativeFunction<InitNative>>('localp2p_init').asFunction();
    _start = _lib.lookup<ffi.NativeFunction<StartNative>>('localp2p_start').asFunction();
    _stop = _lib.lookup<ffi.NativeFunction<StopNative>>('localp2p_stop').asFunction();
    _cleanup = _lib.lookup<ffi.NativeFunction<CleanupNative>>('localp2p_cleanup').asFunction();
    _getLocalPeerId = _lib.lookup<ffi.NativeFunction<GetLocalPeerIdNative>>('localp2p_get_local_peer_id').asFunction();
    _getDeviceName = _lib.lookup<ffi.NativeFunction<GetDeviceNameNative>>('localp2p_get_device_name').asFunction();
    _getVerifiedNodes = _lib.lookup<ffi.NativeFunction<GetVerifiedNodesNative>>('localp2p_get_verified_nodes').asFunction();
    _freeNodeList = _lib.lookup<ffi.NativeFunction<FreeNodeListNative>>('localp2p_free_node_list').asFunction();
    _sendMessage = _lib.lookup<ffi.NativeFunction<SendMessageNative>>('localp2p_send_message').asFunction();
    _broadcastMessage = _lib.lookup<ffi.NativeFunction<BroadcastMessageNative>>('localp2p_broadcast_message').asFunction();
    _freeError = _lib.lookup<ffi.NativeFunction<FreeErrorNative>>('localp2p_free_error').asFunction();

    // 订阅全局事件流
    _globalSubscription = _globalEventController.stream.listen((event) {
      _eventController.add(event);
    });
  }

  /// 初始化 P2P 模块
  bool init(String deviceName) {
    final deviceNameC = deviceName.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();

    try {
      _handle = _init(deviceNameC.cast<ffi.Char>(), errorOut);

      final error = errorOut.value;
      if (error != ffi.nullptr) {
        final errorStr = error.cast<Utf8>().toDartString();
        _freeError(error);
        throw Exception('Init failed: $errorStr');
      }

      return _handle != null;
    } finally {
      calloc.free(deviceNameC);
      calloc.free(errorOut);
    }
  }

  /// 启动 P2P 服务
  bool start() {
    if (_handle == null) {
      throw Exception('Not initialized');
    }

    // 创建回调闭包
    _callbackPointer = ffi.Pointer.fromFunction<EventCallbackNative>(
      _eventCallback,
    );

    return _start(_handle!, _callbackPointer!, ffi.nullptr) == 0;
  }

  /// 停止 P2P 服务
  void stop() {
    if (_handle != null) {
      _stop(_handle!);
    }
  }

  /// 清理资源
  void cleanup() {
    _globalSubscription?.cancel();
    if (_handle != null) {
      _cleanup(_handle!);
      _handle = null;
    }
    _eventController.close();
  }

  /// 获取本地 Peer ID
  String getLocalPeerId() {
    if (_handle == null) throw Exception('Not initialized');

    final out = calloc<ffi.Char>(256);
    try {
      final result = _getLocalPeerId(_handle!, out, 256);
      if (result != 0) {
        throw Exception('Failed to get local peer id');
      }
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// 获取设备名称
  String getDeviceName() {
    if (_handle == null) throw Exception('Not initialized');

    final out = calloc<ffi.Char>(256);
    try {
      final result = _getDeviceName(_handle!, out, 256);
      if (result != 0) {
        throw Exception('Failed to get device name');
      }
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// 获取已验证的节点列表
  List<NodeInfoData> getVerifiedNodes() {
    if (_handle == null) throw Exception('Not initialized');

    final out = calloc<ffi.Pointer<NodeInfo>>();
    final outLen = calloc<ffi.Uint64>();

    try {
      final result = _getVerifiedNodes(_handle!, out, outLen);
      if (result != 0) {
        throw Exception('Failed to get verified nodes');
      }

      final len = outLen.value.toInt();
      final nodes = out.value;
      final resultList = <NodeInfoData>[];

      for (var i = 0; i < len; i++) {
        final node = (nodes + i).ref;
        resultList.add(NodeInfoData(
          peerId: node.peerId.cast<Utf8>().toDartString(),
          displayName: node.displayName.cast<Utf8>().toDartString(),
          deviceName: node.deviceName.cast<Utf8>().toDartString(),
        ));
      }

      _freeNodeList(nodes, len);
      return resultList;
    } finally {
      calloc.free(out);
      calloc.free(outLen);
    }
  }

  /// 发送消息
  bool sendMessage(String targetPeerId, String message) {
    if (_handle == null) throw Exception('Not initialized');

    final targetPeerIdC = targetPeerId.toNativeUtf8();
    final messageC = message.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();

    try {
      final result = _sendMessage(_handle!, targetPeerIdC.cast<ffi.Char>(), messageC.cast<ffi.Char>(), errorOut);

      final error = errorOut.value;
      if (error != ffi.nullptr) {
        final errorStr = error.cast<Utf8>().toDartString();
        _freeError(error);
        throw Exception('Send failed: $errorStr');
      }

      return result == 0;
    } finally {
      calloc.free(targetPeerIdC);
      calloc.free(messageC);
      calloc.free(errorOut);
    }
  }

  /// 广播消息
  bool broadcastMessage(List<String> targetPeerIds, String message) {
    if (_handle == null) throw Exception('Not initialized');

    final targetCount = targetPeerIds.length;
    final targets = calloc<ffi.Pointer<ffi.Char>>(targetCount);

    for (var i = 0; i < targetCount; i++) {
      targets[i] = targetPeerIds[i].toNativeUtf8().cast<ffi.Char>();
    }

    final messageC = message.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();

    try {
      final result = _broadcastMessage(_handle!, targets, targetCount, messageC.cast<ffi.Char>(), errorOut);

      final error = errorOut.value;
      if (error != ffi.nullptr) {
        final errorStr = error.cast<Utf8>().toDartString();
        _freeError(error);
        throw Exception('Broadcast failed: $errorStr');
      }

      return result == 0;
    } finally {
      for (var i = 0; i < targetCount; i++) {
        final ptr = targets[i];
        if (ptr != ffi.nullptr) {
          calloc.free(ptr);
        }
      }
      calloc.free(targets);
      calloc.free(messageC);
      calloc.free(errorOut);
    }
  }

  /// 事件回调（C 调用）
  static void _eventCallback(P2PEventData eventData, ffi.Pointer<ffi.Void> userData) {
    final eventType = eventData.eventType;

    switch (eventType) {
      case P2PEventType.nodeDiscovered:
        final peerId = eventData.peerIdString;
        _globalEventController.add(NodeDiscoveredEvent(peerId));
        break;

      case P2PEventType.nodeExpired:
        final peerId = eventData.peerIdString;
        _globalEventController.add(NodeExpiredEvent(peerId));
        break;

      case P2PEventType.nodeVerified:
        final peerId = eventData.peerIdString;
        final displayName = eventData.displayNameString;
        _globalEventController.add(NodeVerifiedEvent(peerId, displayName));
        break;

      case P2PEventType.nodeOffline:
        final peerId = eventData.peerIdString;
        _globalEventController.add(NodeOfflineEvent(peerId));
        break;

      case P2PEventType.messageReceived:
        final from = eventData.peerIdString;
        final message = eventData.messageString;
        final timestamp = eventData.timestamp;
        _globalEventController.add(MessageReceivedEvent(from, message, timestamp));
        break;

      case P2PEventType.messageSent:
        final to = eventData.peerIdString;
        final messageId = eventData.messageIdString;
        _globalEventController.add(MessageSentEvent(to, messageId));
        break;

      case P2PEventType.peerTyping:
        final from = eventData.peerIdString;
        final isTyping = eventData.isTyping;
        _globalEventController.add(PeerTypingEvent(from, isTyping));
        break;

      default:
        break;
    }
  }
}
