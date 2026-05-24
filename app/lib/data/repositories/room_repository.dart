import 'dart:math'; // 🔥 THÊM THƯ VIỆN NÀY ĐỂ RANDOM
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'package:route_mate_app/services/firebase_functions_helper.dart';

/// Quản lý dữ liệu Phòng Phượt (Room), Lộ trình (Route) và Vị trí GPS (Location)
class RoomRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // Dù không dùng nữa nhưng cứ giữ lại để không bị lỗi các module khác
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// TẠO PHÒNG MỚI (Frontend tự sinh mã, ghi thẳng lên Firestore)
  Future<String?> createRoom(UserModel creator) async {
    try {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final random = Random();
      String roomId = '';
      bool isDuplicate = true;

      // Vòng lặp check trùng mã phòng
      while (isDuplicate) {
        roomId = String.fromCharCodes(
          Iterable.generate(
            6,
            (_) => chars.codeUnitAt(random.nextInt(chars.length)),
          ),
        );

        final docSnap = await _firestore.collection('rooms').doc(roomId).get();
        if (!docSnap.exists) {
          isDuplicate = false; // Mã sạch, an toàn để tạo
        }
      }

      // Ghi cấu trúc phòng lên Firestore
      await _firestore.collection('rooms').doc(roomId).set({
        'createdAt': FieldValue.serverTimestamp(),
        'creatorId': creator.id, // Lưu ID Leader để dễ quản lý sau này
        'status': 'active',
        'route': null,
        'memberInfo': {
          creator.id: {
            'displayName': creator.name,
            'role': creator.role == UserRole.leader ? 'leader' : 'member',
            'joinedAt': FieldValue.serverTimestamp(),
          },
        },
      });

      debugPrint(
        '[RoomRepository] Đã tạo phòng Client-side thành công: $roomId',
      );
      return roomId;
    } catch (e) {
      debugPrint('[RoomRepository] Lỗi mạng/Hệ thống khi tạo phòng: $e');
      return null;
    }
  }

  /// VÀO PHÒNG (Cập nhật trực tiếp lên Firestore)
  Future<bool> joinRoom(String roomId, UserModel user) async {
    try {
      final docRef = _firestore.collection('rooms').doc(roomId);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        debugPrint('Phòng không tồn tại!');
        return false;
      }

      // Cập nhật member mới vào Map memberInfo
      await docRef.update({
        'memberInfo.${user.id}': {
          'displayName': user.name,
          'role': user.role == UserRole.leader ? 'leader' : 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        },
      });
      return true;
    } catch (e) {
      debugPrint('Lỗi khi vào phòng: $e');
      return false;
    }
  }

  /// CHIA SẺ LỘ TRÌNH CHO CẢ NHÓM (Cập nhật trực tiếp lên Firestore)
  Future<double?> setRoomRoute({
    required String roomId,
    required List<Map<String, double>> polyline,
    required String startName,
    required String endName,
  }) async {
    try {
      // 🔥 M3 XỬ LÝ: Update route thẳng lên Firestore thay vì gọi Backend M5
      await _firestore.collection('rooms').doc(roomId).update({
        'route': {
          'polyline': polyline,
          'startName': startName,
          'endName': endName,
        },
      });

      debugPrint('[RoomRepository] Đã chia sẻ lộ trình cho nhóm');
      return 0.0; // Trả về 0 tạm thời vì M2 đã tự tính totalKm ở giao diện rồi
    } catch (e) {
      debugPrint('[RoomRepository] Lỗi khi set lộ trình: $e');
      return null;
    }
  }

  /// BẮN TỌA ĐỘ LÊN MÁY CHỦ (Realtime Database)
  Future<void> updateUserLocation(
    String roomId,
    String userId,
    double lat,
    double lng,
  ) async {
    try {
      final ref = _rtdb.ref('gps/$roomId/$userId');

      // Xóa điểm GPS nếu rớt mạng (Chống "Bóng ma")
      await ref.onDisconnect().remove();

      await ref.set({
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Lỗi cập nhật vị trí GPS: $e');
    }
  }

  /// LẮNG NGHE VỊ TRÍ CỦA TẤT CẢ THÀNH VIÊN (Realtime)
  Stream<Map<String, dynamic>> listenToRoomLocations(String roomId) {
    return _rtdb.ref('gps/$roomId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      return Map<String, dynamic>.from(data as Map);
    });
  }

  /// LẮNG NGHE SỰ THAY ĐỔI CỦA PHÒNG (Lộ trình mới, Thành viên mới)
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToRoomData(
    String roomId,
  ) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }
}
