import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:route_mate_app/core/theme/app_theme.dart';
import 'package:route_mate_app/features/main_map/main_map_screen.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';
import 'package:route_mate_app/features/group_radar/screens/room_lobby_screen.dart';
import 'package:route_mate_app/features/map_routing/screens/routing_panel.dart';
import 'package:route_mate_app/features/sos_emergency/screens/sos_screen.dart';
import 'package:route_mate_app/features/profile/screens/profile_screen.dart';
import 'package:route_mate_app/features/group_radar/presentation/providers/members_provider.dart';
import 'package:route_mate_app/core/services/solo_room_service.dart';
import 'package:route_mate_app/core/services/voice_service.dart';
import 'package:route_mate_app/core/services/wake_word_service.dart';
import 'package:route_mate_app/core/providers/voice_command_provider.dart';
import 'widgets/voice_fab.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import '../sos_emergency/widgets/sos_map_overlay.dart' show SOSMapOverlay;

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  final VoiceService _voiceService = VoiceService();
  final WakeWordService _wakeWord = WakeWordService();
  bool _isVoiceListening = false;
  BuildContext? _shellCtx; // Builder ctx — below MultiProvider, can read providers

  @override
  void initState() {
    super.initState();
    _voiceService.initialize();
    _wakeWord.addListener(_onWakeWordStateChanged);
    _wakeWord.onWakeWordDetected = _onWakeWordDetected;
    _wakeWord.init();
    SoloRoomService.ensureSoloRoom();
    FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onMessage.listen(_handleFcmMessage);
  }

  @override
  void dispose() {
    _wakeWord.removeListener(_onWakeWordStateChanged);
    _wakeWord.onWakeWordDetected = null;
    _voiceService.stopListening();
    super.dispose();
  }

  void _onWakeWordStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onWakeWordDetected() async {
    if (!mounted || _isVoiceListening) return;
    await _wakeWord.pauseForCommand();
    if (mounted) _startVoiceCommand();
  }

  Future<void> _startVoiceCommand() async {
    if (_isVoiceListening) return;
    setState(() => _isVoiceListening = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đang nghe... Hãy nói lệnh của bạn'),
        duration: Duration(seconds: 3),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || !_isVoiceListening) return;
    _voiceService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() => _isVoiceListening = false);
        unawaited(_wakeWord.resumeAfterCommand());
        final ctx = _shellCtx;
        if (ctx != null) _dispatchVoiceResult(ctx, text);
      },
      onDone: () {
        if (!mounted || !_isVoiceListening) return;
        setState(() => _isVoiceListening = false);
        if (_wakeWord.mode == VoiceMode.wakeWord) {
          unawaited(_wakeWord.resumeAfterCommand());
        }
      },
    ).catchError((_) {
      if (!mounted) return;
      setState(() => _isVoiceListening = false);
      if (_wakeWord.mode == VoiceMode.wakeWord) {
        unawaited(_wakeWord.resumeAfterCommand());
      }
    });
  }

  void _toggleVoice(BuildContext ctx) async {
    if (_isVoiceListening) {
      await _voiceService.stopListening();
      if (mounted) setState(() => _isVoiceListening = false);
      if (_wakeWord.mode == VoiceMode.wakeWord) {
        unawaited(_wakeWord.resumeAfterCommand());
      }
      return;
    }

    if (_wakeWord.mode == VoiceMode.wakeWord) {
      await _wakeWord.pauseForCommand();
      if (mounted) _startVoiceCommand();
      return;
    }

    setState(() => _isVoiceListening = true);
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Đang nghe... Hãy nói lệnh của bạn'),
        duration: Duration(seconds: 2),
      ),
    );
    await _voiceService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() => _isVoiceListening = false);
        _dispatchVoiceResult(ctx, text);
      },
      onDone: () {
        if (!mounted || !_isVoiceListening) return;
        setState(() => _isVoiceListening = false);
      },
    );
  }

  void _dispatchVoiceResult(BuildContext ctx, String text) {
    if (_currentIndex > 1) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Voice command không khả dụng ở tab này'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_currentIndex == 1 && !ctx.read<MapStateProvider>().isGroupModeActive) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Bạn chưa vào phòng nhóm, không thể thực hiện lệnh này'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    ctx.read<VoiceCommandProvider>().dispatch(text);
  }

  void _showModeToast(VoiceMode mode) {
    final msg = mode == VoiceMode.wakeWord
        ? 'Chế độ Wake Word — nói "routemate" để kích hoạt'
        : 'Chế độ Nhấn mic';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _handleFcmMessage(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    final double? lat = double.tryParse(data['lat']?.toString() ?? '');
    final double? lng = double.tryParse(data['lng']?.toString() ?? '');
    final String battery = data['battery']?.toString() ?? 'Không rõ';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    builder: (context) => SOSMapOverlay(latitude: lat, longitude: lng),
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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MapStateProvider()),
        ChangeNotifierProvider(create: (_) => MembersProvider()),
        ChangeNotifierProvider(create: (_) => VoiceCommandProvider()),
      ],
      child: Builder(builder: (ctx) {
        _shellCtx = ctx;
        final screens = [
          SafeArea(child: RoutingPanel(isActive: _currentIndex == 0)),
          const RoomLobbyScreen(),
          const ColoredBox(color: Colors.white, child: SafeArea(child: SosScreen())),
          const ProfileScreen(),
        ];

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              const MainMapScreen(),
              ...List.generate(
                screens.length,
                (i) => AnimatedOpacity(
                  opacity: i == _currentIndex ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: i != _currentIndex,
                    child: screens[i],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: VoiceFab(
            isListening: _isVoiceListening,
            mode: _wakeWord.mode,
            wakeState: _wakeWord.state,
            onTap: () => _toggleVoice(ctx),
            onSwitchToWake: () async {
              await _wakeWord.setMode(VoiceMode.wakeWord);
              if (mounted) _showModeToast(VoiceMode.wakeWord);
            },
            onSwitchToTap: () async {
              await _wakeWord.setMode(VoiceMode.tap);
              if (mounted) _showModeToast(VoiceMode.tap);
            },
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _BottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index == _currentIndex) return;
              if (_currentIndex == 1 &&
                  ctx.read<MapStateProvider>().isGroupModeActive &&
                  index != 2) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng rời phòng trước khi chuyển tab'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              setState(() => _currentIndex = index);
            },
          ),
        );
      }),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      color: Colors.white,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.map_outlined,
              activeIcon: Icons.map_rounded,
              label: 'Bản đồ',
              selected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              icon: Icons.people_outline_rounded,
              activeIcon: Icons.people_rounded,
              label: 'Nhóm',
              selected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            const SizedBox(width: 48),
            _SosNavItem(
              selected: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Hồ sơ',
              selected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? activeIcon : icon,
                key: ValueKey(selected),
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                size: 26,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosNavItem extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _SosNavItem({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppTheme.red : AppTheme.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'SOS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.red,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'SOS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: AppTheme.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
