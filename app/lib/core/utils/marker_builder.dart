import 'dart:async';
import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class MarkerBuilder {
  static Future<Uint8List> buildBadgeMarker({
    required String emoji,
    required String label,
    required Color ringColor,
    double devicePixelRatio = 3.0,
  }) async {
    const double R = 22.0;
    const double innerR = R - 3.5;
    const double pillH = 22.0;
    const double pillW = 112.0;
    const double pillCorner = 11.0;
    const double gap = 5.0;
    const double topPad = 3.0;
    const double sidePad = 8.0;
    const double bottomPad = 3.0;

    const double imgW = pillW + sidePad * 2;
    const double imgH = topPad + pillH + gap + R * 2 + bottomPad;
    const double cx = imgW / 2;
    const double circleCY = topPad + pillH + gap + R;
    const double pillCY = topPad + pillH / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 1, pillCY + 1.5), width: pillW, height: pillH),
        const Radius.circular(pillCorner),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, pillCY), width: pillW, height: pillH),
        const Radius.circular(pillCorner),
      ),
      Paint()..color = ringColor,
    );

    final pillPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(offset: Offset(0.5, 0.5), blurRadius: 1.0, color: Colors.black38)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    pillPainter.layout(maxWidth: pillW - 14);
    pillPainter.paint(canvas, Offset(cx - pillPainter.width / 2, pillCY - pillPainter.height / 2));

    canvas.drawCircle(
      Offset(cx + 1.5, circleCY + 2.0),
      R,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawCircle(Offset(cx, circleCY), R, Paint()..color = ringColor);
    canvas.drawCircle(Offset(cx, circleCY), innerR, Paint()..color = Colors.white);

    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 22)),
      textDirection: TextDirection.ltr,
    );
    emojiPainter.layout();
    emojiPainter.paint(canvas, Offset(cx - emojiPainter.width / 2, circleCY - emojiPainter.height / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (imgW * devicePixelRatio).toInt(),
      (imgH * devicePixelRatio).toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<Uint8List> buildDestinationPin({
    double devicePixelRatio = 3.0,
  }) async {
    const double R = 24.0;
    const double dotR = 7.5;
    const double tailH = 20.0;
    const double pad = 10.0;
    const double imgW = R * 2 + pad * 2;
    const double imgH = pad + R * 2 + tailH;
    const double cx = imgW / 2;
    const double cy = pad + R;
    const double tipY = imgH;
    const Color red = Color(0xFFEA4335);
    const Color dot = Color(0xFF8B0000);

    final double d = R + tailH;
    final double hw = R * sqrt(d * d - R * R) / d;
    final double baseY = cy + R * R / d;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    final path = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - hw, baseY)
      ..arcToPoint(
        Offset(cx + hw, baseY),
        radius: Radius.circular(R),
        largeArc: true,
        clockwise: true,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = red);
    canvas.drawCircle(Offset(cx, cy), dotR, Paint()..color = dot);

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (imgW * devicePixelRatio).toInt(),
      (imgH * devicePixelRatio).toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<Uint8List> buildNavigationArrow({
    double devicePixelRatio = 3.0,
  }) async {
    const double size = 56.0;
    const double cx = size / 2;

    final path = Path()
      ..moveTo(cx, 5)
      ..lineTo(cx + 20, 51)
      ..lineTo(cx, 40)
      ..lineTo(cx - 20, 51)
      ..close();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    canvas.drawPath(
      Path()..addPath(path, const Offset(1.5, 2.0)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(cx, 5), const Offset(cx, 51),
          [const Color(0xFF1A73E8), const Color(0xFF1557B0)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (size * devicePixelRatio).toInt(),
      (size * devicePixelRatio).toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<Uint8List> buildWaypointPin(int number, {double devicePixelRatio = 3.0}) async {
    const double R = 22.0;
    const double tailH = 18.0;
    const double pad = 8.0;
    const double imgW = R * 2 + pad * 2;
    const double imgH = pad + R * 2 + tailH;
    const double cx = imgW / 2;
    const double cy = pad + R;
    const double tipY = imgH;
    const Color blue = Color(0xFF1A73E8);

    final double d = R + tailH;
    final double hw = R * sqrt(d * d - R * R) / d;
    final double baseY = cy + R * R / d;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    final path = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - hw, baseY)
      ..arcToPoint(Offset(cx + hw, baseY), radius: Radius.circular(R), largeArc: true, clockwise: true)
      ..close();
    canvas.drawPath(path, Paint()..color = blue);
    canvas.drawCircle(Offset(cx, cy), R * 0.55, Paint()..color = Colors.white);

    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(color: blue, fontSize: R * 0.85, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage((imgW * devicePixelRatio).toInt(), (imgH * devicePixelRatio).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<Uint8List> buildMemberBubble({
    required Color ringColor,
    String roleLabel = '',
    ui.Image? avatarImage,
    double devicePixelRatio = 3.0,
  }) async {
    const double R = 26.0;
    const double innerR = 19.0;
    const double tailH = 22.0;
    const double topPad = 10.0;
    const double sidePad = 8.0;
    const double imgW = R * 2 + sidePad * 2;
    const double imgH = topPad + R * 2 + tailH;
    const double cx = imgW / 2;
    const double cy = topPad + R;
    const double tipY = imgH;

    final Color baseColor = ringColor;

    final pinPath = Path()
      ..moveTo(cx, tipY)
      ..cubicTo(cx - R * 0.25, tipY - tailH * 0.4, cx - R, cy + R * 0.65, cx - R, cy)
      ..arcToPoint(Offset(cx + R, cy), radius: Radius.circular(R), clockwise: false)
      ..cubicTo(cx + R, cy + R * 0.65, cx + R * 0.25, tipY - tailH * 0.4, cx, tipY)
      ..close();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(devicePixelRatio);

    canvas.drawPath(pinPath, Paint()..color = baseColor);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: innerR)));
    if (avatarImage != null) {
      canvas.drawImageRect(
        avatarImage,
        Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble()),
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
        Paint(),
      );
    } else {
      canvas.drawCircle(Offset(cx, cy), innerR, Paint()..color = Colors.white);
      final grey = Paint()..color = const Color(0xFF9E9E9E);
      canvas.drawCircle(Offset(cx, cy - innerR * 0.18), innerR * 0.38, grey);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + innerR * 0.60), width: innerR * 1.6, height: innerR * 1.1),
        grey,
      );
    }
    canvas.restore();

    canvas.drawCircle(
      Offset(cx, cy),
      innerR,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (roleLabel.isNotEmpty) {
      const double badgeR = 7.5;
      final bx = cx + innerR * 0.707;
      final by = cy + innerR * 0.707;

      canvas.drawCircle(Offset(bx, by), badgeR + 1.5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(bx, by), badgeR, Paint()..color = baseColor);

      final badgePainter = TextPainter(
        text: TextSpan(
          text: roleLabel,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      badgePainter.layout();
      badgePainter.paint(
        canvas,
        Offset(bx - badgePainter.width / 2, by - badgePainter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (imgW * devicePixelRatio).toInt(),
      (imgH * devicePixelRatio).toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
