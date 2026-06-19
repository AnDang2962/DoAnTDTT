import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'package:route_mate_app/core/services/firebase_functions_helper.dart';

class RoomRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  Future<String?> _getFcmToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) return null;
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<String?> createRoom(UserModel creator) async {
    try {
      final fcmToken = await _getFcmToken() ?? '';
      final result = await backendFunctions
          .httpsCallable('createRoom')
          .call<Map<String, dynamic>>({
        'displayName': creator.name,
        'fcmToken': fcmToken,
      });
      final data = Map<String, dynamic>.from(result.data);
      return data['roomId']?.toString();
    } catch (e) {
      debugPrint('❌ createRoom error: $e');
      return null;
    }
  }

  Future<bool> joinRoom(String roomId, UserModel user) async {
    try {
      final fcmToken = await _getFcmToken() ?? '';
      await backendFunctions
          .httpsCallable('joinRoom')
          .call<Map<String, dynamic>>({
        'roomId': roomId.toUpperCase(),
        'displayName': user.name,
        'fcmToken': fcmToken,
      });
      return true;
    } catch (e) {
      debugPrint('❌ joinRoom error: $e');
      return false;
    }
  }

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
      return (data['totalDistanceKm'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return null;
    }
  }

  Future<bool> leaveRoom(String roomId) async {
    try {
      await backendFunctions
          .httpsCallable('leaveRoom')
          .call<Map<String, dynamic>>({'roomId': roomId});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateUserLocation(
    String roomId,
    String userId,
    double lat,
    double lng,
  ) async {
    try {
      final ref = _rtdb.ref('gps/$roomId/$userId');
      await ref.onDisconnect().remove();
      await ref.set({
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  Stream<Map<String, dynamic>> listenToRoomLocations(String roomId) {
    return _rtdb.ref('gps/$roomId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      return Map<String, dynamic>.from(data as Map);
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToRoomData(String roomId) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }

  Future<void> updateSweeperAlert(String roomId, Map<String, dynamic>? alert) async {
    try {
      await _firestore.collection('rooms').doc(roomId).update({'sweeperAlert': alert});
    } catch (_) {}
  }

  Future<void> updateGroupStop(String roomId, Map<String, dynamic>? stop) async {
    try {
      await _firestore.collection('rooms').doc(roomId).update({'groupStop': stop});
    } catch (_) {}
  }

  Future<void> sendGroupMessage(String roomId, String text, String senderName, String senderUid) async {
    try {
      await _firestore.collection('rooms').doc(roomId).update({
        'groupMessage': {
          'text': text,
          'senderName': senderName,
          'senderUid': senderUid,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      });
    } catch (_) {}
  }

  Future<void> setNavigationStopped(String roomId) async {
    try {
      await _firestore.collection('rooms').doc(roomId).update({
        'navigationStopped': {'at': DateTime.now().millisecondsSinceEpoch},
        'route': FieldValue.delete(),
      });
    } catch (_) {}
  }
}
