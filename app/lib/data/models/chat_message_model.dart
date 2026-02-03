/// 聊天消息数据模型
class ChatMessageData {
  final String message;
  final DateTime timestamp;
  final bool isSelf;

  ChatMessageData({
    required this.message,
    required this.timestamp,
    required this.isSelf,
  });
}
