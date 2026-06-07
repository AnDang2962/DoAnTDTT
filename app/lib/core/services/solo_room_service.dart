import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

String uidToSoloRoomCode(String uid) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final hash = sha256.convert(utf8.encode(uid)).bytes;
  final buf = StringBuffer();
  for (int i = 0; i < 6; i++) {
    buf.write(alphabet[hash[i] % 32]);
  }
  return buf.toString();
}

class SoloRoomService {
  static Future<void> ensureSoloRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final roomId = uidToSoloRoomCode(uid);

    try {
      await FirebaseFirestore.instance.collection('rooms').doc(roomId).set({
        'leaderId': uid,
        'isSolo': true,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'members': [uid],
        'memberInfo': {
          uid: {'name': 'Solo', 'role': 'leader'},
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
