import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (_) => _isListening = false,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _isListening = false;
        },
      );
      return _isInitialized;
    } catch (_) {
      _isInitialized = false;
      return false;
    }
  }

  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
  }) async {
    if (!_isInitialized || _isListening) return;
    try {
      await _speech.listen(
        localeId: 'vi_VN',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: onPartialResult != null,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            onResult(result.recognizedWords);
          } else if (!result.finalResult && onPartialResult != null) {
            onPartialResult(result.recognizedWords);
          }
        },
      );
      _isListening = true;
    } catch (_) {
      _isListening = false;
      rethrow;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
      _isListening = false;
    } catch (_) {}
  }

  Future<void> dispose() async => stopListening();
}
