import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dịch vụ quản lý Microphone và chuyển đổi Giọng nói thành Văn bản (Tiếng Việt)
class VoiceService {
  // Biến service thành Singleton (Chỉ có 1 bản sao duy nhất trong toàn bộ App)
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Khởi tạo dịch vụ (Xin quyền Microphone)
  /// Phải gọi hàm này trước khi bắt đầu thu âm.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          debugPrint('[VoiceService] Lỗi: ${error.errorMsg}');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('[VoiceService] Trạng thái: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
      );
      
      if (!_isInitialized) {
        debugPrint('[VoiceService] Không thể khởi tạo Microphone!');
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('[VoiceService] Ngoại lệ khi khởi tạo: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Bắt đầu lắng nghe và tự động nhận diện ngôn ngữ Tiếng Việt (vi_VN)
  /// Sẽ tự động ngắt sau 10 giây hoặc khi im lặng 3 giây.
  Future<void> startListening({required Function(String) onResult}) async {
    if (!_isInitialized) return;
    if (_isListening) return;

    try {
      await _speech.listen(
        localeId: 'vi_VN',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: false, // Chỉ lấy kết quả cuối cùng (tránh nhảy chữ liên tục)
          cancelOnError: true,
        ),
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            debugPrint('[VoiceService] Nghe được: "${result.recognizedWords}"');
            onResult(result.recognizedWords);
          }
        },
      );
      _isListening = true;
    } catch (e) {
      debugPrint('[VoiceService] Lỗi thu âm: $e');
      _isListening = false;
      rethrow;
    }
  }

  /// Dừng thu âm chủ động
  Future<void> stopListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
      _isListening = false;
    } catch (e) {
      debugPrint('[VoiceService] Lỗi dừng thu âm: $e');
    }
  }

  Future<void> dispose() async {
    await stopListening();
  }
}
