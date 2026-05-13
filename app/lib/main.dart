import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';



void main() async {
  // Bắt buộc phải có dòng này khi khởi tạo các thư viện ngoài (như dotenv, Firebase...)
  WidgetsFlutterBinding.ensureInitialized();
  
  // Nạp Két sắt .env TRƯỚC KHI chạy app
  await dotenv.load(fileName: ".env");

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
      home: const Scaffold(
        body: Center(
          child: Text('RouteMate Core đã khởi tạo thành công!'),
        ),
      ),
    );
  }
}