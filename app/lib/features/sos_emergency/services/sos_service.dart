import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SosService {
  Future<void> checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<Map<String, dynamic>> _collectEmergencyData() async {
    double lat = 0.0;
    double lng = 0.0;
    int batteryLevel = -1;

    // Bọc Try-Catch để không bao giờ quăng lỗi ra ngoài gây crash
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      debugPrint("Lỗi GPS: $e");
    }

    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      debugPrint("Lỗi Pin: $e");
    }

    return {
      'lat': lat,
      'lng': lng,
      'battery': batteryLevel,
    };
  }

  Future<void> sendEmergencySignal({
    required String roomId,
    required String leaderPhoneNumber,
    required Function(String, Color) onStatusUpdate
  }) async {
    // 🔥 Lấy data 1 lần duy nhất ở ngoài cùng để tái sử dụng trong cả try và catch
    final data = await _collectEmergencyData();

    try {
      final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());

      if (connectivityResult.contains(ConnectivityResult.none)) {
        _sendSmsFallback(data, leaderPhoneNumber);
        onStatusUpdate("Mất mạng! Đã kích hoạt SMS dự phòng.", Colors.orange);
      } else {
        onStatusUpdate("Đang phát tín hiệu SOS...", Colors.blue);
        
        final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('sendSOS');
        
        final params = {
          'roomId': roomId, 
          'lat': data['lat'],
          'lng': data['lng'],
          'battery': data['battery'],
          'idempotencyKey': 'SOS_${DateTime.now().millisecondsSinceEpoch}', 
        };
        
        final HttpsCallableResult response = await callable.call(params);
        
        final String? status = response.data['status'];
        if (status == 'DELIVERED' || status == 'PARTIAL' || status == 'CACHED') {
          onStatusUpdate("🆘 TÍN HIỆU ĐÃ PHÁT TỚI ĐỘI CỨU HỘ!", Colors.red);
        } else {
          onStatusUpdate("Lỗi: Không có thiết bị nào nhận được tín hiệu", Colors.orange);
        }
      }
    } on FirebaseFunctionsException catch (e) {
      onStatusUpdate("Lỗi máy chủ: ${e.message}. Kích hoạt SMS...", Colors.black);
      debugPrint("Mã lỗi: ${e.code}");
      
      // Tái sử dụng data, không gọi lại await _collectEmergencyData()
      _sendSmsFallback(data, leaderPhoneNumber); 
    } catch (e) {
      onStatusUpdate("Lỗi kết nối mạng. Kích hoạt SMS...", Colors.black);
      
      // Tái sử dụng data, không gọi lại await _collectEmergencyData()
      _sendSmsFallback(data, leaderPhoneNumber); 
    }
  }

  void _sendSmsFallback(Map<String, dynamic> data, String phoneNumber) async {
    final String message = "SOS! Toi can giup. Vi tri: http://googleusercontent.com/maps.google.com/${data['lat']},${data['lng']} - Pin: ${data['battery']}%";
    
    // Dọn dẹp số
    String cleanPhone = phoneNumber.replaceAll(RegExp(r'\s+|-'), '');
    
    debugPrint("👉 Số điện thoại đang gửi: '$cleanPhone'");

    // 🔥 Fix lỗi url_launcher mã hóa khoảng trắng thành dấu '+' trên Android
    final Uri smsUri = Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(message)}');
    
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      debugPrint("Không thể mở ứng dụng SMS");
    }
  }
}