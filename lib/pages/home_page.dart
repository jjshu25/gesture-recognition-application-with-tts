import 'package:flutter/material.dart';
import '../widgets/home_menu_button.dart';
import 'gesture_recognition_page.dart';
import 'chat_page.dart';
import 'pose_detection_page.dart';
import 'about_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(223, 36, 160, 231),
        foregroundColor: Colors.white,
        title: const Text("Sign Language Translator"),
        centerTitle: true,
        actions: [
          // Add About button to app bar
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Gesture Recognition Button
            HomeMenuButton(
              title: "GESTURE RECOGNITION",
              icon: Icons.sign_language,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => GestureRecognitionPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            // Chatbox Button
            HomeMenuButton(
              title: "CHATBOX",
              icon: Icons.chat,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ChatPage()),
                );
              },
            ),
            const SizedBox(height: 20),
            // Add this new button for pose detection
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(223, 36, 160, 231),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PoseDetectionPage(),
                  ),
                );

                if (result != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Detected: ${result['pose']} with ${(result['confidence'] * 100).toStringAsFixed(1)}% confidence')),
                  );
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.accessibility_new),
                  SizedBox(width: 12),
                  Text('Open Pose Detection'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // In your home_page.dart, add this method to navigate to either gesture or pose recognition
  void navigateToGestureOrPoseRecognition(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Recognition Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sign_language),
                title: const Text('Hand Gesture Recognition'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GestureRecognitionPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.accessibility_new),
                title: const Text('Pose Recognition'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PoseDetectionPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
