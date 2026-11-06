import 'package:flutter/material.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../library/models.dart';
import 'library_widgets.dart';
import 'quote_form_screen.dart';
import 'quote_screen.dart';
import 'work_form_screen.dart';
import 'work_screen.dart';

enum _Mode { quotes, works }

/// The library on the phone: every quote and work, searchable, with the way to add, open, favourite and
/// export them. It reads only the local [LibraryStore], so it works with no server.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    required this.picker,
    this.share = shareThroughSheet,
    this.shareImage = shareImageThroughSheet,
  });

  final LibraryStore store;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Mode _mode = _Mode.quotes;
  final _search = TextEditingController();
  bool _favourites = false;
  String? _tag;
  List<Quote> _quotes = const [];
  List<Work> _works = const [];
  Map<int, Work> _byId = const {};
  LibraryCounts? _counts;
  bool _loaded = false;

  /// Only the newest request may fill the list: a slow search must not overwrite a faster, newer one.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = ++_request;
    final all = await widget.store.works();
    final counts = await widget.store.counts();
    final quotes = _mode == _Mode.quotes
        ? await widget.store.quotes(
            query: _search.text,
            favouritesOnly: _favourites,
            tag: _tag,
          )
        : const <Quote>[];
    final works = _mode == _Mode.works
        ? await widget.store.works(query: _search.text)
        : const <Work>[];
    if (!mounted || me != _request) return;
    setState(() {
      _byId = {for (final w in all) w.id: w};
      _counts = counts;
      _quotes = quotes;
      _works = works;
      _loaded = true;
    });
  }

  Future<void> _addQuote() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuoteFormScreen(store: widget.store)),
    );
    await _load();
  }

  Future<void> _addWork() async {
    await Navigator.of(context).push<Work>(
      MaterialPageRoute(builder: (_) => WorkFormScreen(store: widget.store)),
    );
    await _load();
  }

  Future<void> _openQuote(Quote q) async {
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

  Future<void> _openWork(Work w) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkScreen(
          store: widget.store,
          workId: w.id,
          picker: widget.picker,
          share: widget.share,
          shareImage: widget.shareImage,
        ),
      ),
    );
    await _load();
  }

  Future<void> _pickTag() async {
    final tags = await widget.store.tags();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (tags.isEmpty)
              const ListTile(title: Text('No tags yet.'))
            else
              for (final t in tags)
                ListTile(
                  title: Text('#$t'),
                  selected: t == _tag,
                  onTap: () => Navigator.of(context).pop(t),
                ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _tag = picked);
    await _load();
  }

  void _export(ExportKind kind) => runExport(
    context,
    store: widget.store,
    share: widget.share,
    picker: widget.picker,
    kind: kind,
  );

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<ExportKind>(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: ExportKind.share,
                child: Text('Share as Markdown'),
              ),
              PopupMenuItem(
                value: ExportKind.save,
                child: Text('Save as Markdown file'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mode == _Mode.quotes ? _addQuote : _addWork,
        icon: const Icon(Icons.add),
        label: Text(_mode == _Mode.quotes ? 'Add a quote' : 'Add a work'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _mode == _Mode.quotes
                    ? 'Search words, people, works and tags'
                    : 'Search titles and creators',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SegmentedButton<_Mode>(
                  segments: [
                    ButtonSegment(
                      value: _Mode.quotes,
                      label: Text(
                        counts == null ? 'Quotes' : 'Quotes ${counts.quotes}',
                      ),
                    ),
                    ButtonSegment(
                      value: _Mode.works,
                      label: Text(
                        counts == null ? 'Works' : 'Works ${counts.works}',
                      ),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _mode = s.single);
                    _load();
                  },
                ),
                const Spacer(),
                if (_mode == _Mode.quotes) ...[
                  FilterChip(
                    label: const Text('Favourites'),
                    selected: _favourites,
                    onSelected: (v) {
                      setState(() => _favourites = v);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  InputChip(
                    label: Text(_tag == null ? 'Tag' : '#$_tag'),
                    selected: _tag != null,
                    onPressed: _pickTag,
                    onDeleted: _tag == null
                        ? null
                        : () {
                            setState(() => _tag = null);
                            _load();
                          },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final searching =
        _search.text.trim().isNotEmpty || _favourites || _tag != null;
    final empty = _mode == _Mode.quotes ? _quotes.isEmpty : _works.isEmpty;
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            searching
                ? 'Nothing matches.'
                : _mode == _Mode.quotes
                ? 'No quotes yet. Add the first one with the button below.'
                : 'No works yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: _mode == _Mode.quotes
          ? [
              for (final q in _quotes)
                QuoteTile(
                  quote: q,
                  work: _byId[q.workId],
                  onTap: () => _openQuote(q),
                  onFavourite: () async {
                    await widget.store.setFavorite(q.id, !q.favorite);
                    await _load();
                  },
                ),
            ]
          : [
              for (final w in _works)
                ListTile(
                  title: Text(w.title),
                  subtitle: Text(
                    [
                      workKindLabel(w.kind),
                      if (w.creator.isNotEmpty) w.creator,
                      if (w.year != null) '${w.year}',
                    ].join(' · '),
                  ),
                  onTap: () => _openWork(w),
                ),
            ],
    );
  }
}
