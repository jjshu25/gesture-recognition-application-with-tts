class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime time;
  final bool isSystem;

  ChatMessage({
    required this.text,
    this.isMe = false,
    required this.time,
    this.isSystem = false,
  });
}
