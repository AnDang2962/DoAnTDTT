import 'package:flutter/material.dart';

class BadgeHelper {
  /// Xác định Cấp độ Huy hiệu dựa trên số Km đã đi.
  /// 0: Mới (0 - 49km)
  /// 1: Đồng (50 - 199km)
  /// 2: Bạc (200 - 499km)
  /// 3: Vàng (500 - 999km)
  /// 4: Bạch Kim (1000km+)
  static int getBadgeLevel(double totalKm) {
    if (totalKm >= 1000) return 4;
    if (totalKm >= 500) return 3;
    if (totalKm >= 200) return 2;
    if (totalKm >= 50) return 1;
    return 0;
  }

  /// Trả về màu sắc viền dựa trên Cấp độ Huy hiệu
  static Color getBadgeColor(int badgeLevel) {
    switch (badgeLevel) {
      case 4:
        return const Color(0xFFE5E4E2); // Platinum / Bạch Kim
      case 3:
        return const Color(0xFFFFD700); // Gold / Vàng
      case 2:
        return const Color(0xFFC0C0C0); // Silver / Bạc
      case 1:
        return const Color(0xFFCD7F32); // Bronze / Đồng
      case 0:
      default:
        return Colors.white; // Bình thường
    }
  }

  /// Trả về tên của Huy hiệu
  static String getBadgeName(int badgeLevel) {
    switch (badgeLevel) {
      case 4:
        return 'Phượt Thủ Bạch Kim';
      case 3:
        return 'Phượt Thủ Vàng';
      case 2:
        return 'Tay Lái Bạc';
      case 1:
        return 'Tân Binh Đồng';
      case 0:
      default:
        return 'Thành Viên Mới';
    }
  }
}
