import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/io.dart';
import '../models/chat_message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  Widget build(BuildContext context) {
    return ConnectionScreen();
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({Key? key}) : super(key: key);

  @override
  _ConnectionScreenState createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _codeController = TextEditingController();
  String? _myCode;
  bool _isGeneratingCode = false;

  @override
  void initState() {
    super.initState();
    _generateMyCode();
  }

  void _generateMyCode() async {
    setState(() {
      _isGeneratingCode = true;
    });

    // Generate a random 6-digit code
    final random = Random();
    final code = List.generate(6, (_) => random.nextInt(10)).join();

    // Store this code in SharedPreferences for persistence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_chat_code', code);

    setState(() {
      _myCode = code;
      _isGeneratingCode = false;
    });
  }

  void _connectToChat() {
    if (_codeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a connection code')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          myCode: _myCode!,
          peerCode: _codeController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(223, 36, 160, 231),
        foregroundColor: Colors.white,
        title: const Text('Connect to Chat'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Share your code with the person you want to chat with:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Color.fromARGB(223, 36, 160, 231)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isGeneratingCode
                  ? const CircularProgressIndicator()
                  : SelectableText(
                      _myCode ?? 'Error generating code',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Enter the code of the person you want to chat with:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter connection code',
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Color.fromARGB(223, 36, 160, 231),
                  ),
                ),
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _connectToChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(223, 36, 160, 231),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Connect and Chat'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String myCode;
  final String peerCode;

  const ChatScreen({
    Key? key,
    required this.myCode,
    required this.peerCode,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = true;
  List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _connectToServer();
  }

  void _connectToServer() {
    try {
      // Connect to your Node.js server (replace with your server URL)
      _channel = IOWebSocketChannel.connect('ws://192.168.1.17:3000');

      // Send initial connection message with identification codes
      _channel!.sink.add(jsonEncode({
        'type': 'connect',
        'from': widget.myCode,
        'to': widget.peerCode,
      }));

      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onError: (error) {
          _showConnectionError('Connection error: $error');
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
            });
            _showConnectionError('Connection closed');
          }
        },
      );
    } catch (e) {
      _showConnectionError('Failed to connect: $e');
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'connected') {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _addSystemMessage('Connected to chat');
        });
      } else if (data['type'] == 'message' &&
          data['to'] == widget.myCode &&
          data['from'] == widget.peerCode) {
        _addMessage(
          ChatMessage(
            text: data['content'],
            isMe: false,
            time: DateTime.now(),
          ),
        );
      } else if (data['type'] == 'error') {
        _showConnectionError(data['message']);
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _showConnectionError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || !_isConnected) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Send message through WebSocket
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'from': widget.myCode,
      'to': widget.peerCode,
      'content': messageText,
    }));

    _addMessage(
      ChatMessage(
        text: messageText,
        isMe: true,
        time: DateTime.now(),
      ),
    );
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });

    // Scroll to the bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isSystem: true,
        time: DateTime.now(),
      ));
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(223, 36, 160, 231),
        foregroundColor: Colors.white,
        title: Text(_isConnecting
            ? 'Connecting...'
            : _isConnected
                ? 'Chat with ${widget.peerCode}'
                : 'Disconnected'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isConnecting
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting to chat...'),
                      ],
                    ),
                  )
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet.\nSend a message to start the conversation!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];

                          if (message.isSystem) {
                            return Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  message.text,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[800],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          }

                          return Align(
                            alignment: message.isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: message.isMe
                                    ? Color.fromARGB(223, 36, 160, 231)
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: message.isMe
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${message.time.hour}:${message.time.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: message.isMe
                                          ? Colors.white70
                                          : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  offset: Offset(0, -1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide(
                          color: Color.fromARGB(223, 36, 160, 231),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    enabled: _isConnected,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isConnected ? _sendMessage : null,
                  color: Color.fromARGB(223, 36, 160, 231),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
