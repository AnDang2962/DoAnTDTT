import 'package:flutter/material.dart';
import '../../../core/services/voice_service.dart';

/// Nút thu âm nổi (Floating Action Button) dùng để báo cáo rủi ro.
/// Khi bấm vào sẽ kích hoạt VoiceService để lắng nghe giọng nói Tiếng Việt.
/// Kết quả nhận diện (Text) sẽ được trả về qua hàm callback [onVoiceResult].
class VoiceFab extends StatefulWidget {
  final Function(String text) onVoiceResult;

  const VoiceFab({Key? key, required this.onVoiceResult}) : super(key: key);

  @override
  State<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<VoiceFab> {
  final VoiceService _voiceService = VoiceService();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    // Khởi tạo Microphone ngay khi màn hình hiện lên
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _voiceService.initialize();
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }

  void _toggleListening() async {
    if (_isListening) {
      // Đang nghe -> Dừng lại
      await _voiceService.stopListening();
      setState(() => _isListening = false);
    } else {
      // Chưa nghe -> Bắt đầu nghe
      setState(() => _isListening = true);
      
      // Hiển thị thông báo nhỏ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang nghe... Hãy nói sự cố (Ví dụ: "Có ổ gà phía trước")'),
          duration: Duration(seconds: 2),
        ),
      );

      await _voiceService.startListening(
        onResult: (text) {
          // Khi người dùng nói xong, text sẽ được trả về đây
          setState(() => _isListening = false);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã ghi nhận: "$text"')),
          );

          // Bắn text ra ngoài cho màn hình cha (Overlay) xử lý tiếp (Gọi AI)
          widget.onVoiceResult(text);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'voice_fab', // Tránh lỗi trùng heroTag nếu có nhiều FAB
      onPressed: _toggleListening,
      backgroundColor: _isListening ? Colors.red : Colors.deepOrange,
      child: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        color: Colors.white,
      ),
    );
  }
}
