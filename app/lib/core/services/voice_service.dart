import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum _SessionType { none, wake, command }

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool _wakeActive = false;
  Function(String)? _onWakePartial;
  // Tracks which session owns the current STT session so that stale
  // onStatus/onError callbacks from a stopped session are ignored.
  _SessionType _activeSession = _SessionType.none;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (e) {
          if (_activeSession == _SessionType.none) return;
          _isListening = false;
          if (_activeSession == _SessionType.wake) {
            _activeSession = _SessionType.none;
            if (_wakeActive) _scheduleWakeRestart();
          } else {
            _activeSession = _SessionType.none;
            final cb = _onCommandDone;
            _onCommandDone = null;
            cb?.call();
            if (_wakeActive && !_isListening && !_isStartingWake) _scheduleWakeRestart();
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (_activeSession == _SessionType.none) return;
            _isListening = false;
            if (_activeSession == _SessionType.wake) {
              _activeSession = _SessionType.none;
              if (_wakeActive) _scheduleWakeRestart();
            } else {
              _activeSession = _SessionType.none;
              final cb = _onCommandDone;
              _onCommandDone = null;
              cb?.call();
              if (_wakeActive && !_isListening && !_isStartingWake) _scheduleWakeRestart();
            }
          }
        },
      );
      return _isInitialized;
    } catch (_) {
      _isInitialized = false;
      return false;
    }
  }

  bool _isStartingWake = false;
  Timer? _wakeRestartTimer;

  void _scheduleWakeRestart() {
    _wakeRestartTimer?.cancel();
    _wakeRestartTimer = Timer(const Duration(milliseconds: 500), () {
      _wakeRestartTimer = null;
      if (_wakeActive && !_isListening && !_isStartingWake) unawaited(_doWakeListen());
    });
  }

  bool get isWakeReallyActive => _wakeActive && _speech.isListening;

  // Must be called synchronously on wake detection so that any delayed
  // onStatus: done from the wake session is ignored rather than treated
  // as a command-session event.
  void pauseWake() {
    _wakeActive = false;
    _onWakePartial = null;
    _activeSession = _SessionType.none;
  }

  Future<void> startContinuousWake(Function(String) onPartial) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized) return;
    _wakeActive = true;
    _onWakePartial = onPartial;
    if (!_isListening) await _doWakeListen();
  }

  Future<void> _doWakeListen() async {
    if (!_wakeActive || _isListening || _isStartingWake) return;
    _isStartingWake = true;
    _activeSession = _SessionType.wake;
    _isListening = true;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(minutes: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty && _wakeActive) {
            _onWakePartial?.call(result.recognizedWords.toLowerCase());
          }
        },
      );
    } catch (_) {
      _isListening = false;
      _activeSession = _SessionType.none;
      _scheduleWakeRestart();
    } finally {
      _isStartingWake = false;
    }
  }

  Future<void> stopContinuousWake() async {
    _wakeActive = false;
    _onWakePartial = null;
    await stopListening();
  }

  Future<void> resetForWake() async {
    _wakeActive = false;
    _onWakePartial = null;
    _wakeRestartTimer?.cancel();
    _wakeRestartTimer = null;
    _isStartingWake = false;
    _activeSession = _SessionType.none;
    try { await _speech.cancel(); } catch (_) {}
    _isListening = false;
    _isInitialized = false;
  }

  VoidCallback? _onCommandDone;

  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
    VoidCallback? onDone,
  }) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized || _isListening) return;
    _onCommandDone = onDone;
    _activeSession = _SessionType.command;
    _isListening = true;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          partialResults: onPartialResult != null,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _onCommandDone = null;
            onResult(result.recognizedWords);
          } else if (!result.finalResult && onPartialResult != null) {
            onPartialResult(result.recognizedWords);
          }
        },
      );
    } catch (_) {
      _onCommandDone = null;
      _activeSession = _SessionType.none;
      _isListening = false;
      rethrow;
    }
  }

  Future<void> stopListening() async {
    _onCommandDone = null;
    _activeSession = _SessionType.none;
    if (!_isListening) return;
    try {
      await _speech.stop();
      _isListening = false;
    } catch (_) {}
  }

  Future<void> dispose() async {
    _wakeActive = false;
    await stopListening();
  }
}
