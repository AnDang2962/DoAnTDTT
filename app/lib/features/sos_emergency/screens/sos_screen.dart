import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'sos_history_screen.dart';

import '../services/sos_service.dart';
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
  bool _isSending = false;

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
    setState(() {
      _isHolding = false;
      _rippleController.stop();
      _rippleController.reset();
      _currentProgress = 0.0;
    });

    if (_isSending) return;

    final currentRoomId = Provider.of<MembersProvider>(context, listen: false).roomId;

    if (currentRoomId == null || currentRoomId.isEmpty) {
      _showStatus('Không thể gửi: Bạn chưa tham gia vào đội nhóm nào!', Colors.orange);
      return;
    }

    setState(() => _isSending = true);
    _showStatus('Đang thu thập tọa độ và phát tín hiệu...', Colors.blue);

    for (int i = 0; i < 5; i++) {
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    await _sosService.sendEmergencySignal(
      roomId: currentRoomId,
      onStatusUpdate: _showStatus,
    );

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: double.infinity,
      color: _isSending ? Colors.red.withValues(alpha: 0.18) : Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _isSending ? 'ĐANG LIÊN LẠC ĐỘI CỨU HỘ...' : 'HỖ TRỢ KHẨN CẤP',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
          const SizedBox(height: 8),
          Consumer<MembersProvider>(
            builder: (_, provider, __) {
              final roomId = provider.roomId;
              final inGroup = roomId != null && roomId.isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: inGroup
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: inGroup ? Colors.green : Colors.orange),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      inGroup ? Icons.group : Icons.group_off,
                      size: 16,
                      color: inGroup ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      inGroup ? 'Phòng: $roomId' : 'Chưa tham gia nhóm',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: inGroup ? Colors.green[700] : Colors.orange[700],
                      ),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                        color: Colors.red,
                      ),
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
                              'SOS',
                              style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.history, color: Colors.grey, size: 30),
                  tooltip: 'Xem lịch sử SOS',
                  onPressed: () {
                    final currentRoomId =
                        Provider.of<MembersProvider>(context, listen: false).roomId ?? '';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SosHistoryScreen(roomId: currentRoomId),
                      ),
                    );
                  },
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
    );
  }
}

