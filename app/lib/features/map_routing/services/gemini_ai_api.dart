import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:route_mate_app/core/firebase_functions_helper.dart';

class GeminiAiApi {
  /// Hàm gọi AI Backend để phân tích giọng nói
  static Future<Map<String, dynamic>?> analyzeCommand(
    String spokenText, {
    String? roomId,
    double? currentLat,
    double? currentLng,
  }) async {
    try {
      // Đóng gói data theo đúng chuẩn Backend yêu cầu
      final result = await backendFunctions.httpsCallable('voiceCommand').call({
        'text': spokenText,
        'context': {
          if (roomId != null) 'roomId': roomId,
          if (currentLat != null) 'currentLat': currentLat,
          if (currentLng != null) 'currentLng': currentLng,
        },
      });

      final data = result.data as Map;

      // Bóc tách kết quả từ Backend trả về
      return {
        'intent': data['intent'], // Ví dụ: 'query_progress', 'report_risk', 'navigate'
        'response': data['response'], // Lời đáp của AI (nếu có)
        'destination': data['action']?['destinationName'], // Tên địa điểm nếu intent là tìm đường
      };
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[GeminiAiApi] Lỗi gọi AI Backend: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[GeminiAiApi] Lỗi hệ thống: $e');
      return null;
    }
  }
}