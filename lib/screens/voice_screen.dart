import 'package:flutter/material.dart';

import '../capture/voice_listener.dart';
import 'capture_screen.dart' show CapturedText;
import '../l10n/l10n.dart';

/// Turns speech into words: press the microphone, say them, press again, and correct the text. Pops a
/// [CapturedText] for the quote form to put in the words. The app keeps no audio.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key, this.listener});

  final VoiceListener? listener;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

/// Languages offered, as the phone's recogniser names them.
const voiceLocales = {
  'en_IN': 'English (India)',
  'en_US': 'English (US)',
  'en_GB': 'English (UK)',
  'hi_IN': 'Hindi',
  'bn_IN': 'Bengali',
};

class _VoiceScreenState extends State<VoiceScreen> {
  late final VoiceListener _listener = widget.listener ?? PhoneVoiceListener();
  final _text = TextEditingController();
  String _locale = 'en_IN';
  bool _listening = false;
  String? _problem;

  @override
  void dispose() {
    _listener.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      setState(() => _listening = false);
      await _listener.stop();
      return;
    }
    setState(() {
      _listening = true;
      _problem = null;
    });
    // What is already in the box (an earlier take, or the reader's edits) stays, and new speech is added.
    final before = _text.text.trim();
    var ok = false;
    try {
      ok = await _listener.start(_locale, (words) {
        if (!mounted) return;
        setState(() {
          _text.text = [
            before,
            words.trim(),
          ].where((s) => s.isNotEmpty).join(' ');
        });
      });
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _listening = false;
        _problem = context.tr('app.voice.this_phone_could_not_listen_allow');
      });
    }
  }

  Future<void> _use() async {
    if (_listening) {
      await _listener.stop();
      if (mounted) setState(() => _listening = false);
    }
    if (!mounted) return;
    // The server accepts only "manual" and "ocr" as a quote's source, so spoken words are kept as typed ones.
    Navigator.of(context).pop(CapturedText(_text.text.trim(), 'manual'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.voice.say_a_quote'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _locale,
            decoration: InputDecoration(
              labelText: context.tr('app.voice.language_you_will_speak'),
            ),
            items: [
              for (final e in voiceLocales.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _listening
                ? null
                : (v) => setState(() => _locale = v ?? 'en_IN'),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(160, 64),
                backgroundColor: _listening ? theme.colorScheme.error : null,
              ),
              onPressed: _toggle,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(
                _listening ? 'Stop' : context.tr('app.voice.start_speaking'),
              ),
            ),
          ),
          if (_listening) ...[
            const SizedBox(height: 12),
            Center(child: Text(context.tr('app.voice.listening'))),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 16),
            Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('app.voice.the_words_as_heard'),
              helperText: context.tr('app.voice.correct_anything_it_got_wrong'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _use,
            child: Text(context.tr('app.capture.use_this_text')),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('app.voice.tippani_keeps_no_recording_your_phone'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
