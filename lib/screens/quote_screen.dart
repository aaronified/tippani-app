import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../anthologies/anthologies.dart';
import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/share_format.dart';
import '../speech/speaker.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import 'anthologies_screen.dart' show addToAnthologyDialog;
import 'quote_card.dart';
import 'quote_chips_row.dart';
import 'quote_context_section.dart';
import 'quote_form_screen.dart';
import 'share_screen.dart';
import 'work_screen.dart';
import '../l10n/l10n.dart';

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
    this.speaker,
    this.anthologies,
  });

  final LibraryStore store;
  final int quoteId;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;
  final Speaker? speaker;

  /// The server's anthologies; null (or not available) hides Add to anthology.
  final AnthologyService? anthologies;

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final _cardKey = GlobalKey();
  Quote? _quote;
  Work? _work;
  bool _loaded = false;
  bool _speaking = false;
  late final Speaker _speaker = widget.speaker ?? PlatformSpeaker();

  @override
  void dispose() {
    _speaker.stop();
    super.dispose();
  }

  Future<void> _speak() async {
    final q = _quote;
    if (q == null) return;
    if (_speaking) {
      await _speaker.stop();
      return;
    }
    final language = q.language.isNotEmpty
        ? q.language
        : (_work?.language ?? '');
    setState(() => _speaking = true);
    try {
      final ok = await _speaker.speak(q.text, language);
      if (!ok && mounted) _say('This phone has no voice for "$language".');
    } on Object {
      if (mounted) _say(context.tr('app.quote.the_quote_could_not_be_read'));
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

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
    final gone = _quote;
    final deleted = context.tr('app.quote.quote_deleted');
    final undo = context.tr('common.action.undo.label');
    // the messenger belongs to the app, so the Undo outlives this screen
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('quotes.delete.confirm')),
        content: Text(
          context.tr('app.quote_form.it_is_removed_from_this_phone'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('app.anthologies.keep_it')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.delete.label')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final store = widget.store;
    await store.deleteQuote(widget.quoteId);
    if (mounted) Navigator.of(context).pop(true);
    if (gone == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(deleted),
          action: SnackBarAction(
            label: undo,
            onPressed: () => store.addQuote(
              QuoteDraft(
                text: gone.text,
                workId: gone.workId,
                translation: gone.translation,
                language: gone.language,
                speaker: gone.speaker,
                chapter: gone.chapter,
                location: gone.location,
                note: gone.note,
                color: gone.color,
                favorite: gone.favorite,
                notedAt: gone.notedAt,
                source: gone.source,
                tags: gone.tags,
                boardId: gone.boardId,
              ),
            ),
          ),
        ),
      );
  }

  /// Puts the quote on the clipboard the way the web's copy button does: its words with the credit line.
  Future<void> _copy() async {
    final q = _quote;
    if (q == null) return;
    final on = shareDefaults(shareFieldsOf(q, _work));
    await Clipboard.setData(
      ClipboardData(text: buildShareText(q, _work, on, ShareFormat.plain)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(context.tr('account.widget.copied'))),
      );
  }

  void _share() {
    final q = _quote;
    if (q == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShareScreen(
          quote: q,
          work: _work,
          share: widget.share,
          shareImage: widget.shareImage,
          picker: widget.picker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    final theme = Theme.of(context);
    if (!_loaded || q == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loaded
            ? Center(
                child: Text(context.tr('app.quote.this_quote_is_not_here_any')),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final place = [
      q.chapter,
      q.location,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('common.field.quote.label')),
        actions: [
          IconButton(
            tooltip: q.favorite
                ? context.tr('common.action.favourite.off.label')
                : 'Favourite',
            icon: Icon(q.favorite ? Icons.star : Icons.star_border),
            onPressed: _favourite,
          ),
          IconButton(
            tooltip: context.tr('common.action.copy.label'),
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: context.tr('common.action.edit.label'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: context.tr('common.action.delete.label'),
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
          const SizedBox(height: 12),
          QuoteChipsRow(
            quote: q,
            work: _work,
            // the library opens on this name
            onTap: (f) => Navigator.of(context).pop(f),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.anthologies?.available == true && q.serverId != null)
                FilledButton.tonalIcon(
                  onPressed: () => addToAnthologyDialog(
                    context,
                    widget.anthologies!,
                    kind: entryKindOf(realmOfQuote(_work)),
                    itemId: q.serverId!,
                  ),
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  label: Text(context.tr('common.action.anthology.label')),
                ),
              FilledButton.tonalIcon(
                onPressed: _speak,
                icon: Icon(_speaking ? Icons.stop : Icons.volume_up_outlined),
                label: Text(
                  _speaking ? 'Stop' : context.tr('speech.play.aria'),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: Text(context.tr('common.action.share.label')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (q.note.isNotEmpty) ...[
            Text(
              context.tr('identity.field.note'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(q.note),
            const SizedBox(height: 16),
          ],
          QuoteContextSection(quote: q, work: _work),
          if (_work != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(_work!.title),
                subtitle: Text(
                  [
                    if (_work!.creator.isNotEmpty) _work!.creator,
                    if (place.isNotEmpty) place,
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openWork,
              ),
            )
          else if (place.isNotEmpty)
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(place)),
              ],
            ),
          if (q.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final t in q.tags) Chip(label: Text('#$t'))],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              context.tr('app.quote.noted_x', {'x': _date(q.notedAt)}),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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
