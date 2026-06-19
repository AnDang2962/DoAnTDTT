import 'package:shared_preferences/shared_preferences.dart';

/// Lưu session phòng nhóm vào bộ nhớ cục bộ.
/// Khi user thoát app (kill process) rồi mở lại, session này cho phép
/// tự động quay lại phòng mà không cần nhập lại mã.
class RoomSessionService {
  static const _keyRoomId = 'session_room_id';
  static const _keyUserName = 'session_user_name';
  static const _keyUserRole = 'session_user_role';

  static Future<void> save({
    required String roomId,
    required String userName,
    required String userRole,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRoomId, roomId);
    await prefs.setString(_keyUserName, userName);
    await prefs.setString(_keyUserRole, userRole);
  }

  static Future<Map<String, String>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString(_keyRoomId);
    final userName = prefs.getString(_keyUserName);
    final userRole = prefs.getString(_keyUserRole);
    if (roomId == null || userName == null || userRole == null) return null;
    return {'roomId': roomId, 'userName': userName, 'userRole': userRole};
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRoomId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserRole);
  }
}
