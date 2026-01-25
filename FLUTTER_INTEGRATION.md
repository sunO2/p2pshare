# Flutter FFI 集成指南（完整版）

本文档详细说明如何通过 FFI 将 Rust P2P 核心库集成到 Flutter 应用中。

## 目录

1. [架构概述](#架构概述)
2. [编译 Rust 库](#编译-rust-库)
3. [C 头文件](#c-头文件)
4. [Dart FFI 绑定](#dart-ffi-绑定)
5. [Flutter Widget 示例](#flutter-widget-示例)
6. [平台特定配置](#平台特定配置)
7. [测试和调试](#测试和调试)

## 架构概述

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter App (Dart)                    │
│  ┌───────────────────────────────────────────────────┐  │
│  │           UI Layer (Widgets)                      │  │
│  └───────────────────────────────────────────────────┘  │
│                        ↓                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │        P2PService (Dart FFI Wrapper)              │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↓
                    C ABI (FFI)
                          ↓
┌─────────────────────────────────────────────────────────┐
│              Rust FFI Layer (localp2p-ffi)              │
│  ┌───────────────────────────────────────────────────┐  │
│  │  C-compatible functions & types                   │  │
│  └───────────────────────────────────────────────────┘  │
│                        ↓                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │         Core P2P Library (mdns crate)             │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 编译 Rust 库

### 使用构建脚本（推荐）

```bash
cd crates/ffi

# 构建所有平台
./build.sh all

# 只构建当前平台
./build.sh linux    # Linux
./build.sh macos-arm64  # macOS ARM64
./build.sh windows  # Windows
```

### 手动编译

```bash
# 从项目根目录编译
cargo build -p localp2p-ffi --release

# 特定目标
cargo build --target aarch64-apple-ios --release
cargo build --target x86_64-unknown-linux-gnu --release
```

### 输出文件位置

| 平台 | 输出文件 | Flutter 路径 |
|------|---------|-------------|
| Linux x64 | `target/x86_64-unknown-linux-gnu/release/liblocalp2p_ffi.so` | `linux/liblocalp2p_ffi.so` |
| macOS ARM64 | `target/aarch64-apple-darwin/release/liblocalp2p_ffi.dylib` | `macos/liblocalp2p_ffi.dylib` |
| macOS x64 | `target/x86_64-apple-darwin/release/liblocalp2p_ffi.dylib` | `macos/liblocalp2p_ffi.dylib` |
| Windows x64 | `target/x86_64-pc-windows-msvc/release/localp2p_ffi.dll` | `windows/localp2p_ffi.dll` |
| Android ARM64 | `target/aarch64-linux-android/release/liblocalp2p_ffi.so` | `android/src/main/jniLibs/arm64-v8a/liblocalp2p_ffi.so` |
| iOS ARM64 | `target/aarch64-apple-ios/release/liblocalp2p_ffi.a` | (通过 Xcode 集成) |

## C 头文件

C 头文件位于 `crates/ffi/include/localp2p.h`，包含以下类型定义：

```c
/** P2P 句柄 */
typedef struct { int32_t _private; } LocalP2P_Handle;

/** 错误代码 */
typedef enum {
    LOCALP2P_SUCCESS = 0,
    LOCALP2P_NOT_INITIALIZED = -1,
    LOCALP2P_INVALID_ARGUMENT = -2,
    LOCALP2P_SEND_FAILED = -3,
    LOCALP2P_NODE_NOT_VERIFIED = -4,
    LOCALP2P_OUT_OF_MEMORY = -5,
    LOCALP2P_UNKNOWN = -99,
} LocalP2P_ErrorCode;

/** 事件类型 */
typedef enum {
    LOCALP2P_EVENT_NODE_DISCOVERED = 1,
    LOCALP2P_EVENT_NODE_VERIFIED = 3,
    LOCALP2P_EVENT_NODE_OFFLINE = 4,
    LOCALP2P_EVENT_MESSAGE_RECEIVED = 6,
    LOCALP2P_EVENT_MESSAGE_SENT = 7,
    LOCALP2P_EVENT_PEER_TYPING = 8,
} LocalP2P_EventType;

/** 事件数据 */
typedef struct {
    LocalP2P_EventType event_type;
    const char *peer_id;
    const char *display_name;
    const char *message;
    const char *message_id;
    bool is_typing;
    int64_t timestamp;
} LocalP2P_EventData;

/** 事件回调类型 */
typedef void (*LocalP2P_EventCallback)(LocalP2P_EventData event, void *user_data);
```

## Dart FFI 绑定

创建 `lib/p2p_ffi.dart`:

```dart
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// ============================================================
// 类型定义
// ============================================================

/// P2P 错误代码
class P2PErrorCode {
  static const int success = 0;
  static const int notInitialized = -1;
  static const int invalidArgument = -2;
  static const int sendFailed = -3;
  static const int nodeNotVerified = -4;
  static const int outOfMemory = -5;
  static const int unknown = -99;
}

/// P2P 事件类型
class P2PEventType {
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
class P2PHandle extends ffi.Struct {
  @ffi.Int32()
  external int _private;
}

/// P2P 事件数据
class P2PEventData extends ffi.Struct {
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
    return ptr.cast<Utf>().toDartString();
  }

  /// 获取显示名称
  String get displayNameString {
    final ptr = displayName;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf>().toDartString();
  }

  /// 获取消息内容
  String get messageString {
    final ptr = message;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf>().toDartString();
  }

  /// 获取消息 ID
  String get messageIdString {
    final ptr = messageId;
    if (ptr == ffi.nullptr) return '';
    return ptr.cast<Utf>().toDartString();
  }

  /// 获取时间戳
  DateTime get timestampDateTime {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}

// ============================================================
// FFI 函数签名
// ============================================================

typedef InitNative = P2PHandle Function(ffi.Pointer<ffi.Char> deviceName, ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut);
typedef StartNative = ffi.Int32 Function(P2PHandle handle, ffi.Pointer<ffi.NativeFunction<StartCallbackNative>> callback, ffi.Pointer<ffi.Void> userData);
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

// 回调函数类型
typedef StartCallbackNative = ffi.Void Function(P2PEventData eventData, ffi.Pointer<ffi.Void> userData);
typedef StartCallbackDart = void Function(P2PEventData eventData, ffi.Pointer<ffi.Void> userData);

// ============================================================
// 节点信息
// ============================================================

class NodeInfo extends ffi.Struct {
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

// ============================================================
// P2P Service
// ============================================================

class P2PService {
  final ffi.DynamicLibrary _lib;

  late final InitNative _init;
  late final StartNative _start;
  late final StopNative _stop;
  late final CleanupNative _cleanup;
  late final GetLocalPeerIdNative _getLocalPeerId;
  late final GetDeviceNameNative _getDeviceName;
  late final GetVerifiedNodesNative _getVerifiedNodes;
  late final FreeNodeListNative _freeNodeList;
  late final SendMessageNative _sendMessage;
  late final BroadcastMessageNative _broadcastMessage;
  late final FreeErrorNative _freeError;

  P2PHandle? _handle;
  final _eventController = StreamController<P2PEvent>.broadcast();
  ffi.Pointer<ffi.NativeFunction<StartCallbackNative>>? _callbackPointer;

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
  }

  /// 初始化 P2P 模块
  bool init(String deviceName) {
    final deviceNameC = deviceName.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();

    try {
      _handle = _init(deviceNameC.cast<ffi.Char>(), errorOut);

      final error = errorOut.value;
      if (error != ffi.nullptr) {
        final errorStr = error.cast<Utf>().toDartString();
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
    final callback = ffi.Pointer.fromFunction<StartCallbackNative>(
      _eventCallback,
    );

    // 保存回调指针，防止被 GC
    _callbackPointer = ffi.Pointer.fromFunction<StartCallbackNative>(
      _eventCallback,
    );

    return _start(_handle!, _callbackPointer!, ffi.nullptr) == P2PErrorCode.success;
  }

  /// 停止 P2P 服务
  void stop() {
    if (_handle != null) {
      _stop(_handle!);
    }
  }

  /// 清理资源
  void cleanup() {
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
      if (result != P2PErrorCode.success) {
        throw Exception('Failed to get local peer id');
      }
      return out.cast<Utf>().toDartString();
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
      if (result != P2PErrorCode.success) {
        throw Exception('Failed to get device name');
      }
      return out.cast<Utf>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// 获取已验证的节点列表
  List<NodeInfoData> getVerifiedNodes() {
    if (_handle == null) throw Exception('Not initialized');

    final out = calloc<ffi.Pointer<NodeInfo>>();
    final outLen = calloc<ffi.Size>();

    try {
      final result = _getVerifiedNodes(_handle!, out, outLen);
      if (result != P2PErrorCode.success) {
        throw Exception('Failed to get verified nodes');
      }

      final len = outLen.value;
      final nodes = out.value;
      final result = <NodeInfoData>[];

      for (var i = 0; i < len; i++) {
        final node = nodes.elementAt(i).ref;
        result.add(NodeInfoData(
          peerId: node.peerId.cast<Utf>().toDartString(),
          displayName: node.displayName.cast<Utf>().toDartString(),
          deviceName: node.deviceName.cast<Utf>().toDartString(),
        ));
      }

      _freeNodeList(nodes, len);
      return result;
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
        final errorStr = error.cast<Utf>().toDartString();
        _freeError(error);
        throw Exception('Send failed: $errorStr');
      }

      return result == P2PErrorCode.success;
    } finally {
      calloc.free(targetPeerIdC);
      calloc.free(messageC);
      calloc.free(errorOut);
    }
  }

  /// 广播消息
  bool broadcastMessage(List<String> targetPeerIds, String message) {
    if (_handle == null) throw Exception('Not initialized';

    final targetCount = targetPeerIds.length;
    final targets = calloc<ffi.Pointer<ffi.Char>>(targetCount);

    for (var i = 0; i < targetCount; i++) {
      targets.elementAt(i).value = targetPeerIds[i].toNativeUtf8().cast<ffi.Char>();
    }

    final messageC = message.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();

    try {
      final result = _broadcastMessage(_handle!, targets, targetCount, messageC.cast<ffi.Char>(), errorOut);

      final error = errorOut.value;
      if (error != ffi.nullptr) {
        final errorStr = error.cast<Utf>().toDartString();
        _freeError(error);
        throw Exception('Broadcast failed: $errorStr');
      }

      return result == P2PErrorCode.success;
    } finally {
      for (var i = 0; i < targetCount; i++) {
        calloc.free(targets.elementAt(i).value);
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
        _eventController.add(NodeDiscoveredEvent(peerId));
        break;

      case P2PEventType.nodeVerified:
        final peerId = eventData.peerIdString;
        final displayName = eventData.displayNameString;
        _eventController.add(NodeVerifiedEvent(peerId, displayName));
        break;

      case P2PEventType.nodeOffline:
        final peerId = eventData.peerIdString;
        _eventController.add(NodeOfflineEvent(peerId));
        break;

      case P2PEventType.messageReceived:
        final from = eventData.peerIdString;
        final message = eventData.messageString;
        final timestamp = eventData.timestamp;
        _eventController.add(MessageReceivedEvent(from, message, timestamp));
        break;

      case P2PEventType.messageSent:
        final to = eventData.peerIdString;
        final messageId = eventData.messageIdString;
        _eventController.add(MessageSentEvent(to, messageId));
        break;

      case P2PEventType.peerTyping:
        final from = eventData.peerIdString;
        final isTyping = eventData.isTyping;
        _eventController.add(PeerTypingEvent(from, isTyping));
        break;

      default:
        break;
    }
  }
}
```

## Flutter Widget 示例

创建 `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'dart:io';
import 'p2p_ffi.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local P2P Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const P2PPage(),
    );
  }
}

class P2PPage extends StatefulWidget {
  const P2PPage({super.key});

  @override
  State<P2PPage> createState() => _P2PPageState();
}

class _P2PPageState extends State<P2PPage> {
  P2PService? _p2p;
  final List<NodeInfoData> _nodes = [];
  final List<ChatMessage> _messages = [];
  bool _isInitialized = false;
  String? _localPeerId;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _initP2P();
  }

  Future<void> _initP2P() async {
    try {
      // 加载动态库
      final lib = ffi.DynamicLibrary.open(_getLibraryPath());
      _p2p = P2PService(lib);

      // 初始化
      final success = _p2p!.init('Flutter Device');
      if (success) {
        setState(() {
          _isInitialized = true;
          _localPeerId = _p2p!.getLocalPeerId();
          _deviceName = _p2p!.getDeviceName();
        });

        // 监听事件
        _p2p!.eventStream.listen((event) {
          if (!mounted) return;

          if (event is NodeVerifiedEvent) {
            setState(() {
              _nodes.addAll(_p2p!.getVerifiedNodes());
            });
          } else if (event is MessageReceivedEvent) {
            setState(() {
              _messages.add(ChatMessage(
                from: event.from,
                message: event.message,
                timestamp: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
                isSelf: false,
              ));
            });
          } else if (event is MessageSentEvent) {
            setState(() {
              _messages.add(ChatMessage(
                from: _localPeerId!,
                message: '(sent)',
                timestamp: DateTime.now(),
                isSelf: true,
              ));
            });
          }
        });

        // 启动服务
        _p2p!.start();
      }
    } catch (e) {
      debugPrint('Failed to initialize P2P: $e');
    }
  }

  String _getLibraryPath() {
    if (Platform.isAndroid) {
      return 'liblocalp2p_ffi.so';
    } else if (Platform.isLinux) {
      return 'liblocalp2p_ffi.so';
    } else if (Platform.isMacOS) {
      return 'liblocalp2p_ffi.dylib';
    } else if (Platform.isWindows) {
      return 'localp2p_ffi.dll';
    }
    throw Exception('Unsupported platform');
  }

  @override
  void dispose() {
    _p2p?.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Local P2P - $_deviceName'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _nodes.clear();
                _nodes.addAll(_p2p!.getVerifiedNodes());
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 节点列表
          Expanded(
            flex: 1,
            child: _buildNodeList(),
          ),
          // 消息历史
          Expanded(
            flex: 2,
            child: _buildMessageList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeList() {
    if (_nodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在扫描局域网内的设备...'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _nodes.length,
      itemBuilder: (context, index) {
        final node = _nodes[index];
        return ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.devices),
          ),
          title: Text(node.displayName),
          subtitle: Text(node.deviceName),
          trailing: IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () => _showChatDialog(node),
          ),
        );
      },
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text('暂无消息'),
      );
    }

    return ListView.builder(
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Align(
          alignment: msg.isSelf ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: msg.isSelf ? Colors.blue[100] : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.from.substring(0, 8),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(msg.message),
                const SizedBox(height: 4),
                Text(
                  '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChatDialog(NodeInfoData node) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('与 ${node.displayName} 聊天'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入消息...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _p2p!.sendMessage(node.peerId, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String from;
  final String message;
  final DateTime timestamp;
  final bool isSelf;

  ChatMessage({
    required this.from,
    required this.message,
    required this.timestamp,
    required this.isSelf,
  });
}
```

## 平台特定配置

### Android

在 `android/app/build.gradle` 中添加：

```groovy
android {
    // ...
    packagingOptions {
        jniLibs {
            pickFirsts += ['**/liblocalp2p_ffi.so']
        }
    }
}
```

将 `.so` 文件复制到：
- `android/src/main/jniLibs/arm64-v8a/liblocalp2p_ffi.so`
- `android/src/main/jniLibs/armeabi-v7a/liblocalp2p_ffi.so`
- `android/src/main/jniLibs/x86_64/liblocalp2p_ffi.so`

### iOS

在 `ios/Runner.xcodeproj` 中：
1. 添加 `liblocalp2p_ffi.a` 到 "Link Binary With Libraries"
2. 在 "Build Settings" 中添加 "Header Search Paths" 指向包含 `localp2p.h` 的目录

### Linux

将 `.so` 文件放到与可执行文件相同的目录。

### macOS

将 `.dylib` 文件放到与可执行文件相同的目录。

## 测试和调试

### 启用 Rust 日志

```bash
# 设置环境变量
export RUST_LOG=debug
# 运行应用
flutter run
```

### 常见问题

1. **库加载失败**: 确保库文件位于正确的位置
2. **类型不匹配**: 检查 FFI 类型定义是否与 C 头文件一致
3. **内存泄漏**: 使用 `dart:developer` 服务监控内存使用

## 完整示例

查看完整示例：
- C 示例: `crates/ffi/examples/simple.c`
- Dart 绑定: 上面的 `p2p_ffi.dart`
- Flutter Widget: 上面的 `main.dart`
