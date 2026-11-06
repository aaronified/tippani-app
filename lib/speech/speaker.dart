import 'package:flutter_tts/flutter_tts.dart';

/// Reads text aloud. An interface so a test can stand in for the phone's speech engine.
abstract class Speaker {
  /// Speaks [text] in [language] (a code such as "en" or "hi"; empty means the phone's own) and completes when
  /// it has finished or been stopped. False when the phone has no voice for that language, and nothing is said.
  Future<bool> speak(String text, String language);

  /// Stops whatever is being said; a pending [speak] completes.
  Future<void> stop();
}

/// Android's own text-to-speech. Nothing is recorded, stored or sent anywhere. The engine is made on first use.
class PlatformSpeaker implements Speaker {
  FlutterTts? _tts;

  Future<FlutterTts> _engine() async {
    var tts = _tts;
    if (tts == null) {
      tts = FlutterTts();
      await tts.awaitSpeakCompletion(true);
      _tts = tts;
    }
    return tts;
  }

  @override
  Future<bool> speak(String text, String language) async {
    final tts = await _engine();
    if (language.isNotEmpty) {
      final available = await tts.isLanguageAvailable(language);
      if (available != true && available != 1) return false;
      await tts.setLanguage(language);
    }
    await tts.speak(text);
    return true;
  }

  @override
  Future<void> stop() async {
    await _tts?.stop();
  }
}
