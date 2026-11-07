import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText;
import '../library/models.dart';
import '../library/share_format.dart';
import '../share/share_picture.dart';
import 'quote_card.dart' show captureCard;
import 'quote_screen.dart' show ShareImage;

/// Puts text on the clipboard. A function so a test can stand in for the clipboard.
typedef CopyText = Future<void> Function(String text);

Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// One place to send a quote from, in any form: a picture, plain text, Markdown, WhatsApp or Reddit. The
/// reader switches parts on and off (the same parts, with the same defaults, as the web app's share dialog),
/// sees what will be sent, and shares, copies or saves it. Nothing here reaches a server.
class ShareScreen extends StatefulWidget {
  const ShareScreen({
    super.key,
    required this.quote,
    required this.work,
    required this.share,
    required this.shareImage,
    required this.picker,
    this.copy = copyToClipboard,
  });

  final Quote quote;
  final Work? work;
  final ShareText share;
  final ShareImage shareImage;
  final BackupPicker picker;
  final CopyText copy;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _cardKey = GlobalKey();
  late final List<ShareField> _fields = shareFieldsOf(
    widget.quote,
    widget.work,
  );
  late Set<String> _on = shareDefaults(_fields);
  ShareFormat _format = ShareFormat.picture;
  Brightness? _look;
  ShareMaterial _material = ShareMaterial.manuscript;
  bool _tint = false;
  late final _text = TextEditingController(text: _build());
  bool _busy = false;

  // What the reader picked last time for the picture, kept on the phone (the web keeps the same three).
  static const _kTheme = 'share_image_theme';
  static const _kMaterial = 'share_image_material';
  static const _kTint = 'share_image_tint';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString(_kTheme);
      if (!mounted) return;
      setState(() {
        if (t == 'light') _look = Brightness.light;
        if (t == 'dark') _look = Brightness.dark;
        _material = ShareMaterial.named(p.getString(_kMaterial));
        _tint = p.getBool(_kTint) ?? false;
      });
    } on Object {
      // nothing remembered: the defaults stand
    }
  }

  Future<void> _remember() async {
    final dark = (_look ?? Theme.of(context).brightness) == Brightness.dark;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTheme, dark ? 'dark' : 'light');
      await p.setString(_kMaterial, _material.name);
      await p.setBool(_kTint, _tint);
    } on Object {
      // not remembered this time
    }
  }

  String _build() => buildShareText(
    widget.quote,
    widget.work,
    _on,
    _format == ShareFormat.picture ? ShareFormat.plain : _format,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _rebuild(void Function() change) {
    setState(() {
      change();
      _text.text = _build();
    });
  }

  void _say(String message) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  String get _fileName => 'tippani-quote-${widget.quote.id}.png';

  Future<void> _shareText() async {
    try {
      await widget.share(_text.text, 'A quote');
    } on Object {
      if (mounted) _say('The quote could not be shared.');
    }
  }

  Future<void> _copy() async {
    try {
      await widget.copy(_text.text);
      if (mounted) _say('Copied.');
    } on Object {
      if (mounted) _say('The quote could not be copied.');
    }
  }

  Future<Uint8List?> _picture() async {
    final png = await captureCard(_cardKey, width: shareWidth * shareScale);
    if (png == null && mounted) _say('The picture could not be made.');
    return png;
  }

  Future<void> _sharePicture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await _picture();
      if (png == null) return;
      await widget.shareImage(
        png,
        _fileName,
        buildShareText(widget.quote, widget.work, _on, ShareFormat.plain),
      );
    } on Object {
      if (mounted) _say('The picture could not be shared.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePicture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await _picture();
      if (png == null) return;
      final saved = await widget.picker.save(_fileName, png);
      if (mounted) _say(saved ? 'Saved.' : 'Nothing was saved.');
    } on Object {
      if (mounted) _say('The picture could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picture = _format == ShareFormat.picture;
    final look = _look ?? theme.brightness;
    return Scaffold(
      appBar: AppBar(title: const Text('Share')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Format', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in ShareFormat.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _format == f,
                  onSelected: (_) => _rebuild(() => _format = f),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Include', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in _fields)
                FilterChip(
                  label: Text(f.label),
                  selected: _on.contains(f.id),
                  onSelected: (v) => _rebuild(() {
                    _on = {..._on};
                    v ? _on.add(f.id) : _on.remove(f.id);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (picture) ...[
            Row(
              children: [
                Text('Look', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
                SegmentedButton<Brightness>(
                  segments: const [
                    ButtonSegment(
                      value: Brightness.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(value: Brightness.dark, label: Text('Dark')),
                  ],
                  selected: {look},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _look = s.single);
                    _remember();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Material', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ShareMaterial>(
                    initialValue: _material,
                    isExpanded: true,
                    items: [
                      for (final m in ShareMaterial.values)
                        DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => _material = m);
                      _remember();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Quote colour'),
                  tooltip: "Adds the quote's colour to the picture, as a stripe beside the words.",
                  selected: _tint,
                  onSelected: (v) {
                    setState(() => _tint = v);
                    _remember();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                // Drawn at its own width and scaled to fit; the file is made from the unscaled picture.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: SharePicture(
                      quote: widget.quote,
                      work: widget.work,
                      on: _on,
                      dark: look == Brightness.dark,
                      material: _material,
                      tint: _tint,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _sharePicture,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _savePicture,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save picture'),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'The text',
                helperText: 'You can edit it before sending.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _shareText,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
