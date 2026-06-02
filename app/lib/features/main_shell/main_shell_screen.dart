import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:route_mate_app/features/main_map/main_map_screen.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';
import 'package:route_mate_app/features/group_radar/screens/room_lobby_screen.dart';
import 'package:route_mate_app/features/map_routing/screens/routing_panel.dart';
import 'package:route_mate_app/features/sos_emergency/screens/sos_screen.dart';
import 'package:route_mate_app/features/group_radar/presentation/providers/members_provider.dart';
import 'package:route_mate_app/data/repositories/group_repository.dart';
import 'package:route_mate_app/core/services/location_service.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import '../sos_emergency/widgets/sos_map_overlay.dart' show SOSMapOverlay;

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const SafeArea(child: RoutingPanel()),
    const RoomLobbyScreen(),
    const SafeArea(child: SosScreen()),
  ];

  @override
  void initState() {
    super.initState();

    FirebaseMessaging.instance.requestPermission();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final double? lat = double.tryParse(data['lat']?.toString() ?? '');
      final double? lng = double.tryParse(data['lng']?.toString() ?? '');
      final String battery = data['battery']?.toString() ?? 'Không rõ';

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
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
                  'Pin nạn nhân: $battery%',
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('BỎ QUA', style: TextStyle(color: Colors.grey)),
              ),
              if (lat != null && lng != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
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

  @override
  Widget build(BuildContext context) {
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
            const MainMapScreen(),
            ...List.generate(_screens.length, (i) => AnimatedOpacity(
              opacity: i == _currentIndex ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: i != _currentIndex,
                child: _screens[i],
              ),
            )),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          backgroundColor: Colors.white,
          indicatorColor: Colors.blue.withValues(alpha: 0.12),
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
