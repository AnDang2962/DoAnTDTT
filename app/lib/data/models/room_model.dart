import 'user_model.dart';

class RoomModel {
  final String roomId;
  final List<UserModel> members;
  final List<String> fcmTokens; // Optional, can be separate
  
  RoomModel({
    required this.roomId,
    required this.members,
    this.fcmTokens = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'members': members.map((x) => x.toMap()).toList(),
      'fcmTokens': fcmTokens,
    };
  }

  factory RoomModel.fromMap(Map<String, dynamic> map) {
    return RoomModel(
      roomId: map['roomId'] ?? '',
      members: List<UserModel>.from(
        (map['members'] ?? []).map((x) => UserModel.fromMap(x))
      ),
      fcmTokens: List<String>.from(map['fcmTokens'] ?? []),
    );
  }
}
