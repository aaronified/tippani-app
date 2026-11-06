import 'package:flutter/material.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/work_order.dart';
import 'library_widgets.dart';
import 'quote_form_screen.dart';
import 'quote_screen.dart';
import 'work_form_screen.dart';
import 'work_read_screen.dart';

/// One work: its details, the quotes taken from it, and what can be done with it (edit, export, delete).
class WorkScreen extends StatefulWidget {
  const WorkScreen({
    super.key,
    required this.store,
    required this.workId,
    required this.picker,
    this.share = shareThroughSheet,
    this.shareImage = shareImageThroughSheet,
  });

  final LibraryStore store;
  final int workId;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  Work? _work;
  List<Quote> _quotes = const [];
  bool _loaded = false;
  bool _onlyFavourites = false;
  bool _byChapter = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await widget.store.work(widget.workId);
    final qs = await widget.store.quotes(workId: widget.workId);
    if (!mounted) return;
    setState(() {
      _work = w;
      _quotes = qs;
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Work>(
      MaterialPageRoute(
        builder: (_) => WorkFormScreen(store: widget.store, work: _work),
      ),
    );
    if (saved != null) await _load();
  }

  Future<void> _addQuote() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            QuoteFormScreen(store: widget.store, workId: widget.workId),
      ),
    );
    await _load();
  }

  Future<void> _open(Quote q) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuoteScreen(
          store: widget.store,
          quoteId: q.id,
          picker: widget.picker,
          share: widget.share,
          shareImage: widget.shareImage,
        ),
      ),
    );
    await _load();
  }

  void _read() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkReadScreen(
          work: _work!,
          quotes: readingOrder(_quotes),
          share: widget.share,
        ),
      ),
    );
  }

  Widget _tile(Quote q) => QuoteTile(
    quote: q,
    work: null,
    onTap: () => _open(q),
    onFavourite: () async {
      await widget.store.setFavorite(q.id, !q.favorite);
      await _load();
    },
  );

  Future<void> _delete() async {
    final n = _quotes.length;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_work!.title}?'),
        content: Text(
          n == 0
              ? 'It is removed from this phone.'
              : 'Its $n ${n == 1 ? 'quote is' : 'quotes are'} deleted with it. This cannot be undone.',
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
    await widget.store.deleteWork(widget.workId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final w = _work;
    if (_loaded && w == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('This work is no longer in the library.'),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final favourites = _quotes.where((q) => q.favorite).length;
    final chapters = {
      for (final q in _quotes)
        if (q.chapter.trim().isNotEmpty) q.chapter.trim(),
    }.length;
    final shown = _onlyFavourites
        ? _quotes.where((q) => q.favorite).toList()
        : _quotes;
    final ordered = _byChapter ? readingOrder(shown) : shown;
    return Scaffold(
      appBar: AppBar(
        title: Text(w?.title ?? ''),
        actions: [
          if (w != null) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'share':
                  case 'save':
                    runExport(
                      context,
                      store: widget.store,
                      share: widget.share,
                      picker: widget.picker,
                      kind: v == 'share' ? ExportKind.share : ExportKind.save,
                      work: w,
                    );
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share', child: Text('Share as Markdown')),
                PopupMenuItem(
                  value: 'save',
                  child: Text('Save as Markdown file'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Delete work')),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: w == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addQuote,
              icon: const Icon(Icons.add),
              label: const Text('Add a quote'),
            ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w!.title, style: text.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        [
                          workKindLabel(w.kind),
                          if (w.creator.isNotEmpty) w.creator,
                          if (w.year != null) '${w.year}',
                          if (w.language.isNotEmpty) w.language,
                        ].join(' · '),
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_quotes.length} ${_quotes.length == 1 ? 'quote' : 'quotes'}'
                        '${chapters > 0 ? ' · $chapters ${chapters == 1 ? 'chapter' : 'chapters'}' : ''}'
                        ' · $favourites ${favourites == 1 ? 'favourite' : 'favourites'}',
                        style: text.bodySmall,
                      ),
                      if (_quotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _read,
                              icon: const Icon(Icons.menu_book_outlined),
                              label: const Text('Read'),
                            ),
                            FilterChip(
                              label: const Text('Favourites'),
                              selected: _onlyFavourites,
                              onSelected: (v) =>
                                  setState(() => _onlyFavourites = v),
                            ),
                            FilterChip(
                              label: const Text('In reading order'),
                              selected: _byChapter,
                              onSelected: (v) => setState(() => _byChapter = v),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_quotes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No quotes from this work yet.'),
                  ),
                if (_quotes.isNotEmpty && ordered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No favourites in this work yet.'),
                  ),
                if (_byChapter)
                  for (final g in groupByChapter(ordered)) ...[
                    if (g.name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(g.name, style: text.titleMedium),
                      ),
                    for (final q in g.quotes) _tile(q),
                  ]
                else
                  for (final q in ordered) _tile(q),
              ],
            ),
    );
  }
}
