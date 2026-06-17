import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sos_history_screen.dart';

import '../services/sos_service.dart';
import '../../group_radar/presentation/providers/members_provider.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  Timer? _countdownTimer;
  double _currentProgress = 0.0;
  bool _isHolding = false;
  bool _isSending = false;
  String? _pendingCallPhone;

  final SosService _sosService = SosService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _sosService.checkAndRequestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _rippleController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCallPhone != null) {
      final phone = _pendingCallPhone!;
      _pendingCallPhone = null;
      _sosService.makeCall(phone);
    }
  }

  Future<List<String>> _getEmergencyContacts() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final contacts = doc.data()?['emergencyContacts'];
      if (contacts is List) {
        return contacts.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('Lỗi lấy emergency contacts: $e');
    }
    return [];
  }

  void _showStatus(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _startCountdown() {
    if (_isSending) return;
    setState(() {
      _isHolding = true;
      _currentProgress = 0.0;
    });
    _rippleController.repeat();
    HapticFeedback.lightImpact();

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) return;
      setState(() {
        _currentProgress += 0.01;
        if (_currentProgress >= 1.0) {
          timer.cancel();
          _currentProgress = 1.0;
          _executeSOS();
        }
      });
    });
  }

  void _stopCountdown() {
    if (_isSending) return;
    _countdownTimer?.cancel();
    setState(() {
      _isHolding = false;
      _currentProgress = 0.0;
    });
    _rippleController.stop();
    _rippleController.reset();
  }

  void _executeSOS() async {
    _countdownTimer?.cancel();
    _rippleController.stop();
    _rippleController.reset();
    setState(() {
      _isHolding = false;
      _currentProgress = 0.0;
    });

    if (_isSending) return;

    final currentRoomId = Provider.of<MembersProvider>(context, listen: false).roomId;
    final leaderPhone = Provider.of<MembersProvider>(context, listen: false).leaderPhoneNumber ?? '';

    setState(() => _isSending = true);

    for (int i = 0; i < 5; i++) {
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    String? phoneToCall;
    if (currentRoomId == null || currentRoomId.isEmpty) {
      final contacts = await _getEmergencyContacts();
      phoneToCall = await _sosService.sendSoloEmergencySignal(
        emergencyContacts: contacts,
        onStatusUpdate: _showStatus,
      );
    } else {
      _showStatus('Đang thu thập tọa độ và phát tín hiệu...', Colors.blue);
      phoneToCall = await _sosService.sendEmergencySignal(
        roomId: currentRoomId,
        leaderPhoneNumber: leaderPhone,
        onStatusUpdate: _showStatus,
      );
    }

    // Đặt lại UI trước khi mở app ngoài để tránh màn hình đen khi quay lại
    if (mounted) setState(() => _isSending = false);

    // Gọi điện khi user quay lại từ app SMS (xử lý trong didChangeAppLifecycleState)
    if (phoneToCall != null) _pendingCallPhone = phoneToCall;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: double.infinity,
      color: _isSending ? Colors.red.withValues(alpha: 0.18) : Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _isSending ? 'ĐANG LIÊN LẠC ĐỘI CỨU HỘ...' : 'HỖ TRỢ KHẨN CẤP',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<MembersProvider>(
                  builder: (_, provider, _) {
                    final roomId = provider.roomId;
                    final inGroup = roomId != null && roomId.isNotEmpty;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: inGroup ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: inGroup ? Colors.greenAccent : Colors.orangeAccent,
                          width: 1.5,
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            inGroup ? Icons.group : Icons.group_off,
                            size: 18,
                            color: inGroup ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            inGroup ? 'Phòng: $roomId' : 'Chưa tham gia nhóm',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 52),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isHolding && !_isSending)
                      ScaleTransition(
                        scale: _rippleController,
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(
                              alpha: (0.3 - (_rippleController.value * 0.3)).clamp(0.0, 0.3),
                            ),
                          ),
                        ),
                      ),
                    if (!_isSending)
                      SizedBox(
                        width: 170,
                        height: 170,
                        child: CircularProgressIndicator(
                          value: _currentProgress,
                          strokeWidth: 8,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                        ),
                      ),
                    _isSending
                        ? const SizedBox(
                            width: 150,
                            height: 150,
                            child: CircularProgressIndicator(strokeWidth: 6, color: Colors.red),
                          )
                        : GestureDetector(
                            onTapDown: (_) => _startCountdown(),
                            onTapUp: (_) => _stopCountdown(),
                            onTapCancel: () => _stopCountdown(),
                            child: ScaleTransition(
                              scale: Tween(begin: 1.0, end: _isHolding ? 1.15 : 1.05).animate(_pulseController),
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.redAccent, Colors.red],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.6),
                                      blurRadius: _isHolding ? 40 : 20,
                                      spreadRadius: _isHolding ? 10 : 0,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'SOS',
                                    style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 80),
                Text(
                  _isSending ? 'Vui lòng giữ bình tĩnh và chờ đợi...' : 'NHẤN GIỮ ĐỂ GỬI TÍN HIỆU.',
                  style: const TextStyle(
                    color: Colors.white,
                    letterSpacing: 1.5,
                    fontSize: 12,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            top: 40,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.history, color: Colors.white, size: 26),
                tooltip: 'Xem lịch sử SOS',
                onPressed: () {
                  final currentRoomId =
                      Provider.of<MembersProvider>(context, listen: false).roomId ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SosHistoryScreen(roomId: currentRoomId)),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
