import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

/// Model để đại diện cho thông tin GPS của một thành viên
class GpsData {
  final String userId;
  final LatLng location;
  final String role;
  final int timestamp;

  GpsData({
    required this.userId,
    required this.location,
    required this.role,
    required this.timestamp,
  });

  /// Tạo GpsData từ Map Firebase
  factory GpsData.fromMap(String userId, Map<dynamic, dynamic> data) {
    final lat = _parseDouble(data['lat']);
    final lng = _parseDouble(data['lng']);

    return GpsData(
      userId: userId,
      location: LatLng(lat ?? 0.0, lng ?? 0.0),
      role: data['role']?.toString() ?? 'Member',
      timestamp: (data['timestamp'] is int ? data['timestamp'] : 0) as int,
    );
  }

  /// Chuyển GpsData sang Map để lưu trữ trên Firebase
  Map<String, dynamic> toMap() {
    return {
      'lat': location.latitude,
      'lng': location.longitude,
      'role': role,
      'timestamp': timestamp,
    };
  }
}

/// GroupRepository: Tầng Data tương tác với Firebase Realtime Database
class GroupRepository {
  final FirebaseDatabase _firebaseDatabase;

  // Các biến để quản lý kết nối
  late DatabaseReference _gpsRef;
  StreamSubscription<DatabaseEvent>? _gpsSubscription;
  final _gpsStreamController = StreamController<List<GpsData>>.broadcast();

  GroupRepository({FirebaseDatabase? firebaseDatabase})
    : _firebaseDatabase = firebaseDatabase ?? FirebaseDatabase.instance;

  /// Stream để lắng nghe dữ liệu GPS từ phòng
  Stream<List<GpsData>> getGpsStream(String roomId) {
    // Đóng subscription cũ nếu có
    _gpsSubscription?.cancel();

    // Thiết lập reference mới
    _gpsRef = _firebaseDatabase.ref('gps/$roomId');

    // Lắng nghe thay đổi dữ liệu từ Firebase
    _gpsSubscription = _gpsRef.onValue.listen(
      (DatabaseEvent event) {
        final gpsDataList = <GpsData>[];

        final value = event.snapshot.value;
        if (value is Map<dynamic, dynamic>) {
          value.forEach((key, val) {
            if (val is Map<dynamic, dynamic>) {
              try {
                final gpsData = GpsData.fromMap(key.toString(), val);
                gpsDataList.add(gpsData);
              } catch (e) {
                print('Lỗi phân tích dữ liệu GPS: $e');
              }
            }
          });
        }

        // Phát dữ liệu qua stream
        _gpsStreamController.add(gpsDataList);
      },
      onError: (error) {
        print('Lỗi lắng nghe GPS: $error');
        _gpsStreamController.addError(error);
      },
    );

    return _gpsStreamController.stream;
  }

  /// Đẩy vị trí GPS hiện tại lên Firebase
  Future<void> uploadGps({
    required String roomId,
    required String userId,
    required LatLng location,
    required String role,
  }) async {
    try {
      await _firebaseDatabase
          .ref('gps/$roomId/$userId')
          .set({
            'lat': location.latitude,
            'lng': location.longitude,
            'role': role,
            'timestamp': ServerValue.timestamp,
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Timeout uploading GPS data');
            },
          );
    } catch (e) {
      print('Lỗi tải GPS: $e');
      rethrow;
    }
  }

  /// Lấy vị trí GPS của một người dùng cụ thể trong phòng
  Future<GpsData?> getGpsData(String roomId, String userId) async {
    try {
      final snapshot = await _firebaseDatabase
          .ref('gps/$roomId/$userId')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Timeout fetching GPS data'),
          );

      if (snapshot.exists && snapshot.value is Map<dynamic, dynamic>) {
        return GpsData.fromMap(userId, snapshot.value as Map<dynamic, dynamic>);
      }
      return null;
    } catch (e) {
      print('Lỗi lấy GPS data: $e');
      return null;
    }
  }

  /// Xóa dữ liệu GPS của một người dùng (gọi khi người dùng rời khỏi phòng)
  Future<void> deleteGpsData(String roomId, String userId) async {
    try {
      await _firebaseDatabase
          .ref('gps/$roomId/$userId')
          .remove()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Timeout deleting GPS data'),
          );
    } catch (e) {
      print('Lỗi xóa GPS data: $e');
    }
  }

  /// Lấy tất cả dữ liệu GPS trong phòng một lần (snapshot)
  Future<List<GpsData>> getAllGpsData(String roomId) async {
    try {
      final snapshot = await _firebaseDatabase
          .ref('gps/$roomId')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Timeout fetching all GPS data'),
          );

      final gpsDataList = <GpsData>[];
      if (snapshot.exists && snapshot.value is Map<dynamic, dynamic>) {
        (snapshot.value as Map<dynamic, dynamic>).forEach((key, val) {
          if (val is Map<dynamic, dynamic>) {
            try {
              final gpsData = GpsData.fromMap(key.toString(), val);
              gpsDataList.add(gpsData);
            } catch (e) {
              print('Lỗi phân tích dữ liệu GPS: $e');
            }
          }
        });
      }
      return gpsDataList;
    } catch (e) {
      print('Lỗi lấy tất cả GPS data: $e');
      return [];
    }
  }

  /// Giải phóng tài nguyên khi không sử dụng nữa
  void dispose() {
    _gpsSubscription?.cancel();
    _gpsStreamController.close();
  }
}

/// Hàm helper: Chuyển đổi giá trị động thành double
double? _parseDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
