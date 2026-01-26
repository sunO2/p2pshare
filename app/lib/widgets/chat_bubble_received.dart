import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';

class ChatBubbleReceived extends StatelessWidget {
  final ChatMessageData message;

  const ChatBubbleReceived({super.key, required this.message});

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(
          color: const Color(0xFFE5E4E1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x08000000),
            offset: const Offset(0, 1),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.message,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF1A1918),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatTime(message.timestamp),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF9C9B99),
            ),
          ),
        ],
      ),
    );
  }
}
