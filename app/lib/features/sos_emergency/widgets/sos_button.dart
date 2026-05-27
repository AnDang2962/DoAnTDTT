import 'package:flutter/material.dart';

class SOSButton extends StatefulWidget {
  final VoidCallback onSOSTriggered;

  const SOSButton({super.key, required this.onSOSTriggered});

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

// 🔥 ĐỔI THÀNH TickerProviderStateMixin ĐỂ CHẠY 2 ANIMATION CÙNG LÚC
class _SOSButtonState extends State<SOSButton>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _rippleController; // 🔥 Thêm Controller cho gợn sóng
  bool _isHolding = false;

  static const Duration holdDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: holdDuration,
    );

    // 🔥 Khởi tạo hiệu ứng gợn sóng (tỏa ra trong 1 giây)
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerSOS();
      }
    });
  }

  void _startHolding() {
    setState(() => _isHolding = true);
    _controller.forward(from: 0);
    _rippleController.repeat(); // 🔥 Bắt đầu tỏa gợn sóng
  }

  void _cancelHolding() {
    if (!_isHolding) return;

    setState(() => _isHolding = false);
    _controller.stop();
    _controller.reset();
    
    _rippleController.stop(); // 🔥 Dừng gợn sóng
    _rippleController.reset();
  }

  void _triggerSOS() {
    setState(() => _isHolding = false);
    _controller.reset();
    
    _rippleController.stop(); // 🔥 Dừng gợn sóng khi đã gửi
    _rippleController.reset();
    
    widget.onSOSTriggered();
  }

  @override
  void dispose() {
    _controller.dispose();
    _rippleController.dispose(); // 🔥 Giải phóng bộ nhớ
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHolding(),
      onLongPressEnd: (_) => _cancelHolding(),
      onLongPressCancel: _cancelHolding,
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none, // 🔥 Cho phép gợn sóng tỏa ra ngoài viền 120px mà không bị cắt
          children: [
            // 🔥 THÊM GỢN SÓNG VÀO DƯỚI CÙNG (Dưới vòng đếm ngược và nút)
            if (_isHolding)
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, child) {
                  return Container(
                    // Kích thước tỏa từ 90 (bằng nút thật) to dần ra 160
                    width: 90 + (_rippleController.value * 70),
                    height: 90 + (_rippleController.value * 70),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Màu đỏ nhạt dần khi tỏa ra xa
                      color: Colors.red.withValues(
                        alpha: (0.4 - (_rippleController.value * 0.4)).clamp(0.0, 1.0),
                      ),
                    ),
                  );
                },
              ),

            // Vòng tròn đếm ngược (Giữ nguyên)
            if (_isHolding)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(120, 120),
                    painter: _ProgressPainter(_controller.value),
                  );
                },
              ),

            // Nút SOS (Giữ nguyên)
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                "SOS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;

  _ProgressPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final progressPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // vòng nền
    canvas.drawCircle(center, radius, basePaint);

    // vòng tiến trình
    final sweepAngle = 2 * 3.1416 * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.1416 / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}