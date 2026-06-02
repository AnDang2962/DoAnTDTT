import 'package:flutter/material.dart';
import '../../../core/services/voice_service.dart';

class VoiceFab extends StatefulWidget {
  final Function(String text) onVoiceResult;

  const VoiceFab({super.key, required this.onVoiceResult});

  @override
  State<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<VoiceFab> {
  final VoiceService _voiceService = VoiceService();
  bool _isListening = false;
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _voiceService.initialize();
  }

  @override
  void dispose() {
    _voiceService.stopListening();
    super.dispose();
  }

  void _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      setState(() {
        _isListening = true;
        _currentText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang nghe... Hãy nói sự cố (Ví dụ: "Có ổ gà phía trước")'),
          duration: Duration(seconds: 2),
        ),
      );
      await _voiceService.startListening(
        onPartialResult: (text) {
          if (mounted) setState(() => _currentText = text);
        },
        onResult: (text) {
          if (mounted) setState(() {
            _isListening = false;
            _currentText = '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã ghi nhận: "$text"')),
          );
          widget.onVoiceResult(text);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggleListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(_isListening ? 16 : 12),
            decoration: BoxDecoration(
              color: _isListening ? Colors.redAccent : Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: _isListening
                  ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 15, spreadRadius: 5)]
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
