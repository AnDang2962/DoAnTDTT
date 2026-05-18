import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/room_model.dart';
import '../models/user_model.dart';

class RoomRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  /// Creates a new room and sets the creator as Leader
  /// Returns the newly created RoomModel if successful
  Future<RoomModel?> createRoom(UserModel creator) async {
    try {
      // Đảm bảo người tạo phòng luôn là leader
      final leader = UserModel(id: creator.id, name: creator.name, role: UserRole.leader);
      
      // Tạo một document mới trong collection 'rooms'
      final docRef = _firestore.collection('rooms').doc();
      final roomId = docRef.id;

      final newRoom = RoomModel(
        roomId: roomId,
        members: [leader],
      );

      await docRef.set(newRoom.toMap());
      return newRoom;
    } catch (e) {
      print('Lỗi khi tạo phòng: $e');
      return null;
    }
  }

  /// Joins an existing room
  Future<bool> joinRoom(String roomId, UserModel user) async {
    try {
      final docRef = _firestore.collection('rooms').doc(roomId);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        print('Phòng không tồn tại!');
        return false;
      }

      // Thêm user vào mảng members trên Firestore
      await docRef.update({
        'members': FieldValue.arrayUnion([user.toMap()])
      });
      return true;
    } catch (e) {
      print('Lỗi khi vào phòng: $e');
      return false;
    }
  }

  /// Updates user GPS location in Realtime Database (Rất nhanh và rẻ)
  Future<void> updateUserLocation(String roomId, String userId, double lat, double lng) async {
    try {
      final ref = _rtdb.ref('gps/$roomId/$userId');
      await ref.set({
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp, // Dùng giờ máy chủ Firebase
      });
    } catch (e) {
      print('Lỗi cập nhật vị trí: $e');
    }
  }

  /// Stream to listen to all members' locations in real-time
  Stream<Map<String, dynamic>> listenToRoomLocations(String roomId) {
    return _rtdb.ref('gps/$roomId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      
      // Chuyển đổi dữ liệu từ Realtime DB thành Map
      return Map<String, dynamic>.from(data as Map);
    });
  }
}
