///Phân tích giọng nói cho cảnh báo và tiện ích 

import 'package:google_generative_ai/google_generative_ai.dart';
import '../constants/env_keys.dart';

class GeminiAiService {
  late final GenerativeModel _model;

  /// Khởi tạo gemini với api key free
  void init() {
    final apiKey = EnvKeys.geminiApiKey;
    
    if (apiKey == 'THIẾU_GEMINI_KEY') {
      print('CẢNH BÁO: Chưa cấu hình GEMINI_API_KEY trong file .env');
      return;
    }

    // Khởi tạo model theo phiên bản mới nhất bạn được cấp
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
    print('Gemini AI Service đã sẵn sàng với phiên bản 2.5 Flash!');
  }

  /// Send audio data to Gemini API and parse the response
  /// Returns a structured response containing warning type, lat, lng, etc.
  Future<Map<String, dynamic>?> analyzeVoiceCommand(String audioPath) async {
    // TODO: Implement Gemini API call
    return null;
  }
}
