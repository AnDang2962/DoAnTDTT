import 'package:cloud_functions/cloud_functions.dart';
import 'package:route_mate_app/core/services/firebase_functions_helper.dart';

/// Gọi Cloud Function `voiceCommand` của backend M5.
///
/// Backend trả về schema thống nhất:
///   { type: 'command'|'risk', data: {...}, latencyMs }
class GeminiAiApi {
  /// Phân tích voice command, tự động phân loại command vs risk.
  ///
  /// Kết quả luôn có: type, action, responseText.
  /// Nếu type='risk' thêm: vi, category, subtype, autoSaved, riskId.
  static Future<Map<String, dynamic>?> analyzeCommand(
    String spokenText, {
    String? roomId,
    double? currentLat,
    double? currentLng,
  }) async {
    try {
      final callData = <String, dynamic>{'text': spokenText};
      if (roomId != null) callData['roomId'] = roomId;
      if (currentLat != null) callData['lat'] = currentLat;
      if (currentLng != null) callData['lng'] = currentLng;

      final result =
          await backendFunctions.httpsCallable('voiceCommand').call(callData);

      final raw = Map<String, dynamic>.from(result.data as Map);
      final type = raw['type']?.toString() ?? 'command';
      final dataMap = raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : <String, dynamic>{};

      if (type == 'risk') {
        final vi = dataMap['vi']?.toString() ?? '';
        final responseText = dataMap['responseText']?.toString() ?? '';
        final autoSaved = dataMap['autoSaved'] == true;
        return {
          'type': type,
          'action': 'report_risk',
          'responseText': responseText,
          'response': responseText,
          'vi': vi,
          'category': dataMap['category']?.toString() ?? '',
          'subtype': dataMap['subtype']?.toString() ?? '',
          'autoSaved': autoSaved,
          'riskId': dataMap['id']?.toString(),
        };
      }

      // type == 'command'
      final action = dataMap['action']?.toString() ?? 'unknown';
      final responseText = dataMap['responseText']?.toString() ?? '';
      final params = dataMap['params'] is Map
          ? Map<String, dynamic>.from(dataMap['params'] as Map)
          : <String, dynamic>{};

      return {
        'type': type,
        'action': action,
        'intent': action,
        'response': responseText,
        'responseText': responseText,
        'params': params,
        'destination': params['destination_name']?.toString() ??
            params['place']?.toString(),
        'destinationName': params['destination_name']?.toString(),
        'placeType': params['place_type']?.toString(),
        'radiusKm': params['radius_km'],
        'reason': params['reason']?.toString(),
        'originalText': params['original_text']?.toString(),
        'risks': params['risks'],
      };
    } catch (_) {
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
