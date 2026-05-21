import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/sos_service.dart'; // Nối với file Service vừa tạo
import 'package:provider/provider.dart';
import '../../group_radar/presentation/providers/members_provider.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rippleController;
  Timer? _countdownTimer;
  double _currentProgress = 0.0;
  bool _isHolding = false;

  final SosService _sosService = SosService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _sosService.checkAndRequestPermissions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _showStatus(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: color, 
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startCountdown() {
    setState(() { _isHolding = true; _currentProgress = 0.0; });
    _rippleController.repeat();
    HapticFeedback.heavyImpact(); 

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        _currentProgress += 0.01;
        if (timer.tick % 10 == 0) HapticFeedback.selectionClick();
        if (_currentProgress >= 1.0) _executeSOS();
      });
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _rippleController.stop();
    _rippleController.reset();
    setState(() { _isHolding = false; _currentProgress = 0.0; });
  }

  void _executeSOS() async {
    _stopCountdown();
    for (int i = 0; i < 5; i++) {
      HapticFeedback.vibrate(); 
      await Future.delayed(const Duration(milliseconds: 150));
    }
    
    // 1. Rút ID nhóm động từ Provider của M3
    final currentRoomId = Provider.of<MembersProvider>(context, listen: false).roomId;

    // Đảm bảo an toàn nếu chưa vào phòng
    if (currentRoomId.isEmpty) {
      _showStatus("Lỗi: Chưa có thông tin nhóm!", Colors.red);
      return;
    }

    // 2. Chuyển giao nhiệm vụ bắn tín hiệu cho Service kèm roomId
    await _sosService.sendEmergencySignal(
      roomId: currentRoomId,
      onStatusUpdate: _showStatus,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center, // Đảm bảo căn giữa theo chiều ngang
        children: [
          Text(
            _isHolding ? "GIỮ ĐỂ PHÁT TÍN HIỆU" : "HỖ TRỢ KHẨN CẤP", 
            style: TextStyle(
              fontSize: 22, 
              fontWeight: FontWeight.bold, 
              color: _isHolding ? Colors.red : Colors.black87,
            ),
          ),
          const SizedBox(height: 60),
          Stack(
            alignment: Alignment.center,
            children: [
              if (_isHolding)
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _rippleController,
                    builder: (context, child) {
                      double progress = (_rippleController.value + (index / 3)) % 1.0;
                      return Container(
                        width: 150 + (progress * 180), 
                        height: 150 + (progress * 180),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          color: Colors.red.withValues(alpha: 1.0 - progress),
                        ),
                      );
                    },
                  );
                }),
              SizedBox(
                width: 175, 
                height: 175,
                child: CircularProgressIndicator(
                  value: _currentProgress, 
                  strokeWidth: 8,
                  backgroundColor: _isHolding ? Colors.red.withValues(alpha: 0.1) : Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                ),
              ),
              GestureDetector(
                onTapDown: (_) => _startCountdown(),
                onTapUp: (_) => _stopCountdown(),
                onTapCancel: () => _stopCountdown(),
                child: ScaleTransition(
                  scale: Tween(begin: 1.0, end: _isHolding ? 1.15 : 1.05).animate(_pulseController),
                  child: Container(
                    width: 150, 
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.red, 
                      shape: BoxShape.circle, 
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4), 
                          blurRadius: _isHolding ? 40 : 20,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "SOS", 
                        style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 80),
          const Text(
            "NHẤN GIỮ ĐỂ GỬI TÍN HIỆU.", 
            style: TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12),
          ),
        ],
      ),
    );
  }
}