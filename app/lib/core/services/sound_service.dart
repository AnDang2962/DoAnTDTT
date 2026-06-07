import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _player = AudioPlayer();

  Future<void> playMemberJoin() => _play('assets/sounds/member_join.mp3');
  Future<void> playMemberLeave() => _play('assets/sounds/member_leave.mp3');

  Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset.replaceFirst('assets/', '')));
    } catch (_) {}
  }
}
