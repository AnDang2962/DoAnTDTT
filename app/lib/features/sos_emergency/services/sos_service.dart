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

  // 1. Đã thêm required String roomId để khớp với M3
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
        
        // 2. Truyền roomId lấy từ Provider vào payload
        final params = {
          'roomId': roomId, 
          'lat': data['lat'],
          'lng': data['lng'],
          'message': 'Tôi đang gặp sự cố khẩn cấp!', 
        };
        
        final HttpsCallableResult response = await callable.call(params);
        if (response.data['success'] == true) {
          onStatusUpdate("🆘 TÍN HIỆU ĐÃ PHÁT TỚI ĐỘI CỨU HỘ!", Colors.red);
        }
      }
    } on FirebaseFunctionsException catch (e) {
      onStatusUpdate("Lỗi máy chủ: ${e.message}. Kích hoạt SMS...", Colors.black);
      debugPrint("Mã lỗi: ${e.code}");
      
      // 3. Fallback: Nếu máy chủ Firebase sập, tự động chuyển sang gửi tin nhắn
      final data = await _collectEmergencyData();
      _sendSmsFallback(data);
    } catch (e) {
      onStatusUpdate("Lỗi kết nối mạng: $e. Kích hoạt SMS...", Colors.black);
      
      // 3. Fallback: Nếu lỗi mạng chập chờn không bắn API được, cũng chuyển sang SMS
      final data = await _collectEmergencyData();
      _sendSmsFallback(data);
    }
  }

  void _sendSmsFallback(Map<String, dynamic> data) async {
    // 4. Sửa lại URL Google Maps để đội cứu hộ click vào là mở bản đồ được ngay
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