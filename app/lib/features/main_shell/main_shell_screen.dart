import 'package:flutter/material.dart';
import 'package:route_mate_app/features/main_map/main_map_screen.dart';
import 'package:provider/provider.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  // Biến lưu trữ vị trí Tab đang được chọn (Mặc định là 0 - Bản đồ)
  int _currentIndex = 0;

  // Danh sách các màn hình chờ anh em nhét code vào
  final List<Widget> _screens = [
    // Lô 1: Tab Bản đồ (M2) - ĐÃ ĐƯỢC BỌC KHO DỮ LIỆU PROVIDER
    ChangeNotifierProvider(
      create: (context) => MapStateProvider(),
      child: const MainMapScreen(),
    ),
    
    // Lô 2: Tab Đội nhóm (M3)
    const Center(
      child: Text(
        'RoomScreen\n(Khu vực của M3)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ),
    
    // Lô 3: Tab SOS (M4)
    const Center(
      child: Text(
        'SosHistoryScreen\n(Khu vực của M4)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Hiển thị màn hình tương ứng với Tab đang chọn
      body: _screens[_currentIndex],
      
      // Thanh điều hướng bên dưới
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
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
    );
  }
}