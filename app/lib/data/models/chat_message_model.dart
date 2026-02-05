import 'dart:convert';
import '../../../bridge/types.dart';

/// 消息类型常量
class MessageType {
  static const int text = 1;
  static const int image = 2;
  static const int video = 3;
  static const int file = 4;
  static const int audio = 5;
  static const int redPacket = 6;
  static const int system = 7;
  static const int unknown = 0;
}

/// 扩展字段数据（类似 Map）
class MessageExtra {
  final Map<String, dynamic> data;

  MessageExtra([this.data = const {}]);

  factory MessageExtra.fromJson(String jsonStr) {
    if (jsonStr.isEmpty) return MessageExtra();
    final Map<String, dynamic>? map = jsonDecode(jsonStr);
    return MessageExtra(map ?? {});
  }

  String toJson() => jsonEncode(data);

  // 文件相关字段 getter
  String? get fileId => data['fileId'] as String?;
  String? get fileName => data['fileName'] as String?;
  int? get fileSize => data['fileSize'] as int?;
  String? get mimeType => data['mimeType'] as String?;
  String? get localPath => data['localPath'] as String?;
  String? get thumbnailPath => data['thumbnailPath'] as String?;
  int? get duration => data['duration'] as int?;
  int? get width => data['width'] as int?;
  int? get height => data['height'] as int?;

  // 红包相关字段 getter
  String? get packetId => data['packetId'] as String?;
  int? get amount => data['amount'] as int?;
  int? get count => data['count'] as int?;
  String? get greeting => data['greeting'] as String?;
  int? get packetType => data['packetType'] as int?;

  /// 判断是否为空
  bool get isEmpty => data.isEmpty;
}

/// 聊天消息数据
class ChatMessageData {
  final String id;
  final String conversationId;
  final String senderPeerId;
  final int messageType;
  final String content; // 文本消息的文本内容
  final MessageExtra? extra; // 扩展字段
  final int timestamp;
  final String? replyToId;
  final int status;
  final bool isSelf;

  const ChatMessageData({
    required this.id,
    required this.conversationId,
    required this.senderPeerId,
    required this.messageType,
    required this.content,
    this.extra,
    required this.timestamp,
    this.replyToId,
    this.status = 0,
    this.isSelf = false,
  });

  // 从 MessageJson 构造
  factory ChatMessageData.fromJson(MessageJson msg, String localPeerId) {
    return ChatMessageData(
      id: msg.id,
      conversationId: msg.conversationId,
      senderPeerId: msg.senderPeerId,
      messageType: msg.messageType,
      content: msg.content,
      extra: msg.extra != null && msg.extra!.isNotEmpty
          ? MessageExtra.fromJson(msg.extra!)
          : null,
      timestamp: msg.timestamp.toInt(),
      replyToId: msg.replyToId,
      status: msg.status,
      isSelf: msg.senderPeerId == localPeerId,
    );
  }

  // 获取显示文本
  String get displayText {
    switch (messageType) {
      case MessageType.text:
        return content;
      case MessageType.image:
        return '[图片]';
      case MessageType.video:
        return '[视频]';
      case MessageType.file:
        return '[文件] ${extra?.fileName ?? ''}';
      case MessageType.audio:
        final duration = extra?.duration ?? 0;
        return '[语音] ${duration}s';
      case MessageType.redPacket:
        return '[红包]';
      case MessageType.system:
        return content;
      default:
        return '[未知消息]';
    }
  }

  /// 判断是否为文本消息
  bool get isText => messageType == MessageType.text;

  /// 判断是否为图片消息
  bool get isImage => messageType == MessageType.image;

  /// 判断是否为视频消息
  bool get isVideo => messageType == MessageType.video;

  /// 判断是否为文件消息
  bool get isFile => messageType == MessageType.file;

  /// 判断是否为音频消息
  bool get isAudio => messageType == MessageType.audio;

  /// 判断是否为红包消息
  bool get isRedPacket => messageType == MessageType.redPacket;

  /// 判断是否为系统消息
  bool get isSystem => messageType == MessageType.system;
}

/// 简单的聊天消息数据（旧版，保持兼容）
class ChatMessageDataSimple {
  final String message;
  final DateTime timestamp;
  final bool isSelf;

  ChatMessageDataSimple({
    required this.message,
    required this.timestamp,
    required this.isSelf,
  });

  // 从 ChatMessageData 创建简化版本
  factory ChatMessageDataSimple.fromData(ChatMessageData data) {
    return ChatMessageDataSimple(
      message: data.displayText,
      timestamp: DateTime.fromMillisecondsSinceEpoch(data.timestamp),
      isSelf: data.isSelf,
    );
  }
}

