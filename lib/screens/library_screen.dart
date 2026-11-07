import 'dart:async';

import 'package:flutter/material.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../anthologies/anthologies.dart';
import '../library/models.dart';
import '../tools/work_lookup.dart';
import '../sync/auto_sync.dart';
import 'conflicts_screen.dart';
import 'boards_screen.dart';
import '../library/quote_chips.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import 'anthologies_screen.dart' show addToAnthologyDialog;
import 'bulk_bar.dart';
import 'library_widgets.dart';
import '../tags/tag_service.dart';
import 'quote_form_screen.dart';
import 'tags_screen.dart';
import 'quote_screen.dart';
import 'search_screen.dart';
import 'work_form_screen.dart';
import 'work_screen.dart';
import 'works_view.dart';
import '../l10n/l10n.dart';

enum _Mode { quotes, works }

/// Which part of the library a [LibraryScreen] shows. The app's navigation has one screen for each of the first three
/// (as the web app has its Library, Catalogue and Quotes); [all] is the whole library with a switch between quotes and
/// works.
enum LibrarySection {
  all,

  /// Books (and works of no particular kind).
  books,

  /// Films, shows and games.
  catalogue,

  /// Quotes, with their boards.
  quotes,
}

/// The library on the phone: every quote and work, searchable, with the way to add, open, favourite and
/// export them. It reads only the local [LibraryStore], so it works with no server.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    required this.picker,
    this.share = shareThroughSheet,
    this.shareImage = shareImageThroughSheet,
    this.anthologies,
    this.lookup,
    this.auto,
    this.section = LibrarySection.all,
  });

  /// Which part is shown; the default is all of it.
  final LibrarySection section;

  final LibraryStore store;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;
  final AnthologyService? anthologies;
  final WorkLookup? lookup;

  /// Shows that a sync is running and how many conflicts wait; null hides both.
  final AutoSync? auto;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late _Mode _mode = switch (widget.section) {
    LibrarySection.books || LibrarySection.catalogue => _Mode.works,
    _ => _Mode.quotes,
  };

  bool _inSection(Work w) {
    final screen =
        w.kind == WorkKind.film ||
        w.kind == WorkKind.show ||
        w.kind == WorkKind.game;
    return switch (widget.section) {
      LibrarySection.books => !screen,
      LibrarySection.catalogue => screen,
      _ => true,
    };
  }

  final _search = TextEditingController();
  bool _favourites = false;
  String? _tag;

  /// null: every board; [_noBoard]: quotes on no board; otherwise a board's id.
  int? _boardFilter;
  static const _noBoard = -1;
  bool _groupByBoard = false;
  List<Board> _boards = const [];
  List<Quote> _quotes = const [];
  List<Work> _works = const [];

  /// The quotes (or, in the works list, the works) the reader has selected, by id. Empty: not selecting.
  final _picked = <int>{};
  bool get _selecting => _picked.isNotEmpty;

  void _toggle(int id) => setState(() {
    if (!_picked.add(id)) _picked.remove(id);
  });

  void _endSelecting() => setState(_picked.clear);

  /// A bulk change is done: leave selecting and read the library again.
  void _bulkDone() {
    if (!mounted) return;
    setState(_picked.clear);
    _load();
  }

  Map<int, Work> _byId = const {};
  LibraryCounts? _counts;
  bool _loaded = false;

  /// Only the newest request may fill the list: a slow search must not overwrite a faster, newer one.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // The sections are separate screens over one library: a change made in one (or by a sync) shows in the others.
    _changes = widget.store.changes.listen((_) => _load());
    widget.auto?.addListener(_onSync);
  }

  StreamSubscription<void>? _changes;
  bool _wasSyncing = false;

  void _onSync() {
    final syncing = widget.auto?.syncing ?? false;
    if (_wasSyncing && !syncing) _load();
    _wasSyncing = syncing;
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.auto?.removeListener(_onSync);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = ++_request;
    final all = await widget.store.works();
    final counts = await widget.store.counts();
    // in the order the reader put them in (the server's), the rest by name
    final boards = await widget.store.boards()
      ..sort((x, y) {
        final p = (x.pos ?? 1 << 30).compareTo(y.pos ?? 1 << 30);
        return p != 0
            ? p
            : x.name.toLowerCase().compareTo(y.name.toLowerCase());
      });
    final quotes = _mode == _Mode.quotes
        ? await widget.store.quotes(
            query: _search.text,
            favouritesOnly: _favourites,
            tag: _tag,
            boardId: _boardFilter != null && _boardFilter != _noBoard
                ? _boardFilter
                : null,
            unfiled: _boardFilter == _noBoard,
            standalone: widget.section == LibrarySection.quotes,
          )
        : const <Quote>[];
    final works = _mode == _Mode.works
        ? [
            for (final w in await widget.store.works(query: _search.text))
              if (_inSection(w)) w,
          ]
        : const <Work>[];
    if (!mounted || me != _request) return;
    setState(() {
      _byId = {for (final w in all) w.id: w};
      _boards = boards;
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
      MaterialPageRoute(
        builder: (_) => WorkFormScreen(
          store: widget.store,
          lookup: widget.lookup,
          initialKind: widget.section == LibrarySection.catalogue
              ? WorkKind.film
              : WorkKind.book,
        ),
      ),
    );
    await _load();
  }

  /// Shows the library for a name pressed on a chip: the search box holds it and every other narrowing is cleared.
  Future<void> _applyChip(Object? result) async {
    if (result is! ChipFilter) return;
    setState(() {
      _mode = _Mode.quotes;
      _search.text = result.name;
      _favourites = false;
      _tag = null;
      _boardFilter = null;
    });
  }

  Future<void> _openQuote(Quote q) async {
    final result = await Navigator.of(context).push<Object?>(
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
    await _applyChip(result);
    await _load();
  }

  Future<void> _openWork(Work w) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => WorkScreen(
          store: widget.store,
          workId: w.id,
          picker: widget.picker,
          share: widget.share,
          shareImage: widget.shareImage,
          anthologies: widget.anthologies,
          lookup: widget.lookup,
        ),
      ),
    );
    await _applyChip(result);
    await _load();
  }

  Future<void> _manageBoards() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BoardsScreen(
          store: widget.store,
          picker: widget.picker,
          anthologies: widget.anthologies,
          auto: widget.auto,
        ),
      ),
    );
    // a board may have been deleted while it was the filter
    if (_boardFilter != null &&
        _boardFilter != _noBoard &&
        !(await widget.store.boards()).any((b) => b.id == _boardFilter)) {
      _boardFilter = null;
    }
    await _load();
  }

  Future<void> _pickBoard() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(context.tr('app.bulk_bar.no_board')),
              selected: _boardFilter == _noBoard,
              onTap: () => Navigator.of(context).pop(_noBoard),
            ),
            if (_boards.isEmpty)
              ListTile(
                title: Text(
                  context.tr('app.library.no_boards_yet_make_one_from'),
                ),
              )
            else
              // a hidden board is left out, unless it is the one being filtered by
              for (final b in _boards.where(
                (b) => !b.hidden || b.id == _boardFilter,
              ))
                ListTile(
                  title: Text(b.name),
                  trailing: Text(
                    context.tr('app.library.quotes', {'quotes': b.quotes}),
                  ),
                  selected: b.id == _boardFilter,
                  onTap: () => Navigator.of(context).pop(b.id),
                ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _boardFilter = picked);
    await _load();
  }

  Future<void> _pickTag() async {
    final tags = await widget.store.tags();
    if (!mounted) return;
    const manage = '\u0000manage';
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (tags.isEmpty)
              ListTile(title: Text(context.tr('app.library.no_tags_yet')))
            else
              for (final t in tags)
                ListTile(
                  title: Text('#$t'),
                  selected: t == _tag,
                  onTap: () => Navigator.of(context).pop(t),
                ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(context.tr('app.library.manage_tags')),
              subtitle: Text(
                context.tr('app.library.rename_colour_merge_delete'),
              ),
              onTap: () => Navigator.of(context).pop(manage),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == manage) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TagsScreen(
            store: widget.store,
            picker: widget.picker,
            service: TagServiceScope.of(context),
            anthologies: widget.anthologies,
          ),
        ),
      );
      if (_tag != null && !(await widget.store.tags()).contains(_tag)) {
        _tag = null;
      }
      await _load();
      return;
    }
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
    final PreferredSizeWidget bar;
    if (_selecting) {
      final quoteMode = _mode == _Mode.quotes;
      final chosenQuotes = [
        for (final q in _quotes)
          if (_picked.contains(q.id)) q,
      ];
      final chosenWorks = [
        for (final w in _works)
          if (_picked.contains(w.id)) w,
      ];
      bar = bulkAppBar(
        context,
        count: quoteMode ? chosenQuotes.length : chosenWorks.length,
        total: quoteMode ? _quotes.length : _works.length,
        onClose: _endSelecting,
        onAll: () => setState(
          () => _picked.addAll(
            quoteMode ? _quotes.map((q) => q.id) : _works.map((w) => w.id),
          ),
        ),
        actions: quoteMode
            ? QuoteBulkActions(
                store: widget.store,
                anthologies: widget.anthologies,
                quotes: chosenQuotes,
                done: _bulkDone,
              ).bar(context)
            : WorkBulkActions(
                store: widget.store,
                works: chosenWorks,
                all: _works,
                done: _bulkDone,
              ).bar(context),
      );
    } else {
      bar = _normalBar(context);
    }
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSelecting();
      },
      child: _scaffold(context, bar, counts),
    );
  }

  AppBar _normalBar(BuildContext context) {
    return AppBar(
      title: Text(switch (widget.section) {
        LibrarySection.catalogue => context.tr('nav.tab.movies.label'),
        LibrarySection.quotes => context.tr('nav.tab.quotes.label'),
        _ => context.tr('nav.tab.library.label'),
      }),
      actions: [
        IconButton(
          tooltip: context.tr('search.results.everything.label'),
          icon: const Icon(Icons.manage_search),
          onPressed: () => openSearch(
            context,
            store: widget.store,
            picker: widget.picker,
            share: widget.share,
            shareImage: widget.shareImage,
            anthologies: widget.anthologies,
            lookup: widget.lookup,
            initial: _search.text,
          ),
        ),
        if (widget.section == LibrarySection.all ||
            widget.section == LibrarySection.quotes)
          IconButton(
            tooltip: context.tr('tour.step.boards.name'),
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: _manageBoards,
          ),
        if (widget.auto != null)
          ListenableBuilder(
            listenable: widget.auto!,
            builder: (context, _) {
              final auto = widget.auto!;
              final n = auto.conflicts.length;
              if (n > 0) {
                return IconButton(
                  tooltip: n == 1 ? '1 sync conflict' : '$n sync conflicts',
                  icon: Badge(
                    label: Text('$n'),
                    child: const Icon(Icons.sync_problem_outlined),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConflictsScreen(auto: auto),
                    ),
                  ),
                );
              }
              if (auto.syncing) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        PopupMenuButton<ExportKind>(
          tooltip: context.tr('common.action.export.label'),
          icon: const Icon(Icons.ios_share),
          onSelected: _export,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: ExportKind.share,
              child: Text(context.tr('app.library.share_as_markdown')),
            ),
            PopupMenuItem(
              value: ExportKind.save,
              child: Text(context.tr('app.library.save_as_markdown_file')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scaffold(BuildContext context, PreferredSizeWidget bar, counts) {
    return Scaffold(
      appBar: bar,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-${widget.section.name}',
              onPressed: _mode == _Mode.quotes ? _addQuote : _addWork,
              icon: const Icon(Icons.add),
              label: Text(
                _mode == _Mode.quotes
                    ? context.tr('app.work.add_a_quote')
                    : switch (widget.section) {
                        LibrarySection.books => context.tr(
                          'app.library.add_a_book',
                        ),
                        LibrarySection.catalogue => context.tr(
                          'app.library.add_a_film_show_or_game',
                        ),
                        _ => context.tr('identity.works.add.label'),
                      },
              ),
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
                    ? context.tr(
                        'app.library.search_words_people_works_and_tags',
                      )
                    : context.tr(
                        'app.metadata_tools.search_titles_and_creators',
                      ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr(
                          'common.selection.shelf.clear.label',
                        ),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
                border: _pill(),
                enabledBorder: _pill(),
                focusedBorder: _pill(
                  BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (widget.section == LibrarySection.all)
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
              ],
            ),
          ),
          if (_mode == _Mode.quotes)
            SizedBox(
              height: 44,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text(
                        context.tr('stats.overview.favourites.label'),
                      ),
                      selected: _favourites,
                      onSelected: (v) {
                        setState(() => _favourites = v);
                        _load();
                      },
                    ),
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
                    InputChip(
                      label: Text(
                        _boardFilter == null
                            ? context.tr('common.field.board.label')
                            : _boardFilter == _noBoard
                            ? context.tr('app.bulk_bar.no_board')
                            : _boards
                                      .where((b) => b.id == _boardFilter)
                                      .map((b) => b.name)
                                      .firstOrNull ??
                                  context.tr('common.field.board.label'),
                      ),
                      selected: _boardFilter != null,
                      onPressed: _pickBoard,
                      onDeleted: _boardFilter == null
                          ? null
                          : () {
                              setState(() => _boardFilter = null);
                              _load();
                            },
                    ),
                    FilterChip(
                      label: Text(context.tr('app.library.group_by_board')),
                      selected: _groupByBoard,
                      onSelected: (v) => setState(() => _groupByBoard = v),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  static OutlineInputBorder _pill([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: side,
      );

  Widget _quoteTile(Quote q) => QuoteTile(
    quote: q,
    work: _byId[q.workId],
    onChip: (f) {
      _applyChip(f);
      _load();
    },
    selected: _picked.contains(q.id),
    onLongPress: () => _toggle(q.id),
    onTap: () => _selecting ? _toggle(q.id) : _openQuote(q),
    onFavourite: () async {
      await widget.store.setFavorite(q.id, !q.favorite);
      await _load();
    },
    onAddToAnthology:
        widget.anthologies?.available == true && q.serverId != null
        ? () => addToAnthologyDialog(
            context,
            widget.anthologies!,
            kind: entryKindOf(realmOfQuote(_byId[q.workId])),
            itemId: q.serverId!,
          )
        : null,
  );

  /// The quotes under a heading per board (in name order), then the rest under "Not on a board".
  List<Widget> _groupedQuotes() {
    final out = <Widget>[];
    void heading(String text, int n, Color? dot) => out.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            if (dot != null) ...[
              CircleAvatar(radius: 6, backgroundColor: dot),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('$n'),
          ],
        ),
      ),
    );
    for (final b in _boards) {
      final here = [
        for (final q in _quotes)
          if (q.boardId == b.id) q,
      ];
      if (here.isEmpty) continue;
      heading(
        b.name,
        here.length,
        b.color.isEmpty ? null : quoteColour(b.color),
      );
      out.addAll(here.map(_quoteTile));
    }
    final rest = [
      for (final q in _quotes)
        if (q.boardId == null) q,
    ];
    if (rest.isNotEmpty) {
      heading(context.tr('app.library.not_on_a_board'), rest.length, null);
      out.addAll(rest.map(_quoteTile));
    }
    return out;
  }

  Widget _list() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final searching =
        _search.text.trim().isNotEmpty ||
        _favourites ||
        _tag != null ||
        _boardFilter != null;
    final empty = _mode == _Mode.quotes ? _quotes.isEmpty : _works.isEmpty;
    if (empty) {
      return EmptyState(
        icon: searching
            ? Icons.search_off_rounded
            : _mode == _Mode.quotes
            ? Icons.format_quote_rounded
            : widget.section == LibrarySection.catalogue
            ? Icons.movie_outlined
            : Icons.menu_book_rounded,
        title: searching
            ? context.tr('app.search.nothing_matches')
            : _mode == _Mode.quotes
            ? context.tr('app.library.no_quotes_yet')
            : switch (widget.section) {
                LibrarySection.books => context.tr('app.library.no_books_yet'),
                LibrarySection.catalogue => context.tr(
                  'app.library.no_films_shows_or_games_yet',
                ),
                _ => context.tr('app.library.no_works_yet'),
              },
        hint: searching
            ? context.tr('app.library.try_fewer_words_or_clear_a')
            : _mode == _Mode.quotes
            ? context.tr('app.library.add_the_first_one_with_the')
            : context.tr('app.library.add_one_with_the_button_below'),
      );
    }
    if (_mode == _Mode.works) {
      return WorksView(
        works: _works,
        selected: _picked,
        onLongPress: (w) => _toggle(w.id),
        onOpen: (w) => _selecting ? _toggle(w.id) : _openWork(w),
        sectionKey: widget.section == LibrarySection.catalogue
            ? 'catalogue'
            : 'books',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: _groupByBoard
          ? _groupedQuotes()
          : [for (final q in _quotes) _quoteTile(q)],
    );
  }
}
