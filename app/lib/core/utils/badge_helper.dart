import 'package:flutter/material.dart';

class BadgeHelper {
  static Color ringColor(double? totalKm) {
    if (totalKm == null || totalKm < 100) return const Color(0xFFCD7F32); // Đồng
    if (totalKm < 500) return const Color(0xFFB0C4DE);                    // Bạc
    if (totalKm < 2000) return const Color(0xFFFFD700);                   // Vàng
    return const Color(0xFF00E5FF);                                        // Kim Cương
  }

  static String tierName(double? totalKm) {
    if (totalKm == null || totalKm < 100) return 'Đồng';
    if (totalKm < 500) return 'Bạc';
    if (totalKm < 2000) return 'Vàng';
    return 'Kim Cương';
  }

  static String badgeEmoji(double? totalKm) {
    if (totalKm == null || totalKm < 100) return '🥉';
    if (totalKm < 500) return '🥈';
    if (totalKm < 2000) return '🥇';
    return '💎';
  }

  // Màu ring theo vai trò, dùng khi chưa có dữ liệu km.
  static Color roleRingColor(String role) {
    switch (role.toLowerCase()) {
      case 'leader': return const Color(0xFF1565C0);
      case 'sweeper': return const Color(0xFF2E7D32);
      default: return const Color(0xFFE8650A);
    }
  }

  static String roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'leader': return 'L';
      case 'sweeper': return 'S';
      default: return '';
    }
  }
}
