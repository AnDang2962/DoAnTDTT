import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SosService {
  static const String fallbackEmergencyContact = '0837897543';

  Future<void> checkAndRequestPermissions() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<Map<String, dynamic>> collectEmergencyData() async {
    double lat = 0.0;
    double lng = 0.0;
    int batteryLevel = -1;

    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      debugPrint('Lỗi GPS: $e');
    }

    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      debugPrint('Lỗi Pin: $e');
    }

    return {'lat': lat, 'lng': lng, 'battery': batteryLevel};
  }

  /// Trả về true nếu có mạng và gửi được, false nếu mất mạng.
  Future<bool> sendGroupFcmNotification({
    required String roomId,
    required Map<String, dynamic> data,
    required Function(String, Color) onStatusUpdate,
  }) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        onStatusUpdate('Mất mạng! Sẽ gửi SMS sau khi gọi.', Colors.orange);
        return false;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        onStatusUpdate('Lỗi: Chưa đăng nhập.', Colors.red);
        return false;
      }
      onStatusUpdate('Đang phát tín hiệu SOS...', Colors.blue);
      await FirebaseFirestore.instance.collection('rooms').doc(roomId).update({
        'sos': {
          'senderId': user.uid,
          'senderName': user.displayName ?? 'Thành viên',
          'lat': data['lat'],
          'lng': data['lng'],
          'battery': data['battery'],
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      });
      onStatusUpdate('🆘 TÍN HIỆU ĐÃ PHÁT TỚI ĐỘI CỨU HỘ!', Colors.red);
      return true;
    } catch (e) {
      onStatusUpdate('Lỗi gửi SOS: $e', Colors.black);
      return false;
    }
  }

  Future<void> openEmergencySms(Map<String, dynamic> data, List<String> contacts) async {
    final battery = data['battery'] as int? ?? -1;
    final batteryStr = battery == -1 ? 'Không rõ' : '$battery%';
    final message = 'SOS! Toi can giup. Vi tri: https://maps.google.com/?q=${data['lat']},${data['lng']} - Pin: $batteryStr';
    final numbers = contacts.map((p) => p.replaceAll(RegExp(r'[\s\-]'), '')).join(',');
    final smsUri = Uri.parse('sms:$numbers?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
  }

  Future<void> makeCall(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.isEmpty) return;
    final callUri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(callUri)) await launchUrl(callUri);
  }
}
