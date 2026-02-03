import 'package:flutter/material.dart';
import '../data/models/chat_message_model.dart';

class ChatBubbleSent extends StatelessWidget {
  final ChatMessageData message;

  const ChatBubbleSent({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 气泡
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: const BoxDecoration(
            color: Color(0xFF95EC69), // 微信绿色
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(right: 8),
          child: Text(
            message.message,
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
        ),
        // 头像
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE8E8E6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Icon(Icons.person, size: 20, color: Color(0xFF9C9B99)),
          ),
        ),
      ],
    );
  }
}
