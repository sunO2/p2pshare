import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/material.dart';
import 'native/p2p_ffi.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local P2P',
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
  final TextEditingController _messageController = TextEditingController();

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
              _nodes.clear();
              _nodes.addAll(_p2p!.getVerifiedNodes());
            });
          } else if (event is NodeOfflineEvent) {
            setState(() {
              _nodes.clear();
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
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
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
    throw Exception('Unsupported platform: ${Platform.operatingSystem}');
  }

  @override
  void dispose() {
    _p2p?.cleanup();
    _messageController.dispose();
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
          const Divider(height: 1),
          // 消息历史
          Expanded(
            flex: 2,
            child: _buildMessageList(),
          ),
          // 输入框
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildNodeList() {
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('初始化中...'),
          ],
        ),
      );
    }

    if (_nodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey),
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
            onPressed: () => _selectChatTarget(node),
          ),
        );
      },
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text('暂无消息', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Align(
          alignment: msg.isSelf ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: msg.isSelf
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortenPeerId(msg.from),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: msg.isSelf
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  msg.message,
                  style: TextStyle(
                    color: msg.isSelf
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: msg.isSelf
                        ? Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => _sendMessage(_messageController.text),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _selectChatTarget(NodeInfoData node) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已选择 ${node.displayName}，输入消息后点击发送'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    if (_nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的节点')),
      );
      return;
    }

    // 发送给第一个节点（简化版）
    final target = _nodes.first;
    _p2p!.sendMessage(target.peerId, text);
    _messageController.clear();
  }

  String _shortenPeerId(String peerId) {
    if (peerId.length > 12) {
      return '${peerId.substring(0, 10)}...';
    }
    return peerId;
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
