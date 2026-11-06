import 'package:flutter/material.dart';

import '../capture/voice_listener.dart';
import '../library/library_store.dart';
import 'quote_form_screen.dart';

/// Adds a quote by speaking it: press the microphone, say the words, press again, correct the text, then carry on
/// to the quote form to say where it is from and save. The app keeps no audio. Pops `true` when a quote was saved.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.store,
    this.workId,
    this.listener,
  });

  final LibraryStore store;
  final int? workId;
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
        _problem = 'This phone could not listen. Allow the microphone for Tippani, and check a speech service is installed.';
      });
    }
  }

  Future<void> _carryOn() async {
    if (_listening) {
      await _listener.stop();
      if (mounted) setState(() => _listening = false);
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuoteFormScreen(
          store: widget.store,
          workId: widget.workId,
          initialText: _text.text.trim(),
        ),
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Say a quote')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _locale,
            decoration: const InputDecoration(
              labelText: 'Language you will speak',
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
              label: Text(_listening ? 'Stop' : 'Start speaking'),
            ),
          ),
          if (_listening) ...[
            const SizedBox(height: 12),
            const Center(child: Text('Listening…')),
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
            decoration: const InputDecoration(
              labelText: 'The words, as heard',
              helperText: 'Correct anything it got wrong.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _carryOn,
            child: const Text('Use this text'),
          ),
          const SizedBox(height: 12),
          Text(
            'Tippani keeps no recording. Your phone’s speech service does the listening, and on some phones that service sends the audio to Google.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
