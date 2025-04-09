// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import '../models/chat_message.dart';
import '../widgets/gauge_painters.dart';

class GestureRecognitionPage extends StatefulWidget {
  const GestureRecognitionPage({super.key});

  @override
  State<GestureRecognitionPage> createState() => _GestureRecognitionPageState();
}

class _GestureRecognitionPageState extends State<GestureRecognitionPage> {
  // Add these chat-related properties
  bool _isChatVisible = false;
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  List<ChatMessage> _messages = [];
  String? _myCode;
  String? _peerCode;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _connectionError;

  // Copy all properties and methods from _HomePageState
  static const platform = MethodChannel('com.example.handlandmarker/detection');
  final FlutterTts flutterTts = FlutterTts();
  double _confidence = 0.0;
  int _inferenceTime = 0;
  bool _isSpeaking = false;
  String _currentSentence = ''; // To store the built-up sentence
  Timer? _debounceTimer;
  String _pendingGesture = ''; // To store the last gesture temporarily
  Timer? _gestureRecognitionTimer;
  String _lastRecognizedGesture = '';
  bool _isGestureCooldown = false;
  static const _gestureCooldownDuration = Duration(milliseconds: 1200);
  String _stableGesture = '';
  int _stableGestureCount = 0;
  static const int _requiredStabilityCount = 2;
  bool _isSpeechCooldown = false; // Speech cooldown flag and timer
  Timer? _speechCooldownTimer;

  // Add these properties
  String? _currentAction;
  Timer? _landmarkBufferTimer;

  // Add these new properties for delete-specific cooldown
  bool _isDeleteCooldown = false;
  Timer? _deleteCooldownTimer;
  static const _deleteCooldownDuration =
      Duration(milliseconds: 1000); // Longer pause for delete
  int _consecutiveDeleteCount = 0;

  // Add these new properties to _GestureRecognitionPageState
  bool _isSpaceCooldown = false;
  Timer? _spaceCooldownTimer;
  static const _spaceCooldownDuration =
      Duration(milliseconds: 1500); // Slightly shorter than delete
  int _consecutiveSpaceCount = 0;

  bool _quickPoseMode = true; // New variable for immediate pose addition

