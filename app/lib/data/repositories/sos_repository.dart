import 'package:cloud_firestore/cloud_firestore.dart';

class SosRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Triggers an SOS alert
  /// Khi ghi vào đây, Cloud Function (file sos.ts trên server) sẽ tự động bắt sự kiện 
  /// và bắn thông báo Push Notification (FCM) đến tất cả anh em trong phòng.
  Future<bool> triggerSosAlert({
    required String roomId,
    required String userId,
    required double lat,
    required double lng,
  }) async {
    try {
      final alertData = {
        'roomId': roomId,
        'userId': userId,
        'lat': lat,
        'lng': lng,
        'type': 'sos', // Phân biệt với các cảnh báo AI khác
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Ghi vào collection 'alerts' trên Firestore
      await _firestore.collection('alerts').add(alertData);
      
      return true;
    } catch (e) {
      print('Lỗi khi gửi SOS: $e');
      return false;
    }
  }

  /// Gets SOS history (Lịch sử các lần bấm SOS của một phòng)
  Future<List<Map<String, dynamic>>> getSosHistory(String roomId) async {
    try {
      // Truy vấn tìm tất cả cảnh báo SOS của phòng này, sắp xếp mới nhất lên đầu
      final querySnapshot = await _firestore
          .collection('alerts')
          .where('roomId', isEqualTo: roomId)
          .where('type', isEqualTo: 'sos')
          .orderBy('createdAt', descending: true)
          .get();

      // Chuyển đổi dữ liệu trả về List<Map>
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Lưu thêm ID của Document nếu cần
        return data;
      }).toList();
    } catch (e) {
      print('Lỗi khi lấy lịch sử SOS: $e');
      return [];
    }
  }
}
