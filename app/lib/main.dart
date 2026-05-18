import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:route_mate_app/features/main_shell/main_shell_screen.dart';

void main() async {
  // Bắt buộc phải có dòng này khi khởi tạo các thư viện ngoài (như dotenv, Firebase...)
  WidgetsFlutterBinding.ensureInitialized();
  
  // Nạp Két sắt .env TRƯỚC KHI chạy app
  await dotenv.load(fileName: ".env");

  // Khởi tạo Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteMate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ), 
      home: const MainShellScreen(),  // màn hình chính ban đầu của ứng dụng RouteMate. 
    );
  }
}