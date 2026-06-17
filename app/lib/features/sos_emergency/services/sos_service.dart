import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

class SosService {
  Future<void> checkAndRequestPermissions() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<Map<String, dynamic>> _collectEmergencyData() async {
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

  /// Gửi FCM cho group. Trả về số điện thoại cần gọi nếu cần fallback, null nếu FCM delivered.
  Future<String?> sendEmergencySignal({
    required String roomId,
    required String leaderPhoneNumber,
    required Function(String, Color) onStatusUpdate,
  }) async {
    final data = await _collectEmergencyData();

    try {
      final connectivity = await Connectivity().checkConnectivity();

      if (connectivity.contains(ConnectivityResult.none)) {
        await _openSms(data, [leaderPhoneNumber]);
        onStatusUpdate('Mất mạng! Đã soạn SMS dự phòng.', Colors.orange);
        return leaderPhoneNumber.isNotEmpty ? leaderPhoneNumber : null;
      } else {
        onStatusUpdate('Đang phát tín hiệu SOS...', Colors.blue);

        final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('sendSOS');
        final response = await callable.call({
          'roomId': roomId,
          'lat': data['lat'],
          'lng': data['lng'],
          'battery': data['battery'],
          'idempotencyKey': 'SOS_${DateTime.now().millisecondsSinceEpoch}',
        });

        final status = response.data['status'] as String?;
        if (status == 'DELIVERED' || status == 'PARTIAL' || status == 'CACHED') {
          onStatusUpdate('🆘 TÍN HIỆU ĐÃ PHÁT TỚI ĐỘI CỨU HỘ!', Colors.red);
          return leaderPhoneNumber.isNotEmpty ? leaderPhoneNumber : null;
        } else {
          onStatusUpdate('Lỗi: Không có thiết bị nào nhận được tín hiệu', Colors.orange);
          await _openSms(data, [leaderPhoneNumber]);
          return leaderPhoneNumber.isNotEmpty ? leaderPhoneNumber : null;
        }
      }
    } on FirebaseFunctionsException catch (e) {
      onStatusUpdate('Lỗi máy chủ: ${e.message}. Kích hoạt SMS...', Colors.black);
      debugPrint('Mã lỗi: ${e.code}');
      await _openSms(data, [leaderPhoneNumber]);
      return leaderPhoneNumber.isNotEmpty ? leaderPhoneNumber : null;
    } catch (e) {
      onStatusUpdate('Lỗi kết nối mạng. Kích hoạt SMS...', Colors.black);
      await _openSms(data, [leaderPhoneNumber]);
      return leaderPhoneNumber.isNotEmpty ? leaderPhoneNumber : null;
    }
  }

  /// Gửi SOS solo. Mở SMS đến liên hệ khẩn cấp, trả về số cần gọi.
  Future<String> sendSoloEmergencySignal({
    required List<String> emergencyContacts,
    required Function(String, Color) onStatusUpdate,
  }) async {
    final data = await _collectEmergencyData();
    final contacts = emergencyContacts.isNotEmpty ? emergencyContacts : ['0837897543'];
    onStatusUpdate('Đang gửi tín hiệu khẩn cấp...', Colors.blue);
    await _openSms(data, contacts);
    onStatusUpdate('🆘 Đã soạn SMS! Gọi điện ngay sau khi bạn quay lại.', Colors.red);
    return contacts.first;
  }

  Future<void> makeCall(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.isEmpty) return;
    if (Platform.isAndroid) {
      try {
        await AndroidIntent(action: 'android.intent.action.CALL', data: 'tel:$clean').launch();
        return;
      } catch (_) {}
    }
    final callUri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(callUri)) await launchUrl(callUri);
  }

  Future<void> _openSms(Map<String, dynamic> data, List<String> contacts) async {
    final battery = data['battery'] as int? ?? -1;
    final batteryStr = battery == -1 ? 'Không rõ' : '$battery%';
    final message = 'SOS! Toi can giup. Vi tri: https://maps.google.com/?q=${data['lat']},${data['lng']} - Pin: $batteryStr';
    final numbers = contacts.map((p) => p.replaceAll(RegExp(r'[\s\-]'), '')).join(',');
    final smsUri = Uri.parse('sms:$numbers?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
  }
}
