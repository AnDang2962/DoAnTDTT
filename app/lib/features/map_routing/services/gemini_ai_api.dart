import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/constants/env_keys.dart';

class GeminiAiApi {
  /// Phân tích văn bản (được chuyển từ giọng nói) để tìm điểm đến và rủi ro
  static Future<Map<String, dynamic>?> analyzeCommand(String userInput) async {
    if (userInput.isEmpty) return null;

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: EnvKeys.geminiApiKey,
    );

    // Prompt ép Gemini trả về đúng format JSON theo chuẩn WarningMarker
    final prompt = '''
      Bạn là AI phân tích hành trình cho app phượt. Người dùng nói: "$userInput".
      Trả về CHÍNH XÁC định dạng JSON sau, không có text dư thừa:
      {
        "destination": "Tên địa điểm đến (nếu có)",
        "risks": [
          {
            "category": "WEATHER", 
            "vi": "Mưa lớn/Đường trơn (Tóm tắt sự cố)",
            "lat": 12.2388,
            "lng": 109.1967
          }
        ]
      }
      Lưu ý: "category" CHỈ ĐƯỢC PHÉP chọn 1 trong 5 chữ: WEATHER, ACCIDENT, ROAD_BAD, POLICE, HAZARD_OTHER. Tự ước lượng tọa độ gần đúng.
    ''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      // Dọn dẹp cục text trả về để lấy chuẩn JSON
      String rawText = response.text ?? '{}';
      rawText = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
      return json.decode(rawText);
    } catch (e) {
      print('Lỗi AI Gemini: $e');
      return null;
    }
  }
}