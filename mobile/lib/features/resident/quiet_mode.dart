// "I can't speak or make noise": one shared switch for the alert screen. No haptics, no sounds, dimmer content, yes/no only.
import 'package:flutter/foundation.dart';

class QuietMode extends ChangeNotifier {
  QuietMode({bool on = false}) : _on = on;
  bool _on;
  bool get on => _on;
  void set(bool value) {
    if (value == _on) return;
    _on = value;
    notifyListeners();
  }
}
