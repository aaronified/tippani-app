import 'dart:async';

import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';
import '../library/cover_cache.dart' show WorkCover;
import '../people/face_stack.dart';
import '../people/people_directory.dart';
import '../search/search_models.dart';
import '../search/search_service.dart';
import '../tools/work_lookup.dart';
import 'library_widgets.dart';
import 'person_screen.dart';
import 'quote_form_screen.dart' show quoteColour;
import 'quote_screen.dart';
import 'work_screen.dart';
import '../theme/app_theme.dart';

/// Opens the search page over the current screen. [initial] is what the box starts with.
Future<void> openSearch(
  BuildContext context, {
  required LibraryStore store,
  required BackupPicker picker,
  ShareText share = shareThroughSheet,
  ShareImage shareImage = shareImageThroughSheet,
  AnthologyService? anthologies,
  WorkLookup? lookup,
  String initial = '',
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => SearchScreen(
      store: store,
      picker: picker,
      share: share,
      shareImage: shareImage,
      anthologies: anthologies,
      lookup: lookup,
      initial: initial,
    ),
  ),
);

/// The pill that looks like a search box and opens the search page when pressed.
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('app.search.search_words_names_tags_and_titles'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The search page. Searches the paired server when there is one (it forgives typos and reads the credit and tag
/// columns) and the phone's own library otherwise, and says which it did. Results come in the web's sections:
/// titles, people, characters, tags, genres, notes and quotes, with the matched words marked. A name, a tag or a
/// colour can be set as a filter (a chip, or typed as `tag:life`).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    required this.picker,
    this.share = shareThroughSheet,
    this.shareImage = shareImageThroughSheet,
    this.anthologies,
    this.lookup,
    this.server,
    this.initial = '',
    this.initialFacets = const [],
  });

  final LibraryStore store;
  final BackupPicker picker;
  final ShareText share;
  final ShareImage shareImage;
  final AnthologyService? anthologies;
  final WorkLookup? lookup;

  /// The server's search; null takes it from the app (see [ServerSearchScope]).
  final ServerSearch? server;

  /// What the box starts with, and the filters already set.
  final String initial;
  final List<SearchFacet> initialFacets;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _text = TextEditingController(text: widget.initial);
  final _focus = FocusNode();
  late final List<SearchFacet> _facets = [...widget.initialFacets];
  SearchScope _scope = SearchScope.all;
  SearchResults? _results;
  SearchVocabulary _vocab = SearchVocabulary.empty;
  bool _busy = false;
  Timer? _debounce;
  int _request = 0;
  ServerSearch? _server;
  late final _local = LocalSearch(widget.store);

  /// Everything on the phone, to turn a hit into the row that is here (a hit knows the server's id).
  List<Work> _works = const [];
  List<Quote> _quotes = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _server ??= widget.server ?? ServerSearchScope.of(context);
    if (_vocab.byField.isEmpty && !_loadingVocab) _loadVocab();
  }

  bool _loadingVocab = false;

  Future<void> _loadVocab() async {
    _loadingVocab = true;
    SearchVocabulary v;
    try {
      v = _server?.available == true
          ? await _server!.vocabulary()
          : await _local.vocabulary();
    } on Object {
      v = await _local.vocabulary();
    }
    if (mounted) setState(() => _vocab = v);
    if (_text.text.trim().isNotEmpty || _facets.isNotEmpty) _run();
  }

  @override
  void initState() {
    super.initState();
    _readPhone();
    if (widget.initial.trim().isNotEmpty || widget.initialFacets.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  Future<void> _readPhone() async {
    final w = await widget.store.works();
    final q = await widget.store.quotes(limit: 1 << 30);
    if (mounted) {
      setState(() {
        _works = w;
        _quotes = q;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The words and the facets as the reader has set them: the chips, and any `field:value` typed in the box.
  ({String words, List<SearchFacet> facets}) get _query {
    final typed = parseQuery(_text.text);
    final all = <SearchFacet>[..._facets];
    for (final f in typed.facets) {
      if (!all.contains(f)) all.add(f);
    }
    return (words: typed.words, facets: all);
  }

  void _changed() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final q = _query;
    if (q.words.isEmpty && q.facets.isEmpty) {
      setState(() {
        _results = null;
        _busy = false;
      });
      return;
    }
    final me = ++_request;
    setState(() => _busy = true);
    SearchResults r;
    final server = _server;
    if (server != null && server.available) {
      try {
        r = await server.search(q.words, scope: _scope, facets: q.facets);
      } on Object {
        r = (await _local.search(
          q.words,
          scope: _scope,
          facets: q.facets,
        )).withFallback();
      }
    } else {
      r = await _local.search(q.words, scope: _scope, facets: q.facets);
    }
    if (!mounted || me != _request) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  void _addFacet(SearchFacet f, {String? replaceText}) {
    setState(() {
      if (!_facets.contains(f)) _facets.add(f);
      if (replaceText != null) _text.text = replaceText;
    });
    _run();
  }

  void _removeFacet(SearchFacet f) {
    setState(() => _facets.remove(f));
    _run();
  }

  // ---- finding what a hit is on the phone ----

  Work? _workFor(WorkHit h) {
    if (h.localId != null) {
      return _works.where((w) => w.id == h.localId).firstOrNull;
    }
    bool screen(Work w) =>
        w.kind == WorkKind.film ||
        w.kind == WorkKind.show ||
        w.kind == WorkKind.game;
    return _works
        .where((w) => w.serverId == h.serverId && screen(w) == h.screen)
        .firstOrNull;
  }

  Quote? _quoteFor(QuoteHit h) {
    if (h.localId != null) {
      return _quotes.where((q) => q.id == h.localId).firstOrNull;
    }
    final byId = {for (final w in _works) w.id: w};
    return _quotes.where((q) {
      if (q.serverId != h.serverId) return false;
      final w = byId[q.workId];
      final kind = w == null
          ? QuoteHitKind.standalone
          : (w.kind == WorkKind.film ||
                w.kind == WorkKind.show ||
                w.kind == WorkKind.game)
          ? QuoteHitKind.line
          : QuoteHitKind.highlight;
      return kind == h.kind;
    }).firstOrNull;
  }

  Future<void> _afterOpen(Object? result) async {
    if (result is ChipFilter) {
      setState(() => _text.text = result.name);
      _run();
    }
    await _readPhone();
  }

  Future<void> _openWork(WorkHit h) async {
    final w = _workFor(h);
    if (w == null) {
      _say(context.tr('app.search.that_is_on_the_server_only'));
      return;
    }
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
    await _afterOpen(result);
  }

  Future<void> _openQuote(QuoteHit h) async {
    final q = _quoteFor(h);
    if (q == null) {
      // not on the phone yet: read it here
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.text, style: quoteStyle(context, size: 18)),
                const SizedBox(height: 12),
                Text(
                  [
                    if (h.speaker.isNotEmpty) h.speaker,
                    if (h.workTitle.isNotEmpty) h.workTitle,
                    if (h.place.isNotEmpty) h.place,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('app.search.on_the_server_only_sync_to'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
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
    await _afterOpen(result);
  }

  Future<void> _openPerson(PersonGroup p) async {
    final kind = switch (p.role) {
      'character' => ChipKind.character,
      'author' => ChipKind.author,
      _ => ChipKind.speaker,
    };
    await openPersonPage(
      context,
      chip: QuoteChip(kind, p.name),
      onFilter: (f) {
        final field = p.role == 'character' ? 'character' : p.role;
        _addFacet(SearchFacet(field, f.name), replaceText: '');
      },
    );
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- pieces ----

  Future<void> _pickFilter() async {
    final field = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in SearchFacet.fields.entries)
              if (_vocab.of(e.key).isNotEmpty)
                ListTile(
                  title: Text(context.tr(e.value)),
                  trailing: Text('${_vocab.of(e.key).length}'),
                  onTap: () => Navigator.of(context).pop(e.key),
                ),
          ],
        ),
      ),
    );
    if (field == null || !mounted) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ValuePicker(
        title: context.tr(SearchFacet.fields[field] ?? field),
        values: _vocab.of(field),
      ),
    );
    if (value != null) _addFacet(SearchFacet(field, value));
  }

  /// Suggestions under the box: values of a field being typed (`tag:li`), or names and tags from the library that
  /// the words so far could be.
  List<SearchFacet> get _suggestions {
    final t = _text.text;
    final m = RegExp(r'(\w+):(\S*)$').firstMatch(t);
    if (m != null) {
      final f = switch (m.group(1)!.toLowerCase()) {
        'color' => 'colour',
        final x => x,
      };
      if (SearchFacet.fields.containsKey(f)) {
        final part = m.group(2)!.toLowerCase();
        return [
          for (final v in _vocab.of(f))
            if (part.isEmpty || v.toLowerCase().contains(part))
              SearchFacet(f, v),
        ].take(8).toList();
      }
    }
    return [
      for (final s in _vocab.suggest(parseQuery(t).words))
        if (!_facets.contains(s)) s,
    ];
  }

  void _useSuggestion(SearchFacet f) {
    final t = _text.text;
    final m = RegExp(r'(\w+):(\S*)$').firstMatch(t);
    final replaced =
        m != null &&
            SearchFacet.fields.containsKey(
              m.group(1)!.toLowerCase() == 'color'
                  ? 'colour'
                  : m.group(1)!.toLowerCase(),
            )
        ? t.substring(0, m.start).trimRight()
        : '';
    _addFacet(f, replaceText: replaced);
  }

  Widget _banner(BuildContext context, SearchResults? r) {
    final theme = Theme.of(context);
    final server = _server?.available == true;
    final IconData icon;
    final String text;
    if (r != null && r.fellBack) {
      icon = Icons.cloud_off_outlined;
      text = context.tr('app.search.the_server_could_not_be_reached');
    } else if (server) {
      icon = Icons.cloud_done_outlined;
      text = context.tr('app.search.searching_your_server_forgives_typos');
    } else {
      icon = Icons.smartphone_outlined;
      text = context.tr('app.search.searching_this_phone_exact_words_pair');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _results;
    final suggestions = _suggestions;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _text,
          focusNode: _focus,
          autofocus: widget.initial.isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _changed(),
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: context.tr(
              'app.search.search_words_names_tags_and_titles',
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_text.text.isNotEmpty)
            IconButton(
              tooltip: context.tr('common.selection.shelf.clear.label'),
              icon: const Icon(Icons.close),
              onPressed: () {
                _text.clear();
                _changed();
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _banner(context, r),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _facets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(context.tr(f.label)),
                      onDeleted: () => _removeFacet(f),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(context.tr('app.search.filter')),
                    onPressed: _vocab.byField.isEmpty ? null : _pickFilter,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in SearchScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(context.tr(s.label)),
                      selected: _scope == s,
                      onSelected: (_) {
                        setState(() => _scope = s);
                        _run();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.add,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(context.tr(s.label)),
                        onPressed: () => _useSuggestion(s),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _body(context, r)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SearchResults? r) {
    if (r == null) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: context.tr('app.search.search_your_library'),
        hint: context.tr('app.search.words_from_a_quote_a_title'),
      );
    }
    if (r.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: context.tr('app.search.nothing_matches'),
        hint: context.tr('app.search.try_fewer_words_or_take_a'),
      );
    }
    final words = queryWords(
      r.corrected.isNotEmpty ? r.corrected : _query.words,
    );
    final theme = Theme.of(context);
    final out = <Widget>[];

    if (r.corrected.isNotEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: context.tr('app.search.showing_results_for')),
                TextSpan(
                  text: r.corrected,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    void heading(String title, int n) => out.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Text('$n', style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );

    if (r.works.isNotEmpty) {
      heading(context.tr('movies.group.none.label'), r.works.length);
      for (final w in r.works) {
        out.add(_workTile(context, w, words));
      }
    }
    if (r.people.isNotEmpty) {
      heading(context.tr('common.field.people.label'), r.people.length);
      for (final p in r.people) {
        out.add(_personTile(context, p));
      }
    }
    if (r.characters.isNotEmpty) {
      heading(
        context.tr('stats.breakdown.characters.label'),
        r.characters.length,
      );
      for (final c in r.characters) {
        out.add(_personTile(context, c));
      }
    }
    if (r.tags.isNotEmpty) {
      heading(context.tr('common.field.tags.label'), r.tags.length);
      for (final t in r.tags) {
        out.add(
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: Text(context.tr('app.search.name', {'name': t.name})),
            subtitle: Text(
              context.tr('common.work-card.count.quote.other', {'n': t.count}),
            ),
            trailing: const Icon(Icons.filter_alt_outlined),
            onTap: () => _addFacet(SearchFacet('tag', t.name), replaceText: ''),
          ),
        );
      }
    }
    if (r.genres.isNotEmpty) {
      heading(context.tr('common.field.genres.label'), r.genres.length);
      for (final g in r.genres) {
        out.add(
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(g.name),
            subtitle: Text(
              context.tr('app.search.n_titles', {'n': g.works.length}),
            ),
            trailing: const Icon(Icons.filter_alt_outlined),
            onTap: () =>
                _addFacet(SearchFacet('genre', g.name), replaceText: ''),
          ),
        );
      }
    }
    if (r.notes.isNotEmpty) {
      heading(context.tr('vocab.font-role.hand.label'), r.notes.length);
      for (final q in r.notes) {
        out.add(_quoteTile(context, q, words, showNote: true));
      }
    }
    if (r.quotes.isNotEmpty) {
      heading(context.tr('nav.tab.quotes.label'), r.quotes.length);
      for (final q in r.quotes) {
        out.add(_quoteTile(context, q, words));
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: out,
    );
  }

  Widget _workTile(BuildContext context, WorkHit h, List<String> words) {
    final theme = Theme.of(context);
    final work = Work(
      id: h.localId ?? 0,
      kind: h.screen ? WorkKind.film : WorkKind.book,
      title: h.title,
      creator: h.creator,
      year: h.year,
      language: '',
      createdAt: DateTime.utc(2000),
      updatedAt: DateTime.utc(2000),
      cover: h.cover,
    );
    final meta = [
      if (h.creator.isNotEmpty) h.creator,
      if (h.year != null) '${h.year}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          onTap: () => _openWork(h),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                WorkCover(
                  work: work,
                  width: 42,
                  height: 60,
                  fallback: MonogramCover(work: work, width: 42, height: 60),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        marked(
                          h.title,
                          words,
                          theme.textTheme.titleSmall!,
                          theme.colorScheme.primaryContainer,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                FaceStack(
                  names: creditNames(h.creator),
                  kind: h.screen ? ChipKind.speaker : ChipKind.author,
                  ringColor:
                      theme.cardTheme.color ??
                      theme.colorScheme.surfaceContainerLow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personTile(BuildContext context, PersonGroup p) {
    final theme = Theme.of(context);
    final what = switch (p.role) {
      'author' => context.tr('common.field.author.label'),
      'director' => context.tr('common.field.director.label'),
      'actor' => context.tr('common.field.actor.label'),
      'character' => context.tr('common.field.character.label'),
      _ => context.tr('app.search.said_by'),
    };
    final n = p.works.length + p.quotes.length;
    return ListTile(
      leading: PersonFace.any(
        anyName: p.name,
        radius: 20,
        fallback: CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text(
            p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
        ),
      ),
      title: Text(p.name),
      subtitle: Text(
        p.works.isNotEmpty
            ? '$what · ${context.tr('app.search.n_titles', {'n': p.works.length})}'
            : '$what · ${context.tr('common.work-card.count.quote.other', {'n': n})}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openPerson(p),
    );
  }

  Widget _quoteTile(
    BuildContext context,
    QuoteHit q,
    List<String> words, {
    bool showNote = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = [
      if (q.speaker.isNotEmpty) q.speaker,
      if (q.workTitle.isNotEmpty) q.workTitle,
      if (q.place.isNotEmpty) q.place,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: InkWell(
          onTap: () => _openQuote(q),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: quoteColour(q.color),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        marked(
                          showNote && q.note.isNotEmpty ? q.note : q.text,
                          words,
                          quoteStyle(context, size: 16),
                          scheme.primaryContainer,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showNote && q.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          q.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (q.translation.isNotEmpty && !showNote) ...[
                        const SizedBox(height: 4),
                        Text.rich(
                          marked(
                            q.translation,
                            words,
                            theme.textTheme.bodySmall!.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            scheme.primaryContainer,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (from.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          from,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FaceStack(
                  names: [...creditNames(q.speaker), ...creditNames(q.credit)],
                  kind: q.kind == QuoteHitKind.line
                      ? ChipKind.speaker
                      : ChipKind.author,
                  radius: 11,
                  ringColor:
                      theme.cardTheme.color ?? scheme.surfaceContainerLow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text] with the places [words] occur drawn in [style] on a background of [mark]. Matching ignores case.
TextSpan marked(String text, List<String> words, TextStyle style, Color mark) {
  if (words.isEmpty || text.isEmpty) return TextSpan(text: text, style: style);
  final lower = text.toLowerCase();
  // the spans of the text any word covers, merged
  final spans = <(int, int)>[];
  for (final w in words) {
    var from = 0;
    while (true) {
      final i = lower.indexOf(w, from);
      if (i < 0) break;
      spans.add((i, i + w.length));
      from = i + w.length;
    }
  }
  if (spans.isEmpty) return TextSpan(text: text, style: style);
  spans.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final s in spans) {
    if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, s.$2 > last.$2 ? s.$2 : last.$2));
    } else {
      merged.add(s);
    }
  }
  final out = <TextSpan>[];
  var at = 0;
  for (final m in merged) {
    if (m.$1 > at) out.add(TextSpan(text: text.substring(at, m.$1)));
    out.add(
      TextSpan(
        text: text.substring(m.$1, m.$2),
        style: TextStyle(backgroundColor: mark, fontWeight: FontWeight.w700),
      ),
    );
    at = m.$2;
  }
  if (at < text.length) out.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: out);
}

/// A sheet that lists [values], with a box to narrow them. Pops the one pressed.
class _ValuePicker extends StatefulWidget {
  const _ValuePicker({required this.title, required this.values});
  final String title;
  final List<String> values;

  @override
  State<_ValuePicker> createState() => _ValuePickerState();
}

class _ValuePickerState extends State<_ValuePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final v in widget.values)
        if (_q.isEmpty || v.toLowerCase().contains(_q.toLowerCase())) v,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    labelText: widget.title,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final v in shown)
                      ListTile(
                        title: Text(v),
                        onTap: () => Navigator.of(context).pop(v),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
