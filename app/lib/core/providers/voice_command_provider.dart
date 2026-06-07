import 'package:flutter/foundation.dart';

class VoiceCommandProvider extends ChangeNotifier {
  String _lastCommand = '';
  int _version = 0;

  String get lastCommand => _lastCommand;
  int get version => _version;

  void dispatch(String text) {
    if (text.isEmpty) return;
    _lastCommand = text;
    _version++;
    notifyListeners();
  }
}
