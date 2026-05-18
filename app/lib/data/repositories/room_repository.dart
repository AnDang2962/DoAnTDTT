import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

/// Quản lý dữ liệu Phòng Phượt (Room), Lộ trình (Route) và Vị trí GPS (Location)
class RoomRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  
  // Trỏ thẳng đến khu vực chứa Cloud Function (asia-southeast1 để giảm độ trễ)
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// TẠO PHÒNG MỚI (Sử dụng Backend Cloud Function)
  /// Backend sẽ tự động sinh ID ngắn (6 ký tự) và khởi tạo cấu trúc dữ liệu chuẩn.
  Future<String?> createRoom(UserModel creator) async {
    try {
      final result = await _functions
          .httpsCallable('createRoom')
          .call<Map<String, dynamic>>({
        'displayName': creator.name,
        // Cấp 1 token ảo vì app chúng ta chưa cài đặt nhận thông báo Push Notification thật
        'fcmToken': 'fake-fcm-token-pa4-demo-1234567890', 
      });
      
      final roomId = result.data['roomId'] as String;
      debugPrint('[RoomRepository] Đã tạo phòng: $roomId');
      return roomId;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RoomRepository] Lỗi Backend khi tạo phòng: ${e.code} - ${e.message}');
      return null;
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

      // Theo chuẩn Demo, Backend dùng cấu trúc Map 'memberInfo' thay vì List
      await docRef.update({
        'memberInfo.${user.id}': {
          'displayName': user.name,
          'role': user.role == UserRole.leader ? 'leader' : 'member',
          'fcmToken': 'fake-fcm-token-pa4-demo-1234567890',
        }
      });
      return true;
    } catch (e) {
      debugPrint('Lỗi khi vào phòng: $e');
      return false;
    }
  }

  /// CHIA SẺ LỘ TRÌNH CHO CẢ NHÓM (Sử dụng Backend Cloud Function)
  /// Chỉ Leader mới được gọi hàm này. Backend sẽ lưu lộ trình và tự thông báo cho các máy khác.
  Future<double?> setRoomRoute({
    required String roomId,
    required List<Map<String, double>> polyline,
    required String startName,
    required String endName,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('setRoomRoute')
          .call<Map<String, dynamic>>({
        'roomId': roomId,
        'route': {
          'polyline': polyline,
          'startName': startName,
          'endName': endName,
        },
      });
      
      final totalKm = (result.data['totalDistanceKm'] as num).toDouble();
      debugPrint('[RoomRepository] Đã set lộ trình -> Dài $totalKm km');
      return totalKm;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RoomRepository] Lỗi Backend khi set lộ trình: ${e.code} - ${e.message}');
      return null;
    }
  }

  /// BẮN TỌA ĐỘ LÊN MÁY CHỦ (Realtime Database)
  /// Dùng Realtime Database thay vì Firestore để tiết kiệm tiền và đạt tốc độ siêu nhanh (Ping < 50ms)
  Future<void> updateUserLocation(String roomId, String userId, double lat, double lng) async {
    try {
      final ref = _rtdb.ref('gps/$roomId/$userId');
      await ref.set({
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp, // Đóng dấu thời gian chuẩn của máy chủ
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

  /// LẮNG NGHE SỰ THAY ĐỔI CỦA PHÒNG (VD: Có lộ trình mới, Có thành viên mới)
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToRoomData(String roomId) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }
}
