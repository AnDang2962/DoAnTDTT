import 'package:flutter/material.dart';

class MembersProvider extends ChangeNotifier {
  String? _currentRoomId;
  String? _leaderPhoneNumber;
  String? _userRole;

  String? get roomId => _currentRoomId;
  String? get leaderPhoneNumber => _leaderPhoneNumber;
  String? get userRole => _userRole;

  void updateRoomIdForSOS(String id) {
    _currentRoomId = id.isEmpty ? null : id;
    notifyListeners();
  }
  void updateLeaderPhoneForSOS(String phoneNumber) {
    _leaderPhoneNumber = phoneNumber.isEmpty ? null : phoneNumber;
    notifyListeners();
  }
  void updateUserRole(String role) {
    _userRole = role.isEmpty ? null : role;
    notifyListeners();
  }
}
