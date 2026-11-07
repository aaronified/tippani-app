import 'dart:io';

import 'package:flutter/material.dart';

import '../capture/page_adjuster.dart';
import '../capture/photo_source.dart';
import '../capture/recognised_page.dart';
import '../capture/text_recogniser.dart';
import 'adjust_screen.dart';
import 'page_selector.dart';
import '../l10n/l10n.dart';

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
    this.adjuster,
    this.adjust = true,
  });

  final PhotoSource? photos;
  final TextRecogniser recogniser;

  /// Straightens and crops the picture; null uses the phone's own.
  final PageAdjuster? adjuster;

  /// Whether the picture is straightened and cropped before it is read. A test turns it off.
  final bool adjust;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

/// The languages whose data is bundled with the app, as Tesseract names them.
final captureLanguages = {
  'eng': 'English',
  'hin': 'Hindi',
  'eng+hin': 'English and Hindi',
};

class _CaptureScreenState extends State<CaptureScreen> {
  late final PhotoSource _photos = widget.photos ?? DevicePhotos();
  final _text = TextEditingController();
  String _language = 'eng';
  String? _image;
  RecognisedPage? _page;
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
        setState(
          () =>
              _problem = context.tr('app.work.the_picture_could_not_be_opened'),
        );
      }
      return;
    }
    if (path == null) return;
    if (widget.adjust) {
      if (!mounted) return;
      // The reader straightens and crops the page first; backing out of that drops the picture.
      final original = path;
      path = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              AdjustScreen(imagePath: original, adjuster: widget.adjuster),
        ),
      );
      if (path == null) return;
    }
    await _recognise(path);
  }

  Future<void> _recognise(String path) async {
    setState(() {
      _image = path;
      _page = null;
      _text.clear();
      _busy = true;
      _problem = null;
    });
    try {
      // The words with their places first, so the reader can pick on the picture; if that gives nothing, the plain text.
      RecognisedPage? page;
      try {
        page = parseHocr(await widget.recogniser.hocr(path, _language));
      } on Object {
        page = null;
      }
      if (!mounted) return;
      if (page != null && !page.isEmpty) {
        setState(() => _page = page);
        return;
      }
      final raw = await widget.recogniser.read(path, _language);
      if (!mounted) return;
      final text = tidyRecognisedText(raw);
      setState(() {
        _text.text = text;
        if (text.isEmpty) {
          _problem = context.tr('app.capture.no_text_was_found_on_that');
        }
      });
    } on Object {
      if (mounted) {
        setState(
          () => _problem = context.tr('app.capture.the_text_could_not_be_read'),
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
      appBar: AppBar(title: Text(context.tr('app.capture.scan_a_page'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
              labelText: context.tr('app.capture.language_of_the_page'),
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
                label: Text(context.tr('app.capture.take_a_photo')),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _get(_photos.choose),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.tr('anthologies.front.cover.choose')),
              ),
            ],
          ),
          if (_image != null && _page == null) ...[
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
            Text(context.tr('app.capture.reading_the_page_on_this_phone')),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 16),
            Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_page != null && !_busy) ...[
            const SizedBox(height: 16),
            PageSelector(
              key: ValueKey(_image),
              imagePath: _image!,
              page: _page!,
              onChanged: (t) => setState(() => _text.text = t),
            ),
          ],
          if (_image != null && !_busy) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: 14,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('app.capture.the_text_as_read'),
                helperText: context.tr(
                  'app.capture.correct_anything_it_got_wrong_and',
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : _use,
              child: Text(context.tr('app.capture.use_this_text')),
            ),
          ],
        ],
      ),
    );
  }
}
