import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/preference_scope.dart';

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
  SpeechSettings({PreferenceScope? scope})
    : _scope = scope ?? PreferenceScope.instance {
    _scope.addListener(_rescoped);
  }

  final PreferenceScope _scope;

  static final instance = SpeechSettings();

  SpeechPrefs _prefs = const SpeechPrefs();
  bool _loaded = false;

  /// Another account's choices are in use: read them.
  void _rescoped() {
    _loaded = false;
    load();
  }

  SpeechPrefs get prefs => _prefs;

  /// Reads the stored choices once. A phone that cannot be read leaves the defaults.
  Future<SpeechPrefs> load() async {
    if (_loaded) return _prefs;
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = SpeechPrefs(
        voiceName: p.getString(_scope.key(PrefKeys.speechVoiceName)),
        voiceLocale: p.getString(_scope.key(PrefKeys.speechVoiceLocale)),
        rate: (p.getDouble(_scope.key(PrefKeys.speechRate)) ?? 0.5).clamp(
          0.1,
          1.0,
        ),
        pitch: (p.getDouble(_scope.key(PrefKeys.speechPitch)) ?? 1.0).clamp(
          0.5,
          2.0,
        ),
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
        await p.remove(_scope.key(PrefKeys.speechVoiceName));
        await p.remove(_scope.key(PrefKeys.speechVoiceLocale));
      } else {
        await p.setString(
          _scope.key(PrefKeys.speechVoiceName),
          next.voiceName!,
        );
        await p.setString(
          _scope.key(PrefKeys.speechVoiceLocale),
          next.voiceLocale ?? '',
        );
      }
      await p.setDouble(_scope.key(PrefKeys.speechRate), next.rate);
      await p.setDouble(_scope.key(PrefKeys.speechPitch), next.pitch);
    } on Object {
      // the choice still holds for this run
    }
  }
}
