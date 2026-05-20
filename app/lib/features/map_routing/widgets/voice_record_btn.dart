import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceRecordButton extends StatefulWidget {
  final Function(String text) onResult;

  const VoiceRecordButton({Key? key, required this.onResult}) : super(key: key);

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  /// Xử lý khi nhấn nút Mic
  void _listen() async {
    if (!_isListening) {
      // Yêu cầu quyền Micro
      bool available = await _speech.initialize(
        onStatus: (val) => print('Trạng thái thu âm: $val'),
        onError: (val) => print('Lỗi thu âm: $val'),
      );
      
      if (available) {
        setState(() => _isListening = true);
        // Bắt đầu nghe (chỉ định tiếng Việt)
        _speech.listen(
          localeId: 'vi_VN',
          onResult: (val) {
            setState(() {
              _currentText = val.recognizedWords;
            });
          },
        );
      }
    } else {
      // Khi bấm dừng hoặc tự động dừng
      setState(() => _isListening = false);
      _speech.stop();
      
      // Bắn kết quả chữ ra ngoài cho Panel xử lý
      if (_currentText.isNotEmpty) {
        widget.onResult(_currentText);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nút bấm Mic (Đổi màu và có hiệu ứng thu nhỏ/phóng to khi đang nghe)
        GestureDetector(
          onTap: _listen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(_isListening ? 16 : 12),
            decoration: BoxDecoration(
              color: _isListening ? Colors.redAccent : const Color.fromARGB(255, 6, 110, 190),
              shape: BoxShape.circle,
              boxShadow: _isListening 
                  ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 15, spreadRadius: 5)]
                  : [],
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        
        // Hiển thị chữ đang nhận diện theo thời gian thực (để người dùng biết máy đang nghe gì)
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