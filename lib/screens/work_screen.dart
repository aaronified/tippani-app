import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../capture/photo_source.dart';
import '../library/cover_cache.dart';
import '../tools/work_details_source.dart';
import 'work_details_section.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../anthologies/anthologies.dart';
import '../library/models.dart';
import '../tools/work_lookup.dart';
import '../library/work_order.dart';
import 'library_widgets.dart';
import 'capture_screen.dart';
import 'quote_form_screen.dart';
import 'quote_screen.dart';
import 'voice_screen.dart';
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
    this.anthologies,
    this.lookup,
    this.photos,
    this.readBytes,
  });

  /// Where a chosen cover picture comes from (the gallery); null uses the phone's own.
  final PhotoSource? photos;

  /// Reads a chosen picture's bytes; null reads the file. A function so a test needs no real file.
  final Future<Uint8List> Function(String path)? readBytes;

  final LibraryStore store;
  final int workId;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;
  final AnthologyService? anthologies;
  final WorkLookup? lookup;

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
    unawaited(_refreshDetails());
  }

  bool _askedDetails = false;

  /// Asks the server for the work's description, genres and cast when the page opens, if they were never
  /// fetched or are over a day old. One try per visit; offline, what was kept earlier stays on show.
  Future<void> _refreshDetails() async {
    if (_askedDetails) return;
    final w = _work;
    final source = context
        .getInheritedWidgetOfExactType<DetailsScope>()
        ?.source;
    if (w == null || source == null || w.serverId == null) return;
    final at = w.details.fetchedAt;
    if (at != null && DateTime.now().difference(at) < detailsFreshFor) return;
    _askedDetails = true;
    final d = await source.fetch(w);
    if (d == null || !mounted) return;
    await widget.store.setWorkDetails(w.id, d);
    if (mounted) await _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Work>(
      MaterialPageRoute(
        builder: (_) => WorkFormScreen(
          store: widget.store,
          work: _work,
          lookup: widget.lookup,
        ),
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

  Future<void> _scan() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CaptureScreen(store: widget.store, workId: widget.workId),
      ),
    );
    await _load();
  }

  Future<void> _say() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VoiceScreen(store: widget.store, workId: widget.workId),
      ),
    );
    await _load();
  }

  Future<void> _chooseCover() async {
    final source = CoverScope.of(context);
    final w = _work;
    if (source == null || w == null || w.serverId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final String? path;
    try {
      path = await (widget.photos ?? DevicePhotos()).choose();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('The picture could not be opened.')),
      );
      return;
    }
    if (path == null) return;
    final bytes = await (widget.readBytes ?? (p) => File(p).readAsBytes())(
      path,
    );
    final name = await source.upload(
      w,
      bytes,
      path.split(RegExp(r'[\\/]')).last,
    );
    messenger.clearSnackBars();
    if (name == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The server did not take that picture as a cover.'),
        ),
      );
      return;
    }
    await widget.store.setWorkCover(w.id, name);
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
          anthologies: widget.anthologies,
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
              tooltip: 'Say a quote',
              icon: const Icon(Icons.mic_none),
              onPressed: _say,
            ),
            IconButton(
              tooltip: 'Scan a page',
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: _scan,
            ),
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
                  case 'cover':
                    _chooseCover();
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'share',
                  child: Text('Share as Markdown'),
                ),
                const PopupMenuItem(
                  value: 'save',
                  child: Text('Save as Markdown file'),
                ),
                if (w.serverId != null && CoverScope.of(context) != null)
                  const PopupMenuItem(
                    value: 'cover',
                    child: Text('Choose a cover'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete work'),
                ),
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
                if (w!.cover.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: WorkCover(
                        work: w,
                        width: 120,
                        height: 180,
                        fallback: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.title, style: text.headlineSmall),
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
                WorkDetailsSection(work: w),
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
