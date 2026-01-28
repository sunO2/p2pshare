import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';

class ChatBubbleSent extends StatelessWidget {
  final ChatMessageData message;

  const ChatBubbleSent({super.key, required this.message});

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF3D8A5A),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.message,
            style: const TextStyle(fontSize: 15, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            _formatTime(message.timestamp),
            style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }
}
