// ignore_for_file: unused_field, prefer_final_fields

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/chat_message.dart';

class PoseDetectionPage extends StatefulWidget {
  const PoseDetectionPage({Key? key}) : super(key: key);

  @override
  State<PoseDetectionPage> createState() => _PoseDetectionPageState();
}

class _PoseDetectionPageState extends State<PoseDetectionPage> {

  String _currentPose = "None";
  double _confidence = 0.0;
  bool _isDetecting = true;

  // store all pose confidences
  Map<String, double> _poseConfidences = {
    "Hello": 0.0,
    "Thank you": 0.0,
    "Sorry": 0.0,
  };

  String _currentSentence = "";
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;

  InAppWebViewController? _webViewController;

  // chat-related variables
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  List<ChatMessage> _messages = [];
  String? _myCode;
  String? _peerCode;
  String? _connectionError;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _lastAddedPose = "";
  bool _isPoseCooldown = false;
  DateTime _lastPoseAddedTime = DateTime.now();
  DateTime _lastAddedTime = DateTime.now(); // Define _lastAddedTime
  final ValueNotifier<bool> _dataReceivedNotifier = ValueNotifier<bool>(false);
  bool _buildingSentence = false;
  Map<String, bool> _spokenPoses = {};

  @override
  void initState() {
    super.initState();
    _initTts();
    // set to full screen when entering
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _generateChatCode();
  }

