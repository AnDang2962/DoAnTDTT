import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:route_mate_app/features/main_map/main_map_screen.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';
import 'package:route_mate_app/features/group_radar/screens/room_lobby_screen.dart';

// 🔥 QUAN TRỌNG: Import thêm UI của M2 vào đây
import 'package:route_mate_app/features/map_routing/screens/routing_panel.dart';

// 1. IMPORT MÀN HÌNH LOBBY CỦA BẠN VÀO ĐÂY
import 'package:route_mate_app/features/sos_emergency/screens/sos_screen.dart';
// 🔥 THÊM 3 DÒNG NÀY ĐỂ FIX 3 LỖI ĐỎ TRONG ẢNH 🔥
import 'package:route_mate_app/features/group_radar/presentation/providers/members_provider.dart';
import 'package:route_mate_app/data/repositories/group_repository.dart';
import 'package:route_mate_app/core/services/location_service.dart';

// 🔥 THÊM THƯ VIỆN ĐỂ LẮNG NGHE THÔNG BÁO 🔥
// 🔥 CÁC THƯ VIỆN MỚI THÊM CHO TÍNH NĂNG NHẬN CẢNH BÁO SOS
import 'package:firebase_messaging/firebase_messaging.dart';
import '../sos_emergency/widgets/sos_map_overlay.dart' show SOSMapOverlay;

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  // CÁC TAB BÂY GIỜ CHỈ LÀ GIAO DIỆN TRONG SUỐT (Không chứa bản đồ)
  final List<Widget> _screens = [
    const SafeArea(child: RoutingPanel()), // Tab 0: Lớp UI Tìm đường của M2
    const RoomLobbyScreen(), // Tab 1: Lớp UI Radar của M3
    const SafeArea(child: SosScreen()),
  ];

  // 🔥 BẮT ĐẦU ĐOẠN CODE THÊM MỚI: ĐÓN THÔNG BÁO KHI ĐANG MỞ APP 🔥
  @override
  void initState() {
    super.initState();
    
    // 1. Xin quyền hiển thị thông báo (Cần thiết cho Android 13+)
    FirebaseMessaging.instance.requestPermission();

    // 2. Lắng nghe thông báo khi App đang mở (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🚨 Bắt được sóng SOS khi đang mở app!');
      
      // Bóc tách dữ liệu từ payload của tin nhắn
      final data = message.data;
      final double? lat = double.tryParse(data['lat']?.toString() ?? '');
      final double? lng = double.tryParse(data['lng']?.toString() ?? '');
      final String battery = data['battery']?.toString() ?? 'Không rõ';

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false, // Ép người dùng phải tương tác
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.red.shade50,
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
                SizedBox(width: 10),
                Text('BÁO ĐỘNG SOS!', style: TextStyle(color: Colors.red)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.notification?.body ?? 'Có thành viên trong đoàn đang gặp nguy hiểm!',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '🔋 Tình trạng pin nạn nhân: $battery%', 
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('BỎ QUA', style: TextStyle(color: Colors.grey)),
              ),
              // Chỉ hiện nút tới cứu nếu có tọa độ hợp lệ
              if (lat != null && lng != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    // Đóng hộp thoại
                    Navigator.of(dialogContext).pop(); 
                    
                    // Mở bản đồ dẫn đường
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SOSMapOverlay(
                          latitude: lat,
                          longitude: lng,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, color: Colors.white),
                  label: const Text('TỚI CỨU NGAY', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        );
      }
    });
  }
  // 🔥 KẾT THÚC ĐOẠN CODE THÊM MỚI 🔥

  @override
  Widget build(BuildContext context) {
    // 🔥 SỬA THÀNH MULTIPROVIDER Ở ĐÂY 🔥
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => MapStateProvider()),
        ChangeNotifierProvider(
          create: (context) => MembersProvider(
            repository: GroupRepository(),
            locationService: LocationService(),
          ),
        ),
      ],
      child: Scaffold(
        body: Stack(
          children: [
            // 1. LỚP NỀN DƯỚI CÙNG: Bản đồ duy nhất chạy 24/24
            const MainMapScreen(),

            // 2. LỚP KÍNH TRÊN CÙNG: Các Tab giao diện đè lên bản đồ
            IndexedStack(index: _currentIndex, children: _screens),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Bản đồ',
            ),
            NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Đội nhóm',
            ),
            NavigationDestination(
              icon: Icon(Icons.sos_outlined, color: Colors.red),
              selectedIcon: Icon(Icons.sos, color: Colors.red),
              label: 'SOS',
            ),
          ],
        ),
      ),
    );
  }
}
