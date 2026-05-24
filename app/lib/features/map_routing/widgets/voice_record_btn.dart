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
        // Nút bấm Mic 
        GestureDetector(
          onTap: _listen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.all(_isListening ? 16 : 12),
            decoration: BoxDecoration(
              // ĐÃ SỬA: Nền trong suốt khi bình thường, nền đỏ khi đang nghe
              color: _isListening ? Colors.redAccent : Colors.transparent,
              shape: BoxShape.circle,
              boxShadow: _isListening 
                  ? [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 15, spreadRadius: 5)]
                  : [], // Xóa bóng mờ khi ở trạng thái bình thường để tệp vào nền
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic, // Dùng chung 1 icon mic cho đẹp
              // ĐÃ SỬA: Icon màu xanh khi bình thường, màu trắng khi đang nghe
              color: _isListening ? Colors.white : Colors.blue,
              size: 28,
            ),
          ),
        ),
        
        // Hiển thị chữ đang nhận diện theo thời gian thực
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