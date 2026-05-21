import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:route_mate_app/features/main_shell/main_shell_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  // Bắt buộc phải có dòng này khi khởi tạo các thư viện ngoài (như dotenv, Firebase...)
  WidgetsFlutterBinding.ensureInitialized();

  // Nạp Két sắt .env TRƯỚC KHI chạy app
  await dotenv.load(fileName: ".env");

  // Khởi tạo Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    print("Đang kết nối tới Firebase Emulator...");

    //String emulatorIp = '192.168.137.1';

    String emulatorIp= '192.168.0.101';

    FirebaseAuth.instance.useAuthEmulator(emulatorIp, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorIp, 8080);
    FirebaseDatabase.instance.useDatabaseEmulator(emulatorIp, 9000);

    FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).useFunctionsEmulator(emulatorIp, 5001);
  }

  // 🔥 THÊM ĐOẠN NÀY VÀO TRƯỚC KHI RUN APP 🔥
  if (FirebaseAuth.instance.currentUser == null) {
    print("Tiến hành đăng nhập ẩn danh để xin quyền Backend...");
    try {
      // Bắt buộc thêm .timeout để không bị kẹt màn hình đen
      await FirebaseAuth.instance.signInAnonymously().timeout(
        const Duration(seconds: 5),
      );
      print("Đăng nhập thành công!");
    } catch (e) {
      // Nếu 5 giây không kết nối được, in ra lỗi nhưng VẪN CHO CHẠY TIẾP
      print("Đăng nhập thất bại hoặc quá hạn 5 giây: $e");
    }
  }

  // Đảm bảo dòng này luôn được chạy tới
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RouteMate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home:
          const MainShellScreen(), // màn hình chính ban đầu của ứng dụng RouteMate.
    );
  }
}
