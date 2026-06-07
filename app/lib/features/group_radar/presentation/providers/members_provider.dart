import 'package:flutter/material.dart';

class MembersProvider extends ChangeNotifier {
  String? _currentRoomId;

  String? get roomId => _currentRoomId;

  void updateRoomIdForSOS(String id) {
    _currentRoomId = id.isEmpty ? null : id;
  }
}
