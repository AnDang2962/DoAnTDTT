import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:provider/provider.dart';
import 'package:route_mate_app/core/theme/theme_provider.dart';
import 'package:route_mate_app/features/auth/screens/auth_wrapper.dart';
import 'firebase_options.dart';

/// =========================================================
/// EMULATOR SWITCH — Connect frontend với backend emulator
/// =========================================================
///
/// CÁCH DÙNG:
///   - Debug (mặc định): tự động dùng emulator
///     $ flutter run
///
///   - Release + emulator (cho demo 2 máy thật):
///     $ flutter run --release \
///         --dart-define=USE_EMULATOR=true \
///         --dart-define=MAC_LAN_IP=192.168.1.29
///
///   - Production (sau này khi deploy backend):
///     $ flutter run --release
///
/// QUAN TRỌNG: IP Mac phải khớp với máy chạy emulator.
/// Verify bằng lệnh: ipconfig getifaddr en0
const bool _useEmulator =
    bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);
const String _macLanIp =
    String.fromEnvironment('MAC_LAN_IP', defaultValue: '192.168.1.29');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // === 1. Load .env + Mapbox token ===
  try {
    await dotenv.load(fileName: ".env");
    MapboxOptions.setAccessToken(dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '');
    debugPrint('✓ Mapbox token set');
  } catch (e) {
    debugPrint('⚠ Lỗi load .env: $e');
  }

  // === 2. Firebase init ===
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // === 3. Connect emulator (FIX: cloud_firestore/unavailable) ===
  if (_useEmulator) {
    final String host;
    if (kIsWeb) {
      host = '127.0.0.1';
    } else if (Platform.isAndroid) {
      // 10.0.2.2 là localhost của máy tính khi chạy trên máy ảo Android
      host = '10.0.2.2';
    } else if (Platform.isIOS) {
      host = _macLanIp;
    } else {
      host = '127.0.0.1';
    }

    try {
      // QUAN TRỌNG: Functions phải dùng region 'asia-southeast1' (backend deploy ở đây)
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .useFunctionsEmulator(host, 5001);
      // NOTE: Auth KHÔNG dùng emulator để Google Sign-In hoạt động bình thường
      // await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseDatabase.instance.useDatabaseEmulator(host, 9000);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

      debugPrint('✓ Connected to Firebase emulators at $host');
      debugPrint('  Mode: ${kDebugMode ? "DEBUG" : "RELEASE"} + emulator');
    } catch (e) {
      debugPrint('⚠ Lỗi connect emulator: $e');
    }

    // Sign-out token cũ (FIX: INVALID_REFRESH_TOKEN sau khi emulator restart)
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('⚠ Sign-out cũ failed: $e');
    }
  } else {
    debugPrint('▶ PRODUCTION mode — không connect emulator');
  }

  // === 4. Đã bỏ Anonymous sign-in và SoloRoom init ở đây ===
  // SoloRoomService.ensureSoloRoom() sẽ được gọi trong MainShellScreen.


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'RouteMate',
            theme: themeProvider.currentTheme,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}
