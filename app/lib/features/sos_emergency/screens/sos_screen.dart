import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'sos_history_screen.dart';

// Đảm bảo các đường dẫn import này khớp với dự án của bạn
import '../services/sos_service.dart';
import '../../group_radar/presentation/providers/members_provider.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  // 🔥 THÊM DÒNG NÀY VÀO ĐẦU LỚP
  String _roomId = "";
  late AnimationController _pulseController;   
  late AnimationController _rippleController;  
  Timer? _countdownTimer;                      
  double _currentProgress = 0.0;               
  bool _isHolding = false;                     

  // 🔥 Biến khóa trạng thái chặt chẽ (Logic mới)
  bool _isSending = false; 

  final SosService _sosService = SosService();

  @override
  void initState() {
    super.initState();
    // --- [KHÔI PHỤC] Khởi tạo Animations cũ ---
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    // -------------------------------------------
    
    _sosService.checkAndRequestPermissions();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<MembersProvider>(context, listen: false);
      if (mounted) {
        setState(() {
          _roomId = provider.roomId ?? "";
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _countdownTimer?.cancel();
    // -------------------------------------
    super.dispose();
  }

  // Hàm hiển thị thông báo SnackBar (Logic mới)
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
    if (_isSending) return; // Chặn bấm khi đang gửi (Logic mới)

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
          timer.cancel(); // Critical fix: dừng timer
          _currentProgress = 1.0; // clamp
          _executeSOS(); // Kích hoạt gửi
        }
      });
    });
  }

  void _stopCountdown() {
    if (_isSending) return; // Chặn thao tác khi đang gửi (Logic mới)
    _countdownTimer?.cancel();
    setState(() {
      _isHolding = false;
      _currentProgress = 0.0;
    });
    _rippleController.stop();
    _rippleController.reset();
  }
  // ----------------------------------------------------

  void _executeSOS() async {
    // Tạm dừng các Animations để chuyển sang trạng thái load mạng
    _countdownTimer?.cancel();
    setState(() {
      _isHolding = false;
      _rippleController.stop();
      _rippleController.reset();
      _currentProgress = 0.0; // Reset vòng đếm
    });

    if (_isSending) return; // Logic block

    final currentRoomId = Provider.of<MembersProvider>(context, listen: false).roomId;

    if (currentRoomId == null || currentRoomId.isEmpty) {
      _showStatus("⚠️ Không thể gửi: Bạn chưa tham gia vào đội nhóm nào!", Colors.orange);
      return;
    }

    // 1. Khóa UI (Logic mới chặt chẽ)
    setState(() => _isSending = true);
    _showStatus("Đang thu thập tọa độ và phát tín hiệu...", Colors.blue);

    // Rung liên tiếp 5 lần khi báo động (Logic cũ)
    for (int i = 0; i < 5; i++) {
      HapticFeedback.vibrate(); 
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // 2. Gọi Service và chờ kết quả Đỏ/Cam/Đen (Logic mới)
    await _sosService.sendEmergencySignal(
      roomId: currentRoomId, 
      onStatusUpdate: _showStatus,
    );

    // 3. Mở khóa UI sau khi hoàn tất
    if (mounted) {
      setState(() => _isSending = false);
    }
  }

 @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _isSending ? "ĐANG LIÊN LẠC ĐỘI CỨU HỘ..." : "HỖ TRỢ KHẨN CẤP", 
            style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold, 
              color: _isSending ? Colors.blue : Colors.black87,
            ),
          ),
          
          const SizedBox(height: 60),
          
          Stack(
            alignment: Alignment.center,
            children: [
              // 1. Hiệu ứng gợn sóng Ripple
              if (_isHolding && !_isSending)
                ScaleTransition(
                  scale: _rippleController,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(
                        (0.3 - (_rippleController.value * 0.3)).clamp(0.0, 0.3)
                      ),
                    ),
                  ),
                ),
              
              // 2. Vòng đếm ngược viền đỏ
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
              
              // 3. Nút bấm SOS chính
              _isSending 
                ? const SizedBox(
                    width: 150, height: 150,
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
                              color: Colors.red.withOpacity(0.4), 
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

              // 🔥 Nút lịch sử SOS (Đã sửa lỗi crash bằng cách truyền roomId trực tiếp)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.history, color: Colors.grey, size: 30),
                  tooltip: "Xem lịch sử SOS",
                  onPressed: () {
                    // THAY `_roomId` BẰNG BIẾN CHỨA ID PHÒNG CỦA BẠN
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SosHistoryScreen(roomId: _roomId), 
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 80),
          
          Text(
            _isSending ? "Vui lòng giữ bình tĩnh và chờ đợi..." : "NHẤN GIỮ ĐỂ GỬI TÍN HIỆU.", 
            style: const TextStyle(color: Colors.grey, letterSpacing: 1.5, fontSize: 12),
          ),
        ],
      ),
    );
  }
}