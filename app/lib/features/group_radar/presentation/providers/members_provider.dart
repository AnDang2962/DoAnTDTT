import 'package:flutter/material.dart';

class MembersProvider extends ChangeNotifier {
  String? _currentRoomId;
// 🔥 MỚI THÊM: Biến lưu trữ số điện thoại của Leader để dùng khi mất mạng
  String? _leaderPhoneNumber;

  String? get roomId => _currentRoomId;
  // 🔥 MỚI THÊM: Cổng xuất dữ liệu cho số điện thoại
  String? get leaderPhoneNumber => _leaderPhoneNumber;

  void updateRoomIdForSOS(String id) {
    _currentRoomId = id.isEmpty ? null : id;
  }
  void updateLeaderPhoneForSOS(String phoneNumber) {
    _leaderPhoneNumber = phoneNumber.isEmpty ? null : phoneNumber;
  }
}
