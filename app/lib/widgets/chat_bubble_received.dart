import 'package:flutter/material.dart';
import '../data/models/chat_message_model.dart';

class ChatBubbleReceived extends StatelessWidget {
  final ChatMessageData message;
  final String? peerName;

  const ChatBubbleReceived({super.key, required this.message, this.peerName});

  @override
  Widget build(BuildContext context) {
    // 使用对方名字的首字母作为头像文字
    final avatarText = peerName?.isNotEmpty == true
        ? peerName![0].toUpperCase()
        : '?';

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头像
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF3D8A5A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              avatarText,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 气泡
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: const BoxDecoration(
            color: Color.fromRGBO(255, 255, 255, 1),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            message.message,
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
        ),
      ],
    );
  }
}
