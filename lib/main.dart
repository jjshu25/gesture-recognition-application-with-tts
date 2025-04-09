import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions on app start
  await [
    Permission.camera,
    Permission.microphone,
    Permission.storage,
  ].request();

  runApp(const HandLandmarkerApp());
}

class HandLandmarkerApp extends StatelessWidget {
  const HandLandmarkerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}
