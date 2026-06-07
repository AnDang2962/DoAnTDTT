import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    if (Platform.isIOS) {
      // Giữ audio session active (playback + duckOthers) để TTS không bị
      // queue chờ STT "đánh thức" — fix lỗi TTS chỉ phát sau khi dùng mic.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    _initialized = true;
  }

  Future<void> speak(String text) async {
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
