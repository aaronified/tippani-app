import 'package:flutter/material.dart';

import '../speech/speaker.dart';
import '../speech/speech_settings.dart';
import '../l10n/l10n.dart';

/// Chooses how the app reads aloud: which voice, how fast, how high. The voices are the ones Android's speech
/// service offers, so the natural-sounding ones appear after installing them in Android's own settings.
class ReadAloudSettingsScreen extends StatefulWidget {
  const ReadAloudSettingsScreen({super.key, this.speaker, this.settings});

  final Speaker? speaker;
  final SpeechSettings? settings;

  @override
  State<ReadAloudSettingsScreen> createState() =>
      _ReadAloudSettingsScreenState();
}

class _ReadAloudSettingsScreenState extends State<ReadAloudSettingsScreen> {
  late final Speaker _speaker = widget.speaker ?? PlatformSpeaker();
  late final SpeechSettings _settings =
      widget.settings ?? SpeechSettings.instance;
  List<SpeechVoice>? _voices;
  SpeechPrefs _prefs = const SpeechPrefs();
  String? _language;
  bool _testing = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _speaker.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await _settings.load();
    List<SpeechVoice> voices = const [];
    try {
      voices = [
        for (final v in await _speaker.voices())
          if (v.installed) v,
      ];
    } on Object {
      if (mounted) {
        setState(() => _problem = 'The phone would not list its voices.');
      }
    }
    if (!mounted) return;
    final languages = {for (final v in voices) v.language}.toList()..sort();
    setState(() {
      _prefs = prefs;
      _voices = voices;
      _language = prefs.voiceLocale != null && prefs.voiceName != null
          ? languageOf(prefs.voiceLocale!)
          : languages.contains('en')
          ? 'en'
          : (languages.isEmpty ? null : languages.first);
    });
  }

  Future<void> _save(SpeechPrefs next) async {
    setState(() => _prefs = next);
    await _settings.save(next);
  }

  Future<void> _test() async {
    if (_testing) {
      await _speaker.stop();
      return;
    }
    setState(() => _testing = true);
    try {
      final ok = await _speaker.speak(
        'Simplicity, simplicity, simplicity.',
        _language ?? 'en',
      );
      if (!ok && mounted) {
        setState(() => _problem = 'This phone has no voice for that language.');
      }
    } on Object {
      if (mounted) setState(() => _problem = 'The voice could not be tried.');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voices = _voices;
    final languages = voices == null
        ? <String>[]
        : ({for (final v in voices) v.language}.toList()..sort());
    final shown = voices == null
        ? <SpeechVoice>[]
        : ([
            for (final v in voices)
              if (v.language == _language) v,
          ]..sort((a, b) {
            final q = b.quality.compareTo(a.quality);
            if (q != 0) return q;
            if (a.networkRequired != b.networkRequired) {
              return a.networkRequired ? -1 : 1;
            }
            return a.name.compareTo(b.name);
          }));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Read aloud'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'The app uses Android’s own speech service. Online voices usually sound the most natural. To get more, '
            'or to change the speech service, open Android Settings and search for “Text-to-speech”.',
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Speed'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: _prefs.rate.clamp(0.1, 1.0),
            min: 0.1,
            max: 1.0,
            divisions: 9,
            label: _prefs.rate.toStringAsFixed(1),
            onChanged: (v) => _save(_prefs.copyWith(rate: v)),
          ),
          Text(
            context.tr('Pitch'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: _prefs.pitch.clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: _prefs.pitch.toStringAsFixed(1),
            onChanged: (v) => _save(_prefs.copyWith(pitch: v)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _test,
              icon: Icon(_testing ? Icons.stop : Icons.volume_up_outlined),
              label: Text(_testing ? 'Stop' : 'Try this voice'),
            ),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 8),
            Text(
              _problem!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            context.tr('Voice'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ListTile(
            leading: Icon(
              _prefs.voiceName == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(context.tr('Automatic')),
            subtitle: Text(
              context.tr('The best voice installed for each language'),
            ),
            onTap: () => _save(_prefs.copyWith(automatic: true)),
          ),
          if (voices == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (voices.isEmpty)
            Padding(
              padding: EdgeInsets.all(8),
              child: Text(context.tr('The phone lists no voices.')),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(labelText: context.tr('Language')),
              items: [
                for (final l in languages)
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) => setState(() => _language = v),
            ),
            for (final v in shown)
              ListTile(
                leading: Icon(
                  _prefs.voiceName == v.name && _prefs.voiceLocale == v.locale
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text('${v.locale} · ${v.name}'),
                subtitle: Text(v.description),
                onTap: () => _save(
                  _prefs.copyWith(voiceName: v.name, voiceLocale: v.locale),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
