import 'package:flutter/material.dart';

class MembersProvider extends ChangeNotifier {
  String? _currentRoomId;
  String? _leaderPhoneNumber;

  String? get roomId => _currentRoomId;
  String? get leaderPhoneNumber => _leaderPhoneNumber;

  void updateRoomIdForSOS(String id) {
    _currentRoomId = id.isEmpty ? null : id;
  }
  void updateLeaderPhoneForSOS(String phoneNumber) {
    _leaderPhoneNumber = phoneNumber.isEmpty ? null : phoneNumber;
  }
}
