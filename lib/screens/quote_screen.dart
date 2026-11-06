import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/quote_text.dart';
import 'quote_card.dart';
import 'quote_form_screen.dart';
import 'work_screen.dart';

/// Shares a picture through Android's share sheet. A function so a test can stand in for it.
typedef ShareImage = Future<void> Function(
  Uint8List png,
  String fileName,
  String text,
);

Future<void> shareImageThroughSheet(
  Uint8List png,
  String fileName,
  String text,
) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}

/// One quote, read in full: drawn as a card, with its note, tags and place, and what can be done with it:
/// favourite, edit, delete, share it as text or as a picture, or save the picture to a file. It reads only the
/// local [LibraryStore], so it works with no server.
class QuoteScreen extends StatefulWidget {
  const QuoteScreen({
    super.key,
    required this.store,
    required this.quoteId,
    required this.picker,
    this.share = shareThroughSheet,
    this.shareImage = shareImageThroughSheet,
  });

  final LibraryStore store;
  final int quoteId;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _cardKey = GlobalKey();
  Quote? _quote;
  Work? _work;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await widget.store.quote(widget.quoteId);
    final w = q?.workId == null ? null : await widget.store.work(q!.workId!);
    if (!mounted) return;
    if (q == null && _loaded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _quote = q;
      _work = w;
      _loaded = true;
    });
  }

  void _say(String message) {
    final messenger = ScaffoldMessenger.of(context);
    // The newest word first: an older message must not hold up this one.
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _favourite() async {
    final q = _quote;
    if (q == null) return;
    await widget.store.setFavorite(q.id, !q.favorite);
    await _load();
  }

  Future<void> _edit() async {
    final q = _quote;
    if (q == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuoteFormScreen(store: widget.store, quote: q),
      ),
    );
    await _load();
  }

  Future<void> _openWork() async {
    final w = _work;
    if (w == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkScreen(
          store: widget.store,
          workId: w.id,
          picker: widget.picker,
          share: widget.share,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this quote?'),
        content: const Text(
          'It is removed from this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.store.deleteQuote(widget.quoteId);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _shareText() async {
    final q = _quote;
    if (q == null) return;
    try {
      await widget.share(quoteShareText(q, _work), 'A quote');
    } on Object {
      if (mounted) _say('The quote could not be shared.');
    }
  }

  String get _fileName => 'tippani-quote-${widget.quoteId}.png';

  Future<void> _sharePicture() async {
    final q = _quote;
    if (q == null) return;
    try {
      final png = await captureCard(_cardKey);
      if (png == null) {
        if (mounted) _say('The picture could not be made.');
        return;
      }
      await widget.shareImage(png, _fileName, quoteShareText(q, _work));
    } on Object {
      if (mounted) _say('The picture could not be shared.');
    }
  }

  Future<void> _savePicture() async {
    try {
      final png = await captureCard(_cardKey);
      if (png == null) {
        if (mounted) _say('The picture could not be made.');
        return;
      }
      final saved = await widget.picker.save(_fileName, png);
      if (mounted) _say(saved ? 'Saved.' : 'Nothing was saved.');
    } on Object {
      if (mounted) _say('The picture could not be saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    final theme = Theme.of(context);
    if (!_loaded || q == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loaded
            ? const Center(child: Text('This quote is not here any more.'))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final place = [
      q.chapter,
      q.location,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote'),
        actions: [
          IconButton(
            tooltip: q.favorite ? 'Remove from favourites' : 'Favourite',
            icon: Icon(q.favorite ? Icons.star : Icons.star_border),
            onPressed: _favourite,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: RepaintBoundary(
                key: _cardKey,
                child: Container(
                  // A solid ground, so the rounded corners of the picture are not transparent (a chat app
                  // paints transparency black).
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: QuoteCard(quote: q, work: _work),
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
              FilledButton.tonalIcon(
                onPressed: _shareText,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share text'),
              ),
              FilledButton.tonalIcon(
                onPressed: _sharePicture,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Share picture'),
              ),
              FilledButton.tonalIcon(
                onPressed: _savePicture,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save picture'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (q.note.isNotEmpty) ...[
            Text('Your note', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(q.note),
            const SizedBox(height: 16),
          ],
          if (_work != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(_work!.title),
              subtitle: Text(
                [
                  if (_work!.creator.isNotEmpty) _work!.creator,
                  if (place.isNotEmpty) place,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openWork,
            )
          else if (place.isNotEmpty)
            Text(place),
          if (q.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final t in q.tags) Chip(label: Text('#$t'))],
            ),
          ],
          const SizedBox(height: 16),
          Text('Noted ${_date(q.notedAt)}', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
