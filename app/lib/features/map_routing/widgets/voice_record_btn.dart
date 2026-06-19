import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/services/wake_word_service.dart';

class VoiceRecordButton extends StatefulWidget {
  final Function(String text) onResult;

  const VoiceRecordButton({super.key, required this.onResult});

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  final VoiceService _voiceService = VoiceService();
  final WakeWordService _wakeWord = WakeWordService();
  bool _isListening = false;
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _voiceService.initialize();
  }

  @override
  void dispose() {
    if (_isListening) {
      final wasInWakeMode = _wakeWord.mode == VoiceMode.wakeWord;
      unawaited(_voiceService.stopListening().then((_) {
        if (wasInWakeMode) unawaited(_wakeWord.resumeAfterCommand());
      }));
    }
    super.dispose();
  }

  void _listen() async {
    if (!_isListening) {
      final wasInWakeMode = _wakeWord.mode == VoiceMode.wakeWord;
      if (wasInWakeMode) await _wakeWord.pauseForCommand();
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _currentText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang nghe... Hãy nói địa điểm'),
          duration: Duration(seconds: 2),
        ),
      );
      await _voiceService.startListening(
        onPartialResult: (text) {
          if (mounted) setState(() => _currentText = text);
        },
        onResult: (text) {
          if (mounted) setState(() => _isListening = false);
          if (wasInWakeMode) unawaited(_wakeWord.resumeAfterCommand());
          widget.onResult(text);
        },
        onDone: () {
          if (mounted) setState(() => _isListening = false);
          if (wasInWakeMode) unawaited(_wakeWord.resumeAfterCommand());
        },
      );
    } else {
      await _voiceService.stopListening();
      if (mounted) setState(() => _isListening = false);
      if (_wakeWord.mode == VoiceMode.wakeWord) {
        unawaited(_wakeWord.resumeAfterCommand());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _listen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(_isListening ? 16 : 12),
            decoration: BoxDecoration(
              color: _isListening ? Colors.redAccent : Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: _isListening
                  ? [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: 5)]
                  : [],
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.white : Colors.blue,
              size: 28,
            ),
          ),
        ),
        if (_isListening)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              _currentText.isEmpty ? 'Đang nghe...' : _currentText,
              style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
