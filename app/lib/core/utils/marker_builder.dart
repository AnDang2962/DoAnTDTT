import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Tiện ích hỗ trợ vẽ các điểm đánh dấu (Marker) trên bản đồ thành dạng hình ảnh (PNG).
/// Vì thư viện Mapbox 2.x yêu cầu hình ảnh cho các điểm đánh dấu (PointAnnotation),
/// chúng ta phải dùng code vẽ ra hình ảnh (như một bong bóng chat) thay vì dùng Widget của Flutter.
class MarkerBuilder {
  /// Hàm cốt lõi: Vẽ một bong bóng chung có chứa biểu tượng cảm xúc (emoji) và chữ.
  /// Hình dạng: Một hình chữ nhật bo tròn với cái đuôi nhọn trỏ xuống dưới.
  static Future<Uint8List> buildBubble({
    required String emoji,
    required String label,
    required Color color,
    double devicePixelRatio = 3.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const double bubbleWidth = 140.0;
    const double bubbleHeight = 56.0;
    const double tailHeight = 10.0;
    const double tailWidth = 16.0;
    const double cornerRadius = 16.0;

    canvas.scale(devicePixelRatio);

    // 1. Vẽ bóng đổ cho bong bóng để tạo độ nổi
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, bubbleWidth, bubbleHeight),
        const Radius.circular(cornerRadius),
      ),
      shadowPaint,
    );

    // 2. Vẽ hình nền của bong bóng với màu được chỉ định
    final bgPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
        const Radius.circular(cornerRadius),
      ),
      bgPaint,
    );

    // 3. Vẽ cái đuôi nhọn trỏ xuống điểm trên bản đồ
    // tailCenterX canh theo tâm ảnh (bubbleWidth + 4) / 2, không theo tâm bubble
    // để iconAnchor: BOTTOM ghim đúng đầu mũi nhọn vào tọa độ
    final tailPath = Path();
    final tailCenterX = (bubbleWidth + 4) / 2;
    const double imageHeight = bubbleHeight + tailHeight + 4;
    tailPath.moveTo(tailCenterX - tailWidth / 2, bubbleHeight - 1);
    tailPath.lineTo(tailCenterX, imageHeight);
    tailPath.lineTo(tailCenterX + tailWidth / 2, bubbleHeight - 1);
    tailPath.close();
    canvas.drawPath(tailPath, bgPaint);

    // 4. Vẽ Emoji (Biểu tượng) vào bên trái bong bóng
    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 26)),
      textDirection: TextDirection.ltr,
    );
    emojiPainter.layout();
    emojiPainter.paint(
      canvas,
      Offset(12, (bubbleHeight - emojiPainter.height) / 2),
    );

    // 5. Vẽ đoạn chữ (Label) vào bên phải Emoji
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              offset: Offset(0.5, 0.5),
              blurRadius: 1.5,
              color: Colors.black54,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    );
    labelPainter.layout(maxWidth: bubbleWidth - 50);
    labelPainter.paint(
      canvas,
      Offset(46, (bubbleHeight - labelPainter.height) / 2),
    );

    // Kết thúc việc vẽ và xuất ra dạng mảng byte (PNG)
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      ((bubbleWidth + 4) * devicePixelRatio).toInt(),
      ((bubbleHeight + tailHeight + 4) * devicePixelRatio).toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Vẽ bong bóng hiển thị Thời Tiết dọc đường đi.
  /// Nền màu trắng, viền xanh dương, hiển thị nhiệt độ và mô tả ngắn.
  static Future<Uint8List> buildWeatherBubble({
    required String temperature,
    required String description,
    double devicePixelRatio = 3.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const double bubbleWidth = 100.0;
    const double bubbleHeight = 44.0;
    const double tailHeight = 8.0;
    const double tailWidth = 12.0;
    const double cornerRadius = 12.0;

    canvas.scale(devicePixelRatio);

    // Bóng đổ
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, bubbleWidth, bubbleHeight),
        const Radius.circular(cornerRadius),
      ),
      shadowPaint,
    );

    // Nền trắng
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
        const Radius.circular(cornerRadius),
      ),
      bgPaint,
    );

    // Viền xanh
    final borderPaint = Paint()
      ..color = Colors.blue.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
        const Radius.circular(cornerRadius),
      ),
      borderPaint,
    );

    // Vẽ đuôi — canh tâm theo ảnh, tip tại đáy ảnh để iconAnchor: BOTTOM chính xác
    final tailPath = Path();
    final tailCenterX = (bubbleWidth + 4) / 2;
    const double imageHeight = bubbleHeight + tailHeight + 4;
    tailPath.moveTo(tailCenterX - tailWidth / 2, bubbleHeight - 1);
    tailPath.lineTo(tailCenterX, imageHeight);
    tailPath.lineTo(tailCenterX + tailWidth / 2, bubbleHeight - 1);
    tailPath.close();
    canvas.drawPath(tailPath, bgPaint);
    canvas.drawPath(tailPath, borderPaint);

    // Vẽ nhiệt độ (chữ xanh, in đậm)
    final tempPainter = TextPainter(
      text: TextSpan(
        text: temperature,
        style: TextStyle(
          color: Colors.blue.shade800,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tempPainter.layout();
    tempPainter.paint(canvas, const Offset(8, 4));

    // Vẽ mô tả thời tiết (chữ xám nhỏ)
    final descPainter = TextPainter(
      text: TextSpan(
        text: description,
        style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    descPainter.layout(maxWidth: bubbleWidth - 16);
    descPainter.paint(canvas, const Offset(8, 24));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      ((bubbleWidth + 4) * devicePixelRatio).toInt(),
      ((bubbleHeight + tailHeight + 4) * devicePixelRatio).toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Vẽ bong bóng đánh dấu Điểm Đến (Màu đỏ, biểu tượng 📍)
  static Future<Uint8List> buildDestinationBubble({
    required String label,
    double devicePixelRatio = 3.0,
  }) {
    return buildBubble(
      emoji: '📍',
      label: label.length > 14 ? '${label.substring(0, 14)}…' : label,
      color: Colors.red.shade600,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// Vẽ pin tròn dạng Apple Find My cho thành viên nhóm.
  /// Viền màu theo vai trò, ảnh đại diện (placeholder: bóng người xám).
  /// [avatarBytes]: ảnh thực từ login (để null dùng placeholder).
  static Future<Uint8List> buildMemberBubble({
    required String name,
    required String role,
    ui.Image? avatarImage,
    double devicePixelRatio = 3.0,
  }) async {
    const double R = 26.0;
    const double border = 3.5;
    const double innerR = R - border;
    const double tailH = 14.0;
    const double tailW = 13.0;
    const double topPad = 4.0;
    const double sidePad = 4.0;
    const double imgW = R * 2 + sidePad * 2;
    const double imgH = topPad + R * 2 + tailH;
    const double cx = imgW / 2;
    const double cy = topPad + R;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    Color borderColor;
    switch (role.toLowerCase()) {
      case 'leader':  borderColor = const Color(0xFF1F4E79); break;
      case 'sweeper': borderColor = const Color(0xFF2E7D32); break;
      default:        borderColor = const Color(0xFFF57C00);
    }

    // 1. Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(Offset(cx + 1, cy + 1), R, shadowPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx - tailW / 2, cy + R - 5)
        ..lineTo(cx + 1, imgH)
        ..lineTo(cx + tailW / 2, cy + R - 5)
        ..close(),
      shadowPaint,
    );

    // 2. Viền màu role (circle + tail cùng màu liền mạch)
    final borderPaint = Paint()..color = borderColor;
    canvas.drawCircle(Offset(cx, cy), R, borderPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx - tailW / 2, cy + R - 5)
        ..lineTo(cx, imgH)
        ..lineTo(cx + tailW / 2, cy + R - 5)
        ..close(),
      borderPaint,
    );

    // 3. Nền ảnh đại diện
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: innerR)));

    if (avatarImage != null) {
      // Ảnh thực: scale + center crop vào vòng tròn
      final src = Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble());
      final dst = Rect.fromCircle(center: Offset(cx, cy), radius: innerR);
      canvas.drawImageRect(avatarImage, src, dst, Paint());
    } else {
      // Placeholder: nền xám + bóng người
      canvas.drawCircle(Offset(cx, cy), innerR, Paint()..color = const Color(0xFFEEEEEE));
      final personPaint = Paint()..color = const Color(0xFF9E9E9E);
      // Đầu
      canvas.drawCircle(Offset(cx, cy - innerR * 0.18), innerR * 0.34, personPaint);
      // Thân/vai
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + innerR * 0.62),
          width: innerR * 1.5,
          height: innerR * 1.1,
        ),
        personPaint,
      );
    }

    canvas.restore();

    // 4. Viền trắng mỏng bên trong để tách avatar với border màu
    canvas.drawCircle(
      Offset(cx, cy),
      innerR,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (imgW * devicePixelRatio).toInt(),
      (imgH * devicePixelRatio).toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
