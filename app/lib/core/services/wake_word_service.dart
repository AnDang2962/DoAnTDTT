import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_service.dart';
import 'sound_service.dart';

enum VoiceMode { tap, wakeWord }

enum WakeWordState { idle, listening, detected }

class WakeWordService extends ChangeNotifier {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  static const _prefKey = 'voice_mode';
  // Primary: routemate và các biến thể STT thực tế trả về
  static const _primaryPatterns = [
    'routemate', 'route mate',
    'hey routemate', 'ok routemate', 'hi routemate',
    'ê routemate', 'hey route',
    // phiên âm tiếng Việt
    'rút mết', 'rốt mết', 'rout mết',
    // STT mishear thực tế
    'roth mate', 'ruth made', 'ruth mate', 'ruth me',
    'roomate', 'roommate', 'room mate',
    'root mate', 'root made', 'rout made',
    'use made',
    'rome', 'roman',
    'rau má', 'rất mệt',
  ];

  // Fallback: dành cho người dùng không phát âm được "routemate"
  static const _fallbackPatterns = [
    'trợ lý',
  ];

  final _voice = VoiceService();
  bool _active = false;
  bool _paused = false;

  VoiceMode _mode = VoiceMode.tap;
  VoiceMode get mode => _mode;

  WakeWordState _state = WakeWordState.idle;
  WakeWordState get state => _state;

  VoidCallback? onWakeWordDetected;

  Timer? _watchdogTimer;
  DateTime? _pausedAt;
  static const _watchdogInterval = Duration(seconds: 30);
  static const _maxPausedDuration = Duration(seconds: 35);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _mode = saved == 'wakeWord' ? VoiceMode.wakeWord : VoiceMode.tap;
    notifyListeners();
    if (_mode == VoiceMode.wakeWord) unawaited(startListening());
  }

  Future<void> setMode(VoiceMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
    notifyListeners();
    if (mode == VoiceMode.wakeWord) {
      unawaited(startListening());
    } else {
      await stopListening();
    }
  }

  Future<void> startListening() async {
    if (_active || _paused || _mode != VoiceMode.wakeWord) return;
    _active = true;
    _setState(WakeWordState.listening);
    await _voice.startContinuousWake(_onPartial);
    _startWatchdog();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) async {
      if (_mode != VoiceMode.wakeWord) return;

      if (_paused && _pausedAt != null &&
          DateTime.now().difference(_pausedAt!) >= _maxPausedDuration) {
        _pausedAt = null;
        await resumeAfterCommand();
        return;
      }

      if (!_paused && (!_active || !_voice.isWakeReallyActive)) {
        _active = false;
        await _voice.resetForWake();
        unawaited(startListening());
      }
    });
  }

  Future<void> _playThenNotify() async {
    await _voice.stopListening(); // giải phóng AVAudioSession trước khi phát sound
    await SoundService().playWakeWord();
    onWakeWordDetected?.call();
  }

  void _onPartial(String text) {
    if (!_active || _paused) return;
    final matched = _primaryPatterns.any((p) => text.contains(p)) ||
        _fallbackPatterns.any((p) => text.contains(p));
    if (matched) {
      _active = false;
      _voice.pauseWake();
      _setState(WakeWordState.detected);
      unawaited(_playThenNotify());
    }
  }

  Future<void> stopListening() async {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _active = false;
    await _voice.stopContinuousWake();
    _setState(WakeWordState.idle);
  }

  Future<void> pauseForCommand() async {
    _paused = true;
    _pausedAt = DateTime.now();
    _active = false;
    await _voice.stopContinuousWake();
    _setState(WakeWordState.idle);
  }

  Future<void> resumeAfterCommand() async {
    _pausedAt = null;
    _paused = false;
    if (_mode == VoiceMode.wakeWord) unawaited(startListening());
  }

  void _setState(WakeWordState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    stopListening();
    super.dispose();
  }
}
