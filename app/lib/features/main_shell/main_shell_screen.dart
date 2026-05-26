import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:route_mate_app/features/main_map/main_map_screen.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';
import 'package:route_mate_app/features/group_radar/screens/room_lobby_screen.dart';

// 🔥 QUAN TRỌNG: Import thêm UI của M2 vào đây
import 'package:route_mate_app/features/map_routing/screens/routing_panel.dart';

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
    const Center(child: Text('Khu vực SOS của M4')), // Tab 2: SOS của M4
  ];

  @override
  Widget build(BuildContext context) {
    // Đưa Provider ra ngoài cùng để mọi Tab đều gọi được hàm vẽ Marker
    return ChangeNotifierProvider(
      create: (context) => MapStateProvider(),
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
