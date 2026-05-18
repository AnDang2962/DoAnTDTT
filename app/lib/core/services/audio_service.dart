/// xin quyền quản lí Micro 
class AudioService {
  /// Xin cấp quyền micro
  Future<bool> requestMicrophonePermission() async {
    // TODO: Implement sử dụng thư viện permission_handle để xin quyền micro
    return true;
  }

  /// Start recording audio
  Future<void> startRecording() async {
    // TODO: Implement code để ghi âm
  }

  /// Stop recording and return audio file path or bytes
  Future<String?> stopRecording() async {
    // TODO: Implement stop recording logic
    return null;
  }
}
