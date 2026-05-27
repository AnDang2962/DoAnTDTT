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
    Position? position = await Geolocator.getLastKnownPosition();
    position ??= await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    int batteryLevel = await Battery().batteryLevel;

    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'battery': batteryLevel,
    };
  }

  Future<void> sendEmergencySignal({
    required String roomId,
    required Function(String, Color) onStatusUpdate
  }) async {
    try {
      final data = await _collectEmergencyData();
      final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());

      if (connectivityResult.contains(ConnectivityResult.none)) {
        _sendSmsFallback(data);
        onStatusUpdate("Mất mạng! Đã kích hoạt SMS dự phòng.", Colors.orange);
      } else {
        onStatusUpdate("Đang phát tín hiệu SOS...", Colors.blue);
        
        final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('sendSOS');
        
        // 🔥 ĐỒNG BỘ 1: Đóng gói payload khớp 100% với yêu cầu của sos.js
        final params = {
          'roomId': roomId, 
          'lat': data['lat'],
          'lng': data['lng'],
          // Sinh ra một mã duy nhất dựa trên thời gian (đảm bảo > 8 ký tự) để chống spam
          'idempotencyKey': 'SOS_${DateTime.now().millisecondsSinceEpoch}', 
        };
        
        final HttpsCallableResult response = await callable.call(params);
        
        // 🔥 ĐỒNG BỘ 2: Bắt đúng biến 'status' mà server trả về (DELIVERED, PARTIAL hoặc CACHED)
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
      
      final data = await _collectEmergencyData();
      _sendSmsFallback(data);
    } catch (e) {
      onStatusUpdate("Lỗi kết nối mạng. Kích hoạt SMS...", Colors.black);
      
      final data = await _collectEmergencyData();
      _sendSmsFallback(data);
    }
  }

  void _sendSmsFallback(Map<String, dynamic> data) async {
    // 🔥 ĐỒNG BỘ 3: Fix lỗi hiển thị nội dung và sử dụng Link chuẩn của Google Maps
    final String message = "SOS! Toi can giup. Vi tri: https://maps.google.com/?q=${data['lat']},${data['lng']} - Pin: ${data['battery']}%";
    
    final Uri smsUri = Uri(
      scheme: 'sms', 
      path: '0901234567', 
      queryParameters: {'body': message}
    );
    
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      debugPrint("Không thể mở ứng dụng SMS");
    }
  }
}