  @override
  void initState() {
    super.initState();
    _setupMethodCallHandler();
    _initTts();
    _generateChatCode();

    // Add auto-start camera
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toggleCamera();
    });
  }

  // Generate a unique code for chat
  Future<void> _generateChatCode() async {
    setState(() {
      // Add loading indicator if needed
      // _isGeneratingCode = true;  // Uncomment if you want loading indicator
    });

    final prefs = await SharedPreferences.getInstance();
    String? storedId =
        prefs.getString('my_chat_code'); // Use the same key as chat_page.dart

    if (storedId == null) {
      // Generate a random 6-digit code
      final random = Random();
      storedId =
          (100000 + random.nextInt(900000)).toString(); // Ensures 6 digits
      await prefs.setString('my_chat_code', storedId);
    }

    setState(() {
      _myCode = storedId;
      // _isGeneratingCode = false;  // Uncomment if using loading indicator
    });
  }

  void _connectToChat() {
    if (_peerCode == null || _peerCode!.isEmpty) {
      setState(() {
        _connectionError = 'Please enter a connection code';
      });

      // Clear error message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _connectionError = null;
          });
        }
      });
      return;
    }

    setState(() {
      _connectionError = null;
    });

    try {
      // Connect to your Node.js server
      _channel = IOWebSocketChannel.connect('ws://192.168.1.17:3000');

      // Send initial connection message
      _channel!.sink.add(jsonEncode({
        'type': 'connect',
        'from': _myCode,
        'to': _peerCode,
      }));

      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection error: $error')),
          );
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _connectionError = 'Failed to connect: $e';
      });

      // Clear error message after 3 seconds for connection errors too
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _connectionError = null;
          });
        }
      });
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'connected') {
        setState(() {
          _isConnected = true;
          _addSystemMessage('Connected to chat');
        });
      } else if (data['type'] == 'message' &&
          data['to'] == _myCode &&
          data['from'] == _peerCode) {
        _addMessage(
          ChatMessage(
            text: data['content'],
            isMe: false,
            time: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _sendChatMessage([String? gestureText]) {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to chat')),
      );
      return;
    }

    final messageText = gestureText ?? _messageController.text.trim();

    if (messageText.isEmpty) return;

    if (gestureText == null) {
      _messageController.clear();
    }

    // Send message through WebSocket
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'from': _myCode,
      'to': _peerCode,
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

    // Scroll to bottom
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

  Future<void> _initTts() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      await flutterTts.setLanguage("en-US");
      await flutterTts
          .setSpeechRate(0.4); // Slower rate for better word recognition
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);

      // Add these settings
      await flutterTts.setQueueMode(1); // 1 for queued speaking
      // await flutterTts.setSilenceDuration(500); // 500ms pause between words
      await flutterTts
          .setVoice({"name": "en-us-x-sfg#male_1-local", "locale": "en-US"});
    } else {
      debugPrint("Microphone permission denied");
    }
  }

  Future<void> _speak(String text) async {
    // Check both speaking status and cooldown
    if (!_isSpeaking && !_isSpeechCooldown && text.isNotEmpty) {
      _isSpeaking = true;
      // Set speech cooldown immediately
      _startSpeechCooldown();

      try {
        final sentence = text.trim();
        await flutterTts.speak(sentence);
        await flutterTts.awaitSpeakCompletion(true);
      } finally {
        _isSpeaking = false;
      }
    }
  }

  // Add a separate speech cooldown method
  void _startSpeechCooldown() {
    _isSpeechCooldown = true;
    _speechCooldownTimer?.cancel();

    // Reset speech cooldown after 3 seconds
    _speechCooldownTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isSpeechCooldown = false;
        });
      }
    });
  }

  Future<void> _toggleCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        await platform.invokeMethod('toggleCamera');
        setState(() {});
      } on PlatformException catch (e) {
        debugPrint("Error toggling camera: ${e.message}");
      }
    } else {
      debugPrint("Camera permission denied");
    }
  }

  // Update _setupMethodCallHandler method
  void _setupMethodCallHandler() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onGestureRecognized':
          final String gesture = call.arguments['gesture'] as String;
          final double confidence = call.arguments['confidence'] as double;
          final int inferenceTime = call.arguments['inferenceTime'] as int;

          // Get action recognition results directly from native side
          final String? action = call.arguments['action'] as String?;
          final double actionConfidence =
              call.arguments['actionConfidence'] as double? ?? 0.0;

          // Update UI with gesture recognition
          if (gesture.isEmpty || confidence <= 0.7) {
            setState(() {
              _pendingGesture = '';
              _confidence = 0.0;
              _inferenceTime = 0;
            });
            return;
          }

          if (confidence > 0.7 && !_isGestureCooldown) {
            setState(() {
              _pendingGesture = gesture;
              _confidence = confidence;
              _inferenceTime = inferenceTime;
            });
          }

          // Process regular gestures
          _processGesture(gesture, confidence, inferenceTime);

          // Process action if recognized
          if (action != null && actionConfidence > 0.7) {
            setState(() {
              _currentAction = action;
            });
            _handleRecognizedAction(action);
          }
          break;
      }
    });
  }

  // Add method to handle recognized actions
  void _handleRecognizedAction(String action) {
    // Execute action-specific logic
    switch (action) {
      case 'Thank you':
        // Handle first action (e.g., send current text as message)
        if (_currentSentence.trim().isNotEmpty &&
            _isChatVisible &&
            _isConnected) {
          _sendChatMessage(_currentSentence);
          _updateCurrentSentence('');
        }
        break;
      case 'Hello':
        // Handle second action (e.g., toggle chat visibility)
        setState(() {
          _isChatVisible = !_isChatVisible;
        });
        break;
    }
  }

  // Update the _processGesture method in lib/pages/gesture_recognition_page.dart
  void _processGesture(String gesture, double confidence, int inferenceTime) {
    // Define gestures with lower threshold
    final lowerThresholdGestures = {"1", "4", "5", "F", "H", "N", "R", "U"};

    // Handle special gestures first
    if (confidence > 0.8) {
      switch (gesture.toLowerCase()) {
        case "delete":
          if (_currentSentence.isNotEmpty) {
            _handleDeleteGesture();
          }
          return;

        case "space":
          // Use dedicated space method with pause
          _handleSpaceGesture();
          return;

        case "speak":
          // Use the _speak method instead of directly calling flutterTts.speak
          _speak(_currentSentence);
          // Still apply gesture cooldown
          _startGestureCooldown();
          return;
      }
    }

    // Skip if in cooldown
    if (_isGestureCooldown) return;

    // Check for stability
    if (gesture == _stableGesture) {
      _stableGestureCount++;
    } else {
      _stableGesture = gesture;
      _stableGestureCount = 1;
      return; // Exit early if gesture changed
    }

    // Set appropriate threshold based on the gesture
    final threshold = lowerThresholdGestures.contains(gesture) ? 0.8 : 0.95;

    // Only proceed if stable, meets threshold, and not the last recognized gesture
    if (_stableGestureCount >= _requiredStabilityCount &&
        gesture != _lastRecognizedGesture &&
        confidence >= threshold) {
      _startGestureCooldown();
      _updateCurrentSentence(_currentSentence + gesture);
      setState(() {
        _pendingGesture = ''; // Clear pending after adding to sentence
        _lastRecognizedGesture = gesture;
        _stableGestureCount = 0;
      });

      // Keep your existing timer for last recognized gesture reset
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _lastRecognizedGesture = '';
          });
        }
      });
    }
  }

  // Add this new method to handle delete with special timing
  void _handleDeleteGesture() {
    // If already in delete cooldown, ignore

    if (_isDeleteCooldown) return;

    // Delete one character
    _updateCurrentSentence(
        _currentSentence.substring(0, _currentSentence.length - 1));

    // Track consecutive deletes
    _consecutiveDeleteCount++;

    // Calculate dynamic cooldown based on consecutive deletes
    var cooldownDuration = _deleteCooldownDuration;
    if (_consecutiveDeleteCount > 3) {
      // Increase cooldown for rapid consecutive deletes
      cooldownDuration =
          Duration(milliseconds: 2000 + (_consecutiveDeleteCount * 200));
    }

    // Apply regular cooldown too (prevents other gestures during delete cooldown)
    _startGestureCooldown();

    // Start delete-specific cooldown
    setState(() => _isDeleteCooldown = true);

    // Provide visual feedback
    ScaffoldMessenger.of(context).clearSnackBars();
    if (_consecutiveDeleteCount > 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Delete cooldown: ${cooldownDuration.inMilliseconds ~/ 1000} seconds'),
          duration: const Duration(milliseconds: 800),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Reset delete cooldown after duration
    _deleteCooldownTimer?.cancel();
    _deleteCooldownTimer = Timer(cooldownDuration, () {
      if (mounted) {
        setState(() {
          _isDeleteCooldown = false;
          _consecutiveDeleteCount = 0; // Reset consecutive counter
        });
      }
    });
  }

  // Add this new method for handling space gesture
  void _handleSpaceGesture() {
    // If already in space cooldown, ignore
    if (_isSpaceCooldown) return;

    // Add space to the current sentence
    _updateCurrentSentence('$_currentSentence ');

    // Track consecutive spaces
    _consecutiveSpaceCount++;

    // Apply regular cooldown (prevents other gestures)
    _startGestureCooldown();

    // Start space-specific cooldown
    setState(() => _isSpaceCooldown = true);

    // Provide visual feedback if multiple spaces attempted
    if (_consecutiveSpaceCount > 1) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Space cooldown active'),
          duration: Duration(milliseconds: 800),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Reset space cooldown after duration
    _spaceCooldownTimer?.cancel();
    _spaceCooldownTimer = Timer(_spaceCooldownDuration, () {
      if (mounted) {
        setState(() {
          _isSpaceCooldown = false;
          _consecutiveSpaceCount = 0; // Reset consecutive counter
        });
      }
    });
  }

  void _startGestureCooldown() {
    setState(() => _isGestureCooldown = true);
    Timer(_gestureCooldownDuration, () {
      if (mounted) setState(() => _isGestureCooldown = false);
    });
  }

  @override
  void dispose() {
    // Add the new timer to disposal
    _deleteCooldownTimer?.cancel();
    _spaceCooldownTimer?.cancel();
    _landmarkBufferTimer?.cancel();
    // Rest of your existing dispose code
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _gestureRecognitionTimer?.cancel();
    _speechCooldownTimer?.cancel(); // Cancel speech cooldown timer
    flutterTts.stop();
    super.dispose();
  }

  // Copy your build method with one change to add a back button
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: const Color.fromARGB(223, 36, 160, 231),
            foregroundColor: const Color.fromARGB(255, 255, 255, 255),
            title: const Text("Gesture Recognition"),
            // Add back button functionality
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Stop camera and TTS before going back
                flutterTts.stop();
                Navigator.pop(context);
              },
            ),
            // Add actions list with hamburger menu button
            actions: [
              IconButton(
                icon: Icon(_isChatVisible
                    ? Icons.close
                    : Icons.chat_bubble), // Changed from menu to chat_bubble
                onPressed: () {
                  setState(() {
                    _isChatVisible = !_isChatVisible;
                  });
                },
                tooltip: _isChatVisible ? 'Close Chat' : 'Open Chat',
              ),
              IconButton(
                icon: Icon(_quickPoseMode ? Icons.bolt : Icons.bolt_outlined),
                onPressed: () {
                  setState(() {
                    _quickPoseMode = !_quickPoseMode;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_quickPoseMode
                          ? 'Quick mode: ON - Immediate pose recognition'
                          : 'Quick mode: OFF - Stable pose recognition'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: 'Toggle quick pose mode',
              ),
            ],
          ),
          backgroundColor: const Color.fromARGB(255, 255, 255, 255),
          body: Column(
            children: [
              // Camera view is always shown (removed the _isCameraActive check)
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: const AspectRatio(
                    aspectRatio: 3 / 4,
                    child: AndroidView(
                      viewType: 'hand_landmarker_view',
                      creationParamsCodec: StandardMessageCodec(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Removed the floatingActionButton that toggled the camera
          bottomNavigationBar: SizedBox(
            height: 140,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Sentence: $_currentSentence',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Pending Gesture: $_pendingGesture',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Inference Time: ${_inferenceTime}ms',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 8, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isSpeechCooldown
                            ? null
                            : () => _speak(_currentSentence),
                        icon: const Icon(Icons.volume_up),
                        label: Text(_isSpeechCooldown ? 'Wait...' : 'Speak'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(223, 255, 255, 255),
                          disabledBackgroundColor: Colors.grey,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _updateCurrentSentence('');
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(223, 255, 255, 255),
                          disabledBackgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 80 + MediaQuery.of(context).padding.bottom,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 135,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(5.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: SizedBox(
                  width: 45,
                  height: 45,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(80, 80),
                        painter: GaugeBackgroundPainter(),
                      ),
                      CustomPaint(
                        size: const Size(80, 80),
                        painter: GaugeIndicatorPainter(confidence: _confidence),
                      ),
                      Container(
                        alignment: Alignment.center,
                        child: Text(
                          '${(_confidence * 100).toInt()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_isChatVisible)
          Positioned(
            top: 90, // Height of mini AppBar
            left: 100,
            right: 0,
            bottom: 460, // Height of mini bottom Appbar
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85), // Semi-transparent white
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12, // Lighter shadow
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: _buildChatPanel(),
            ),
          ),
        // Add this to display the current recognized action
        if (_currentAction != null)
          Positioned(
            top: 100,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Action: $_currentAction',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatPanel() {
    return Material(
      // Make Material transparent to show the Container's transparency
      color: Colors.transparent,
      child: Column(
        children: [
          Container(
            height: 50,
            // Keep header fully colored for better contrast
            color: const Color.fromARGB(223, 36, 160, 231),
            child: Row(
              children: [
                // Modify back button functionality
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    if (_isConnected) {
                      // If connected, disconnect from current chat
                      _channel?.sink.add(jsonEncode({
                        'type': 'disconnect',
                        'from': _myCode,
                        'to': _peerCode,
                      }));
                      _channel?.sink.close();
                      _channel = null;

                      setState(() {
                        _isConnected = false;
                        _messages = []; // Clear messages
                        _peerCode = null; // Reset peer code
                        _addSystemMessage('Disconnected from chat');
                      });
                    } else {
                      // If not connected, close chat panel
                      setState(() {
                        _isChatVisible = false;
                      });
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    _isConnected ? 'Chat with $_peerCode' : 'Connect to Chat',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Connection panel if not connected
          if (!_isConnected)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your code: ${_myCode ?? "Loading..."}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Enter code to connect:'),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter connection code',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _peerCode = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _connectToChat,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(223, 36, 160, 231),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Connect to Chat'),
                  ),
                  if (_connectionError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _connectionError!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Rest of your chat panel code...
          if (_isConnected)
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.\nStart typing or use gestures!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      // Your existing ListView builder code
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
                                  ? const Color.fromARGB(223, 36, 160, 231)
                                      .withOpacity(0.9)
                                      .withOpacity(0.9)
                                  : Colors.grey[200]!.withOpacity(0.9),
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

          // Input field when connected
          if (_isConnected)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: const Color.fromARGB(223, 36, 160, 231),
                    onPressed: () => _sendChatMessage(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.gesture),
                    color: const Color.fromARGB(223, 36, 160, 231),
                    onPressed: () {
                      if (_currentSentence.trim().isNotEmpty) {
                        _sendChatMessage(_currentSentence);
                        _updateCurrentSentence(''); // Clear after sending
                      }
                    },
                    tooltip: 'Send current gesture text',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Add this helper method to _GestureRecognitionPageState
  void _updateCurrentSentence(String value) {
    setState(() {
      _currentSentence = value;
      // Also update message controller if chat is visible
      if (_isChatVisible && _isConnected) {
        _messageController.text = value;
        // Position cursor at the end
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    });
  }
}