  // preserve the sentence clearing functionality
  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);

    flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  // auto-speak function
  Future<void> _speak(String text) async {
    if (text.isEmpty) {
      return;
    }

    if (_isSpeaking) {
      await flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    await flutterTts.speak(text);
  }


  void _updateCurrentSentence(String newSentence) {
    setState(() {
      _currentSentence = newSentence;
    });
  }

  // generate a unique code for chat
  Future<void> _generateChatCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('my_chat_code');

    if (storedId == null) {
      // generate a random 6-digit code
      final random = Random();
      storedId = (100000 + random.nextInt(900000)).toString();
      await prefs.setString('my_chat_code', storedId);
    }

    setState(() {
      _myCode = storedId;
    });
  }


  void _connectToChat() {
    if (_peerCode == null || _peerCode!.isEmpty) {
      setState(() {
        _connectionError = 'Please enter a connection code';
      });

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
      // connect to your Node.js server
      _channel = IOWebSocketChannel.connect('ws://192.168.1.17:3000');

      // send initial connection message
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

  // handle pose-based messages
  void _sendChatMessage([String? poseText]) {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to chat')),
      );
      return;
    }

    // provided pose text or the text from the message controller
    final messageText = poseText ?? _messageController.text.trim();

    if (messageText.isEmpty) return;

    // clear the input if we're sending from the input box (not from a pose)
    if (poseText == null) {
      _messageController.clear();
    }

    // send message through WebSocket
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
    flutterTts.stop();
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();

    // restore default UI mode when leaving
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pose Detection'),
        backgroundColor: const Color.fromARGB(223, 36, 160, 231),
        actions: [
          IconButton(
            icon: Icon(_isDetecting ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              setState(() {
                _isDetecting = !_isDetecting;
              });
            },
            tooltip: _isDetecting ? 'Pause Detection' : 'Resume Detection',
          ),
          IconButton(
            icon: Icon(_buildingSentence
                ? Icons.format_list_bulleted
                : Icons.text_fields),
            onPressed: () {
              setState(() {
                _buildingSentence = !_buildingSentence;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_buildingSentence
                      ? 'Building sentence: ON - Poses will be combined'
                      : 'Building sentence: OFF - Each pose replaces previous'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: _buildingSentence ? 'Building Sentence' : 'Single Pose',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _currentSentence.isEmpty
                        ? "No sentence yet"
                        : _currentSentence,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up,
                      color: Colors.white),
                  onPressed: () => _speak(_currentSentence),
                  tooltip: _isSpeaking ? 'Stop Speaking' : 'Speak Sentence',
                ),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white70),
                  onPressed: _currentSentence.isEmpty
                      ? null
                      : () => _updateCurrentSentence(""),
                  tooltip: 'Clear Sentence',
                ),
              ],
            ),
          ),
          // WebView for pose detection
          Expanded(
            flex: 2, 
            child: Stack(
              children: [
                InAppWebView(
                  initialFile: 'assets/index.html',
                  initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(
                      mediaPlaybackRequiresUserGesture: false,
                      transparentBackground: true,
                      supportZoom: false,
                      javaScriptCanOpenWindowsAutomatically: true,
                    ),
                    android: AndroidInAppWebViewOptions(
                      useHybridComposition: true,
                      useShouldInterceptRequest: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                    ),
                    ios: IOSInAppWebViewOptions(
                      allowsInlineMediaPlayback: true,
                    ),
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;

                    // Set the controller to the state for later use
                    controller.addJavaScriptHandler(
                      handlerName: 'console',
                      callback: (args) {
                        if (args.isNotEmpty) {
                          debugPrint("🌐 WebView Log: ${args[0]}");
                        }
                      },
                    );

                    // Replace the pose detection handler with the updated code
                    controller.addJavaScriptHandler(
                      handlerName: 'poseDetection',
                      callback: (args) {
                        if (!_isDetecting) return;

                        // Show data is being received
                        _dataReceivedNotifier.value = true;
                        Future.delayed(const Duration(milliseconds: 500), () {
                          _dataReceivedNotifier.value = false;
                        });

                        try {
                          if (args.isNotEmpty) {
                            debugPrint("📊 Received pose data: ${args[0]}");
                            final rawData = jsonDecode(args[0]);
                            // Check if the data is empty or not
                            final Map<String, double> data = {};

                            // Convert all confidence values to doubles
                            rawData.forEach((pose, confidence) {
                              data[pose] = confidence is int
                                  ? confidence.toDouble()
                                  : confidence;
                            });

                            // Get the highest confidence pose
                            String highestPose = "None";
                            double highestConfidence = 0.0;

                            data.forEach((pose, confidence) {
                              if (pose.toLowerCase() == "none") return;
                              if (confidence > highestConfidence) {
                                highestConfidence = confidence;
                                highestPose = pose;
                              }
                            });

                            // Update the current pose and confidence in the state
                            setState(() {
                              _currentPose = highestConfidence > 0.4
                                  ? highestPose
                                  : "None";
                              _confidence = highestConfidence > 0.4
                                  ? highestConfidence
                                  : 0.0;
                            });

                            // Add pose to sentence if confidence is high enough
                            if (highestConfidence >= 0.95 &&
                                highestPose != "None" &&
                                !_isPoseCooldown &&
                                highestPose != _lastAddedPose) {

                              // Show immediate feedback that a pose was detected
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Detected: $highestPose - Adding in 1 second...'),
                                  duration: const Duration(milliseconds: 800),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.blue,
                                ),
                              );

                              // Add a 1-second delay before adding the pose to the sentence
                              Future.delayed(const Duration(seconds: 1), () {
                                if (mounted) {
                                  _addPoseToSentence(highestPose);
                                }
                              });
                            }

                            // Update confidences
                            _updateConfidences(data);
                          }
                        } catch (e, stackTrace) {
                          debugPrint("❌ Error parsing pose data: $e");
                          debugPrint("Stack trace: $stackTrace");
                        }
                      },
                    );

                    // Inject a test function to verify communication
                    Future.delayed(const Duration(seconds: 3), () {
                      controller.evaluateJavascript(source: '''
                        if (window.flutter_inappwebview) {
                          window.flutter_inappwebview.callHandler('console', 'Communication test successful');
                        } else {
                          console.error('flutter_inappwebview not available after 3 seconds');
                        }
                      ''');
                    });
                  },
                  androidOnPermissionRequest:
                      (controller, origin, resources) async {
                    return PermissionRequestResponse(
                      resources: resources,
                      action: PermissionRequestResponseAction.GRANT,
                    );
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    debugPrint("Console: ${consoleMessage.message}");
                  },
                ),

                // Current pose overlay
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _currentPose == "None"
                              ? "No pose detected"
                              : _currentPose,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_confidence > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${(_confidence * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              color: _getConfidenceColor(_confidence),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _dataReceivedNotifier,
                      builder: (context, isReceiving, _) {
                        return Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isReceiving ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isReceiving ? "Data flowing" : "No data",
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // chat panel at the bottom
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: _buildCompactChatPanel(),
            ),
          ),
        ],
      ),
    );
  }

  // chat panel for bottom placement
  Widget _buildCompactChatPanel() {
    return Column(
      children: [
        // chat header with connection status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color.fromARGB(223, 36, 160, 231),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isConnected
                      ? 'Chat with $_peerCode'
                      : 'Your code: ${_myCode ?? "Loading..."} - Not connected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!_isConnected)
                TextButton.icon(
                  icon: const Icon(Icons.link, color: Colors.white),
                  label: const Text('Connect',
                      style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    _showConnectDialog();
                  },
                ),
            ],
          ),
        ),
        // chat messages area
        Expanded(
          child: _isConnected
              ? _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.\nDetect poses to send messages!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];

                        if (message.isSystem) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                message.text,
                                style: TextStyle(
                                  fontSize: 11,
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
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: message.isMe
                                  ? const Color.fromARGB(223, 36, 160, 231)
                                      .withOpacity(0.9)
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: message.isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.text,
                                  style: TextStyle(
                                    color: message.isMe
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${message.time.hour}:${message.time.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    color: message.isMe
                                        ? Colors.white70
                                        : Colors.grey[600],
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Not connected to chat'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _showConnectDialog(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(223, 36, 160, 231),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Connect to Chat'),
                      ),
                    ],
                  ),
                ),
        ),

        // Message input field (only if connected)
        if (_isConnected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: const Offset(0, -1),
                  blurRadius: 3,
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
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      isDense: true,
                      suffixIcon: _messageController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  _messageController.clear();
                                });
                              },
                            ),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: const Color.fromARGB(223, 36, 160, 231),
                  onPressed: () => _sendChatMessage(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // connection dialog
  void _showConnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _connectToChat();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(223, 36, 160, 231),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _updateConfidences(dynamic data) {
    setState(() {
      for (var key in _poseConfidences.keys.toList()) {
        if (data.containsKey(key)) {
          // Ensure value is always a double
          var value = data[key];
          _poseConfidences[key] = value is int ? value.toDouble() : value;
        }
      }
    });
  }

  // speak only once per pose
  void _addPoseToSentence(String pose) {
    // Skip if the pose is None
    if (pose.toLowerCase() == "none") return;
    _lastPoseAddedTime = DateTime.now();
    String formattedPose;

    switch (pose.toUpperCase()) {
      case 'THANK YOU':
        formattedPose = "Thank you";
        break;
      case 'HELLO':
        formattedPose = "Hello";
        break;
      case 'SORRY':
        formattedPose = "Sorry";
        break;
      default:
        formattedPose = pose;
    }

    setState(() {
      // Update the sentence based on mode
      if (_buildingSentence) {
        _currentSentence =
            "${_currentSentence.isEmpty ? '' : '$_currentSentence '}$formattedPose";
      } else {
        _currentSentence = formattedPose;
      }

      _lastAddedPose = pose;
      _isPoseCooldown = true;

      // ALSO UPDATE CHAT MESSAGE BOX if connected to chat
      if (_isConnected) {
        // Update the message controller text based on mode
        if (_buildingSentence) {
          _messageController.text =
              "${_messageController.text.isEmpty ? '' : '${_messageController.text} '}$formattedPose";
        } else {
          _messageController.text = formattedPose;
        }
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    });

    // prevent constinous speaking of the same pose
    if (!_spokenPoses.containsKey(pose)) {
      _speak(_currentSentence);
      _spokenPoses[pose] = true;

      // Reset the spoken poses map after a delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _spokenPoses.remove(pose);
          });
        }
      });
    }

    // Show feedback that the pose was added
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isConnected
            ? 'Added to chat: $formattedPose'
            : 'Added: $formattedPose'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
      ),
    );

    // Reset cooldown after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isPoseCooldown = false;
        });
      }
    });

    // Reset last added pose after a delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _lastAddedPose == pose) {
        setState(() {
          _lastAddedPose = "";
        });
      }
    });
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence < 0.4) return Colors.red;
    if (confidence < 0.7) return Colors.orange;
    return Colors.green;
  }
}
