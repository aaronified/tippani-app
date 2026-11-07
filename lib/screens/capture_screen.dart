import 'dart:io';

import 'package:flutter/material.dart';

import '../capture/photo_source.dart';
import '../capture/text_recogniser.dart';

/// Text read from a page, handed back to the quote form: [text] as the reader corrected it, and how it was
/// captured ([source]: "ocr").
class CapturedText {
  const CapturedText(this.text, this.source);
  final String text;
  final String source;
}

/// Reads text from a page: photograph it (or choose a picture), let Tesseract read the text on the phone, and
/// correct the text. Pops a [CapturedText] for the quote form to put in the words. Nothing leaves the phone.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    this.photos,
    this.recogniser = const TesseractRecogniser(),
  });

  final PhotoSource? photos;
  final TextRecogniser recogniser;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

/// The languages whose data is bundled with the app, as Tesseract names them.
const captureLanguages = {
  'eng': 'English',
  'hin': 'Hindi',
  'eng+hin': 'English and Hindi',
};

class _CaptureScreenState extends State<CaptureScreen> {
  late final PhotoSource _photos = widget.photos ?? DevicePhotos();
  final _text = TextEditingController();
  String _language = 'eng';
  String? _image;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _get(Future<String?> Function() fetch) async {
    String? path;
    try {
      path = await fetch();
    } on Object {
      if (mounted) {
        setState(() => _problem = 'The picture could not be opened.');
      }
      return;
    }
    if (path == null) return;
    await _recognise(path);
  }

  Future<void> _recognise(String path) async {
    setState(() {
      _image = path;
      _busy = true;
      _problem = null;
    });
    try {
      final raw = await widget.recogniser.read(path, _language);
      if (!mounted) return;
      final text = tidyRecognisedText(raw);
      setState(() {
        _text.text = text;
        if (text.isEmpty) {
          _problem = 'No text was found on that picture. Try again, closer and in better light.';
        }
      });
    } on Object {
      if (mounted) {
        setState(
          () => _problem = 'The text could not be read from that picture.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use() =>
      Navigator.of(context).pop(CapturedText(_text.text.trim(), 'ocr'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a page')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(
              labelText: 'Language of the page',
            ),
            items: [
              for (final e in captureLanguages.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _language = v ?? 'eng'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _get(_photos.take),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take a photo'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _get(_photos.choose),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose a picture'),
              ),
            ],
          ),
          if (_image != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 160,
                child: Image.file(
                  File(_image!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Reading the page on this phone…'),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 16),
            Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_image != null && !_busy) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: 14,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'The text, as read',
                helperText: 'Correct anything it got wrong, and delete what you do not want to keep.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : _use,
              child: const Text('Use this text'),
            ),
          ],
        ],
      ),
    );
  }
}
