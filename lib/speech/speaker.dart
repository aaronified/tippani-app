import 'package:flutter_tts/flutter_tts.dart';

import 'speech_settings.dart';

/// One voice the phone's speech service offers.
class SpeechVoice {
  const SpeechVoice({
    required this.name,
    required this.locale,
    required this.quality,
    required this.networkRequired,
    this.installed = true,
  });

  /// The service's own name for it ("en-us-x-tpf-network").
  final String name;

  /// A language tag such as "en-US" or "hi-IN".
  final String locale;

  /// 0 (very low) to 4 (very high), as Android rates it.
  final int quality;

  /// An online (usually neural, so more natural) voice.
  final bool networkRequired;

  /// False for a voice the service lists but has not downloaded.
  final bool installed;

  /// The language part of [locale], lower case: "en".
  String get language => locale.split(RegExp('[-_]')).first.toLowerCase();

  String get qualityWords => switch (quality) {
    4 => 'very high quality',
    3 => 'high quality',
    1 => 'low quality',
    0 => 'very low quality',
    _ => 'normal quality',
  };

  /// "high quality, online" for the picker.
  String get description => [
    qualityWords,
    if (networkRequired) 'online' else 'on this phone',
  ].join(' · ');

  factory SpeechVoice.fromMap(Map<Object?, Object?> m) => SpeechVoice(
    name: '${m['name'] ?? ''}',
    locale: '${m['locale'] ?? ''}',
    quality: switch ('${m['quality']}') {
      'very high' => 4,
      'high' => 3,
      'low' => 1,
      'very low' => 0,
      _ => 2,
    },
    networkRequired: '${m['network_required']}' == '1',
    installed: !'${m['features'] ?? ''}'.split('\t').contains('notInstalled'),
  );
}

/// The language part of a tag or code: "en-US" and "en" both give "en".
String languageOf(String tag) => tag.split(RegExp('[-_]')).first.toLowerCase();

/// The voice to speak [language] in ("en", "hi"; empty means the phone's own). The reader's chosen voice
/// wins when it is for that language (or when no language is asked for). Otherwise the best installed voice
/// for the language: higher quality first, and an online voice before an on-phone one of the same quality,
/// because the online ones are the natural-sounding ones. Null leaves the phone's default.
SpeechVoice? chooseVoice(
  List<SpeechVoice> all,
  String language,
  SpeechPrefs prefs,
) {
  final wanted = languageOf(language);
  final name = prefs.voiceName;
  if (name != null) {
    for (final v in all) {
      if (v.name == name &&
          v.locale == prefs.voiceLocale &&
          v.installed &&
          (wanted.isEmpty || v.language == wanted)) {
        return v;
      }
    }
  }
  if (wanted.isEmpty) return null;
  final candidates = [
    for (final v in all)
      if (v.installed && v.language == wanted) v,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final q = b.quality.compareTo(a.quality);
    if (q != 0) return q;
    if (a.networkRequired != b.networkRequired) {
      return a.networkRequired ? -1 : 1;
    }
    return a.name.compareTo(b.name);
  });
  return candidates.first;
}

/// Reads text aloud. An interface so a test can stand in for the phone's speech engine.
abstract class Speaker {
  /// Speaks [text] in [language] (a code such as "en" or "hi"; empty means the phone's own) and completes when
  /// it has finished or been stopped. False when the phone has no voice for that language, and nothing is said.
  Future<bool> speak(String text, String language);

  /// Stops whatever is being said; a pending [speak] completes.
  Future<void> stop();

  /// The voices the phone's speech service offers (empty when it cannot say).
  Future<List<SpeechVoice>> voices();
}

/// Android's own text-to-speech service, so the voices are whatever the phone has installed or can fetch
/// (Settings > Text-to-speech picks the engine). Nothing is recorded, stored or sent by the app. The engine
/// is made on first use.
class PlatformSpeaker implements Speaker {
  PlatformSpeaker({SpeechSettings? settings})
    : _settings = settings ?? SpeechSettings.instance;

  final SpeechSettings _settings;
  FlutterTts? _tts;
  List<SpeechVoice>? _voices;

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
  Future<List<SpeechVoice>> voices() async {
    final cached = _voices;
    if (cached != null) return cached;
    final tts = await _engine();
    final raw = await tts.getVoices;
    final out = <SpeechVoice>[
      if (raw is List)
        for (final m in raw)
          if (m is Map) SpeechVoice.fromMap(m),
    ];
    return _voices = out;
  }

  @override
  Future<bool> speak(String text, String language) async {
    final tts = await _engine();
    final prefs = await _settings.load();
    if (language.isNotEmpty) {
      final available = await tts.isLanguageAvailable(language);
      if (available != true && available != 1) return false;
      await tts.setLanguage(language);
    }
    await tts.setSpeechRate(prefs.rate);
    await tts.setPitch(prefs.pitch);
    try {
      final v = chooseVoice(await voices(), language, prefs);
      if (v != null) await tts.setVoice({'name': v.name, 'locale': v.locale});
    } on Object {
      // a service that will not list its voices still speaks in its default one
    }
    await tts.speak(text);
    return true;
  }

  @override
  Future<void> stop() async {
    await _tts?.stop();
  }
}
