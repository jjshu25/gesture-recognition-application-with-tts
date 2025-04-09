import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

class TtsService {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    final status = await Permission.microphone.request();
    if (status.isGranted) {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.4);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setQueueMode(1);
      await _flutterTts
          .setVoice({"name": "en-us-x-sfg#male_1-local", "locale": "en-US"});
      _isInitialized = true;
    } else {
      debugPrint("Microphone permission denied");
    }
  }

  static Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();

    if (text.isNotEmpty) {
      final sentence = text.trim();
      await _flutterTts.speak(sentence);
      await _flutterTts.awaitSpeakCompletion(true);
    }
  }

  static Future<void> stop() async {
    await _flutterTts.stop();
  }
}
