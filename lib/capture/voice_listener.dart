import 'package:speech_to_text/speech_to_text.dart';

/// Turns speech into text. An interface so a test can stand in for the phone's recogniser.
abstract class VoiceListener {
  /// Starts listening in [locale] (such as "en_IN" or "hi_IN"). [onWords] gets the text heard so far, each
  /// time it changes. Returns false if the phone cannot listen (no recogniser, or no permission to record).
  Future<bool> start(String locale, void Function(String words) onWords);

  /// Stops listening; the words already heard stay with the caller.
  Future<void> stop();
}

/// Android's own speech recogniser, through the `speech_to_text` plugin. **It is the phone's recogniser, not the
/// app's:** on many phones it is Google's, which may send the audio to Google unless an offline language pack is
/// installed. The app itself records and stores no audio and sends none to the Tippani server.
class PhoneVoiceListener implements VoiceListener {
  final _speech = SpeechToText();
  bool _ready = false;

  @override
  Future<bool> start(String locale, void Function(String words) onWords) async {
    if (!_ready) {
      _ready = await _speech.initialize();
      if (!_ready) return false;
    }
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 8),
      ),
      onResult: (r) => onWords(r.recognizedWords),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();
}
