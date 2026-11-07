import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the reader wants things read aloud.
class SpeechPrefs {
  const SpeechPrefs({
    this.voiceName,
    this.voiceLocale,
    this.rate = 0.5,
    this.pitch = 1.0,
  });

  /// A voice picked by hand, or null for the best installed voice of each language.
  final String? voiceName;
  final String? voiceLocale;

  /// Speaking speed in the plugin's own scale: 0.5 is normal.
  final double rate;
  final double pitch;

  SpeechPrefs copyWith({
    String? voiceName,
    String? voiceLocale,
    bool automatic = false,
    double? rate,
    double? pitch,
  }) => SpeechPrefs(
    voiceName: automatic ? null : voiceName ?? this.voiceName,
    voiceLocale: automatic ? null : voiceLocale ?? this.voiceLocale,
    rate: rate ?? this.rate,
    pitch: pitch ?? this.pitch,
  );
}

/// The read-aloud choices, kept on the phone. One for the whole app so the settings screen and the speaker see
/// the same values.
class SpeechSettings extends ChangeNotifier {
  SpeechSettings();

  static final instance = SpeechSettings();

  SpeechPrefs _prefs = const SpeechPrefs();
  bool _loaded = false;

  SpeechPrefs get prefs => _prefs;

  /// Reads the stored choices once. A phone that cannot be read leaves the defaults.
  Future<SpeechPrefs> load() async {
    if (_loaded) return _prefs;
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = SpeechPrefs(
        voiceName: p.getString('speech_voice_name'),
        voiceLocale: p.getString('speech_voice_locale'),
        rate: (p.getDouble('speech_rate') ?? 0.5).clamp(0.1, 1.0),
        pitch: (p.getDouble('speech_pitch') ?? 1.0).clamp(0.5, 2.0),
      );
    } on Object {
      // keep the defaults
    }
    _loaded = true;
    notifyListeners();
    return _prefs;
  }

  Future<void> save(SpeechPrefs next) async {
    _prefs = next;
    _loaded = true;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (next.voiceName == null) {
        await p.remove('speech_voice_name');
        await p.remove('speech_voice_locale');
      } else {
        await p.setString('speech_voice_name', next.voiceName!);
        await p.setString('speech_voice_locale', next.voiceLocale ?? '');
      }
      await p.setDouble('speech_rate', next.rate);
      await p.setDouble('speech_pitch', next.pitch);
    } on Object {
      // the choice still holds for this run
    }
  }
}
