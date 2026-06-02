import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'package:route_mate_app/core/services/firebase_functions_helper.dart';

/// Quản lý dữ liệu Phòng Phượt (Room) — KIẾN TRÚC BACKEND-DRIVEN
///
/// Tất cả thao tác thay đổi DB (create/join/setRoute/leave) đều qua
/// Cloud Functions backend, không bypass Firestore từ client.
///
/// Lý do:
/// - Tránh race condition (2 leader cùng tạo phòng mã trùng nhau)
/// - Bảo mật: backend assertLeader, validate input, encode rules
/// - Sẵn sàng deploy production sau này (không cần refactor)
///
/// Pattern direct (RTDB GPS + Firestore listener) vẫn giữ vì:
/// - GPS streaming cần latency thấp, không qua Cloud Functions
/// - Listener Firestore là cách chuẩn để sync data đến client
class RoomRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // ============================================================
  // === BACKEND CALLS (gọi Cloud Functions) ===
  // ============================================================

  /// TẠO PHÒNG MỚI — gọi Cloud Function `createRoom`
  ///
  /// Backend thực hiện:
  ///   1. Sinh mã 6 ký tự ngẫu nhiên (loại trừ O, I, 0, 1 — dễ nhầm)
  ///   2. Loop với transaction tránh race condition mã trùng
  ///   3. Tạo doc rooms/{roomId} với leaderId = auth.uid
  ///   4. Set node roomMembers/{roomId}/{uid} trên RTDB
  ///
  /// Returns: roomId 6 ký tự nếu thành công, null nếu fail.
  Future<String?> createRoom(UserModel creator) async {
    try {
      final result = await backendFunctions
          .httpsCallable('createRoom')
          .call<Map<String, dynamic>>({
        'displayName': creator.name,
        'fcmToken': 'demo_fake_fcm_${DateTime.now().millisecondsSinceEpoch}',
      });

      final data = Map<String, dynamic>.from(result.data);
      final roomId = data['roomId']?.toString();

      debugPrint('[RoomRepository] ✓ Đã tạo phòng qua backend: $roomId');
      return roomId;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[RoomRepository] ✗ Backend createRoom error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[RoomRepository] ✗ Lỗi mạng khi tạo phòng: $e');
      return null;
    }
  }

  /// VÀO PHÒNG — gọi Cloud Function `joinRoom`
  ///
  /// Backend thực hiện:
  ///   1. Verify mã phòng tồn tại (throw not-found nếu invalid)
  ///   2. Check phòng active
  ///   3. Add auth.uid vào members + memberInfo
  ///   4. Set roomMembers/{roomId}/{uid} trên RTDB
  Future<bool> joinRoom(String roomId, UserModel user) async {
    try {
      await backendFunctions
          .httpsCallable('joinRoom')
          .call<Map<String, dynamic>>({
        'roomId': roomId.toUpperCase(), // backend lưu UPPERCASE
        'displayName': user.name,
        'fcmToken': 'demo_fake_fcm_${DateTime.now().millisecondsSinceEpoch}',
      });

      debugPrint('[RoomRepository] ✓ Đã vào phòng: $roomId');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[RoomRepository] ✗ Backend joinRoom error: ${e.code} - ${e.message}');

      if (e.code == 'not-found') {
        debugPrint('  → Mã phòng không tồn tại');
      } else if (e.code == 'failed-precondition') {
        debugPrint('  → ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('[RoomRepository] ✗ Lỗi mạng khi vào phòng: $e');
      return false;
    }
  }

  /// CHIA SẺ LỘ TRÌNH — gọi Cloud Function `setRoomRoute`
  ///
  /// Backend thực hiện:
  ///   1. assertLeader (chỉ Leader mới được set route)
  ///   2. Tính totalDistanceKm với Haversine formula
  ///   3. Update rooms/{roomId}.route trên Firestore
  ///   4. Members tự nhận update qua Firestore listener
  Future<double?> setRoomRoute({
    required String roomId,
    required List<Map<String, double>> polyline,
    required String startName,
    required String endName,
  }) async {
    try {
      final result = await backendFunctions
          .httpsCallable('setRoomRoute')
          .call<Map<String, dynamic>>({
        'roomId': roomId,
        'route': {
          'polyline': polyline,
          'startName': startName,
          'endName': endName,
        },
      });

      final data = Map<String, dynamic>.from(result.data);
      final totalKm = (data['totalDistanceKm'] as num?)?.toDouble() ?? 0.0;

      debugPrint(
          '[RoomRepository] ✓ Đã chia sẻ lộ trình: ${totalKm.toStringAsFixed(1)} km');
      return totalKm;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[RoomRepository] ✗ Backend setRoomRoute error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[RoomRepository] ✗ Lỗi khi set lộ trình: $e');
      return null;
    }
  }

  /// RỜI PHÒNG — gọi Cloud Function `leaveRoom`
  ///
  /// Note: Leader KHÔNG được rời (backend throw failed-precondition).
  /// Trong UI nên ẩn nút "Rời phòng" với Leader.
  Future<bool> leaveRoom(String roomId) async {
    try {
      await backendFunctions
          .httpsCallable('leaveRoom')
          .call<Map<String, dynamic>>({
        'roomId': roomId,
      });

      debugPrint('[RoomRepository] ✓ Đã rời phòng');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[RoomRepository] ✗ Backend leaveRoom error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[RoomRepository] ✗ Lỗi khi rời phòng: $e');
      return false;
    }
  }

  // ============================================================
  // === DIRECT FIREBASE CALLS (đúng pattern, không cần backend) ===
  // ============================================================

  /// BẮN TỌA ĐỘ LÊN RTDB
  ///
  /// GPS streaming dùng RTDB direct (không qua Cloud Functions):
  /// - Latency thấp (<1s)
  /// - Backend rules check membership từ roomMembers/{roomId}/{uid}
  /// - onDisconnect tự xóa khi rớt mạng
  Future<void> updateUserLocation(
    String roomId,
    String userId,
    double lat,
    double lng,
  ) async {
    try {
      final ref = _rtdb.ref('gps/$roomId/$userId');

      // Auto cleanup khi rớt mạng (chống "Ghost bubble")
      await ref.onDisconnect().remove();

      await ref.set({
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[RoomRepository] Lỗi cập nhật GPS: $e');
    }
  }

  /// LẮNG NGHE GPS THỜI GIAN THỰC CỦA TẤT CẢ THÀNH VIÊN
  Stream<Map<String, dynamic>> listenToRoomLocations(String roomId) {
    return _rtdb.ref('gps/$roomId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      return Map<String, dynamic>.from(data as Map);
    });
  }

  /// LẮNG NGHE PHÒNG THAY ĐỔI (lộ trình mới, member mới join)
  ///
  /// Firestore listener — cách chuẩn để frontend sync data từ DB,
  /// không cần qua Cloud Functions.
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToRoomData(
    String roomId,
  ) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }
}
