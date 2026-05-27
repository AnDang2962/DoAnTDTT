import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:route_mate_app/core/firebase_functions_helper.dart';

/// Gọi Cloud Function `voiceCommand` của backend M5.
///
/// Backend trả về schema (Gemini Function Calling, 6 actions):
///   { action, params, responseText, latencyMs }
class GeminiAiApi {
  /// Phân tích voice command.
  /// Trả về Map flatten để tương thích code caller cũ.
  static Future<Map<String, dynamic>?> analyzeCommand(
    String spokenText, {
    String? roomId,
    double? currentLat,
    double? currentLng,
  }) async {
    try {
      final result = await backendFunctions.httpsCallable('voiceCommand').call({
        'text': spokenText,
      });

      // Safe parse — backend trả Map nhưng nested có thể là String/null
      final raw = Map<String, dynamic>.from(result.data as Map);

      final action = raw['action']?.toString() ?? 'unknown';
      final responseText = raw['responseText']?.toString() ?? '';

      // params có thể null, String, hoặc Map
      Map<String, dynamic> params = {};
      final rawParams = raw['params'];
      if (rawParams is Map) {
        params = Map<String, dynamic>.from(rawParams);
      }

      debugPrint('[GeminiAiApi] Action: $action | Response: $responseText');

      // Return Map flatten — code cũ dùng aiResult['destination'], aiResult['intent']
      // Map action backend → key cũ frontend đang dùng
      return {
        'action': action,
        'intent': action, // Alias để tương thích code cũ
        'response': responseText,
        'responseText': responseText,
        'params': params,
        // Convenience fields cho từng action
        'destination': params['destination_name']?.toString() ??
            params['place']?.toString(),
        'destinationName': params['destination_name']?.toString(),
        'placeType': params['place_type']?.toString(),
        'radiusKm': params['radius_km'],
        'reason': params['reason']?.toString(),
        'originalText': params['original_text']?.toString(),
        'risks': params['risks'], // Cho code line 100
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

/// Backward-compat: nếu code khác đã import VoiceActionResult, giữ class này.
class VoiceActionResult {
  final String action;
  final Map<String, dynamic> params;
  final String responseText;

  VoiceActionResult({
    required this.action,
    required this.params,
    required this.responseText,
  });

  String? get placeType => params['place_type']?.toString();
  double? get radiusKm => (params['radius_km'] as num?)?.toDouble();
  String? get sosReason => params['reason']?.toString();
  String? get originalText => params['original_text']?.toString();
  bool get isUnknown => action == 'unknown';
}
