import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Chuyển uid thành mã phòng 6 ký tự hợp lệ (Base32, [A-HJ-NP-Z2-9]).
///
/// Dùng SHA-256 để đảm bảo deterministic — cùng uid luôn cho cùng mã phòng.
String uidToSoloRoomCode(String uid) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 32 ký tự Base32
  final hash = sha256.convert(utf8.encode(uid)).bytes;
  final buf = StringBuffer();
  for (int i = 0; i < 6; i++) {
    buf.write(alphabet[hash[i] % 32]);
  }
  return buf.toString();
}

class SoloRoomService {
  static const _tag = '[SoloRoomService]';

  /// Tạo/cập nhật solo room cho user hiện tại trên Firestore.
  ///
  /// Gọi sau khi anonymous sign-in thành công trong main().
  /// Idempotent: nếu đã tồn tại thì merge và không ghi đè dữ liệu cũ.
  static Future<void> ensureSoloRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('$_tag Bỏ qua — chưa đăng nhập');
      return;
    }

    final uid = user.uid;
    final roomId = uidToSoloRoomCode(uid);

    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomId)
          .set({
        'leaderId': uid,
        'isSolo': true,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'members': [uid],
        'memberInfo': {
          uid: {'name': 'Solo', 'role': 'leader'},
        },
      }, SetOptions(merge: true));

      debugPrint('$_tag Solo room ready: $roomId (uid=$uid)');
    } catch (e) {
      debugPrint('$_tag Lỗi tạo solo room: $e');
    }
  }
}
