import 'package:flutter/foundation.dart';

import 'speaker.dart';

/// Reads one quote aloud at a time for the lists: pressing Speak on a card reads it, pressing it again stops, and
/// pressing it on another card stops the first and reads that one. Shared, so there is one voice, not one per card.
class QuoteSpeech extends ChangeNotifier {
  QuoteSpeech([Speaker? speaker]) : _speaker = speaker;

  static QuoteSpeech instance = QuoteSpeech();

  Speaker? _speaker;
  Speaker get speaker => _speaker ??= PlatformSpeaker();
  set speaker(Speaker s) => _speaker = s;

  int? _speaking;

  /// The id of the quote being read, or null.
  int? get speaking => _speaking;

  /// Reads [text] for quote [id], or stops it if it is the one being read. False when the phone has no voice for
  /// [language] or could not read it.
  Future<bool> toggle(int id, String text, String language) async {
    if (_speaking == id) {
      await stop();
      return true;
    }
    if (_speaking != null) await speaker.stop();
    _speaking = id;
    notifyListeners();
    var ok = false;
    try {
      ok = await speaker.speak(text, language);
    } on Object {
      ok = false;
    } finally {
      if (_speaking == id) {
        _speaking = null;
        notifyListeners();
      }
    }
    return ok;
  }

  Future<void> stop() async {
    _speaking = null;
    notifyListeners();
    await speaker.stop();
  }
}
