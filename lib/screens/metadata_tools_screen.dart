import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../metadata/metadata_service.dart';
import '../people/picture.dart';
import '../l10n/l10n.dart';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// What a field of a work is called in words.
String fieldName(String f) =>
    {
      'title': 'Title',
      'author': 'Author',
      'director': 'Director',
      'translator': 'Translator',
      'editor': 'Editor',
      'isbn': 'ISBN',
      'description': 'Synopsis',
      'published_year': 'Year',
      'release_year': 'Year',
      'genres': 'Genres',
      'series': 'Series',
      'series_index': tx('app.metadata_tools.place_in_the_series'),
      'cover': 'Cover',
      'poster': 'Poster',
      'cast': 'Cast',
      'links': 'Links',
      'portrait': 'Portrait',
      'bio': 'About',
      'born': 'Born',
      'died': 'Died',
      'identity': tx('app.metadata_tools.source_link'),
      'language': 'Language',
      'publisher': 'Publisher',
      'pages': 'Pages',
    }[f] ??
    f.replaceAll('_', ' ');

/// A field's value in words: a list joined, nothing as "(empty)", a list of records as a count.
String valueText(Object? v) {
  if (v == null) return '(empty)';
  if (v is String) return v.trim().isEmpty ? '(empty)' : v.trim();
  if (v is num) return v == 0 ? '(empty)' : '$v';
  if (v is List) {
    if (v.isEmpty) return '(empty)';
    if (v.every((x) => x is String || x is num)) return v.join(', ');
    return '${v.length} entries';
  }
  return '$v';
}

bool _isEmpty(Object? v) => valueText(v) == '(empty)';

/// Looking after the library's details: the works that still lack something (a cover, an author, a year, a
/// synopsis) with the server's checks against the web for their changes to approve, and the works saved twice, to
/// merge. The server can also fill every work's gaps by itself, and an admin can ask it to fetch covers.
class MetadataToolsScreen extends StatefulWidget {
  const MetadataToolsScreen({
    super.key,
    required this.service,
    this.admin = false,
    this.onChanged,
  });

  final MetadataService service;

  /// An admin account may ask for covers to be fetched.
  final bool admin;

  /// Called after the server's copy of a work changed, so the phone can pull it.
  final VoidCallback? onChanged;

  @override
  State<MetadataToolsScreen> createState() => _MetadataToolsScreenState();
}

class _MetadataToolsScreenState extends State<MetadataToolsScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  List<GapWork>? _works;
  List<List<DuplicateWork>>? _dups;
  String? _problem;
  String _gap = '';
  String _query = '';
  final _picked = <String>{};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _key(GapWork w) => '${w.kind}:${w.id}';

  Future<void> _read() async {
    try {
      final w = await widget.service.works();
      final d = await widget.service.duplicates();
      if (mounted) {
        setState(() {
          _works = w;
          _dups = d;
          _problem = null;
          _picked.removeWhere((k) => !w.any((x) => _key(x) == k));
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _job(Future<void> Function() start, String said) async {
    try {
      await start();
      if (mounted) _say(context, said);
    } on ServerException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  Future<void> _check(List<GapWork> works) async {
    if (works.isEmpty) return;
    setState(() => _checking = true);
    List<ReverifyItem> items;
    try {
      items = await widget.service.check(works);
    } on ServerException catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        _say(context, e.message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _checking = false);
    final withChanges = [
      for (final i in items)
        if (i.checked && i.diffs.isNotEmpty) i,
    ];
    final upToDate = items.where((i) => i.checked && i.diffs.isEmpty).length;
    final unpinned = items.where((i) => i.status == 'unpinned').length;
    final failed = items
        .where((i) => i.status != 'ok' && i.status != 'unpinned')
        .length;
    final summary = [
      if (upToDate > 0)
        context.tr('app.metadata_tools.n_up_to_date', {'n': upToDate}),
      if (unpinned > 0) trn('app.metadata_tools.no_id', unpinned),
      if (failed > 0)
        context.tr('app.metadata_tools.n_unreachable', {'n': failed}),
    ].join(', ');
    if (withChanges.isEmpty) {
      _say(
        context,
        summary.isEmpty
            ? context.tr('app.metadata_tools.the_web_had_nothing_new')
            : context.tr('app.metadata_tools.nothing_to_change_summary', {
                'summary': summary,
              }),
      );
      return;
    }
    final applied = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ReverifyReviewScreen(
          service: widget.service,
          items: withChanges,
          note: summary,
        ),
      ),
    );
    if (applied != null && applied > 0) {
      widget.onChanged?.call();
      await _read();
    }
  }

  Future<void> _merge(List<DuplicateWork> group) async {
    var keep = group.reduce((a, b) => b.quotes > a.quotes ? b : a).id;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(context.tr('app.bulk_bar.merge_into_one')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'app.metadata_tools.quotes_tags_and_credits_move_to',
                ),
              ),
              RadioGroup<int>(
                groupValue: keep,
                onChanged: (v) => set(() => keep = v ?? keep),
                child: Column(
                  children: [
                    for (final w in group)
                      RadioListTile<int>(
                        value: w.id,
                        title: Text(w.title),
                        subtitle: Text(
                          [
                            if (w.creator.isNotEmpty) w.creator,
                            if (w.year > 0) '${w.year}',
                            countWords('quote', w.quotes),
                            if (w.hasCover)
                              tx('app.metadata_tools.has_a_cover'),
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('common.action.cancel.label')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('staging.move.merge.button.label')),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final book = group.first.kind != 'movie';
    try {
      await widget.service.merge(
        book: book,
        into: keep,
        from: [
          for (final w in group)
            if (w.id != keep) w.id,
        ],
      );
      widget.onChanged?.call();
      await _read();
    } on ServerException catch (e) {
      if (mounted) _say(context, e.message);
    }
  }

  List<GapWork> _shown() {
    final all = _works ?? const [];
    final q = _query.toLowerCase();
    return [
      for (final w in all)
        if (w.gaps.isNotEmpty &&
            (_gap.isEmpty || w.gaps.contains(_gap)) &&
            (q.isEmpty ||
                w.title.toLowerCase().contains(q) ||
                w.creator.toLowerCase().contains(q)))
          w,
    ];
  }

  Widget _worksTab() {
    final all = _works!;
    final shown = _shown();
    final gaps = {for (final w in all) ...w.gaps}.toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (gaps.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                for (final g in gaps)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        context.tr('app.metadata_tools.no_g_n', {
                          'g': g,
                          'n': all.where((w) => w.gaps.contains(g)).length,
                        }),
                      ),
                      selected: _gap == g,
                      onSelected: (v) => setState(() => _gap = v ? g : ''),
                    ),
                  ),
              ],
            ),
          ),
        if (_checking) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _read,
            child: shown.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(48),
                        child: Text(
                          all.every((w) => w.gaps.isEmpty)
                              ? context.tr(
                                  'app.metadata_tools.every_work_has_all_its_details',
                                )
                              : context.tr(
                                  'app.metadata_tools.no_work_matches',
                                ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final w in shown)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Card(
                            color: _picked.contains(_key(w))
                                ? scheme.secondaryContainer
                                : null,
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: StoredPicture(
                                  name: w.cover,
                                  width: 40,
                                  height: 56,
                                  fallback: Container(
                                    width: 40,
                                    height: 56,
                                    color: scheme.surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      w.isBook
                                          ? Icons.menu_book_outlined
                                          : Icons.movie_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(w.title),
                              isThreeLine: true,
                              subtitle: Text(
                                [
                                  if (w.creator.isNotEmpty) w.creator,
                                  context.tr('app.metadata_tools.missing_x_x2', {
                                    'x': w.gaps.join(', '),
                                    'x2': w.lowRes
                                        ? ' · ${context.tr('app.metadata_tools.small_cover')}'
                                        : '',
                                  }),
                                ].join('\n'),
                              ),
                              selected: _picked.contains(_key(w)),
                              onTap: () {
                                if (_picked.isNotEmpty) {
                                  setState(
                                    () => _picked.contains(_key(w))
                                        ? _picked.remove(_key(w))
                                        : _picked.add(_key(w)),
                                  );
                                } else {
                                  _check([w]);
                                }
                              },
                              onLongPress: () =>
                                  setState(() => _picked.add(_key(w))),
                              trailing: _picked.isNotEmpty
                                  ? null
                                  : const Icon(Icons.travel_explore_rounded),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _dupsTab() {
    final groups = _dups!;
    if (groups.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(48),
            child: Text(
              context.tr('app.metadata_tools.no_work_looks_saved_twice'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _read,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final w in g)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            [
                              w.title,
                              if (w.creator.isNotEmpty) w.creator,
                              if (w.year > 0) '${w.year}',
                              countWords('quote', w.quotes),
                            ].join(' · '),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: () => _merge(g),
                          child: Text(
                            context.tr('app.metadata_tools.merge_n', {
                              'n': g.length,
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final works = _works;
    final selecting = _picked.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: context.tr('app.metadata_tools.clear_the_choice'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_picked.clear),
              )
            : null,
        title: Text(
          selecting
              ? '${_picked.length} chosen'
              : context.tr('app.settings.details_and_duplicates'),
        ),
        actions: [
          if (selecting)
            TextButton.icon(
              onPressed: _checking
                  ? null
                  : () {
                      final chosen = [
                        for (final w in works ?? const <GapWork>[])
                          if (_picked.contains(_key(w))) w,
                      ];
                      setState(_picked.clear);
                      _check(chosen);
                    },
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(context.tr('app.metadata_tools.re_check')),
            )
          else
            PopupMenuButton<String>(
              tooltip: context.tr('settings.appearance.contrast.more.label'),
              onSelected: (v) {
                if (v == 'fill') {
                  _job(
                    widget.service.fillAll,
                    'The server is filling in what it can. You can follow it in Jobs (admins).',
                  );
                } else if (v == 'covers') {
                  _job(
                    widget.service.fetchCovers,
                    context.tr(
                      'app.metadata_tools.the_server_is_fetching_the_missing',
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'fill',
                  child: Text(
                    context.tr('app.metadata_tools.fill_every_work_s_gaps'),
                  ),
                ),
                if (widget.admin)
                  PopupMenuItem(
                    value: 'covers',
                    child: Text(
                      context.tr('app.metadata_tools.fetch_missing_covers'),
                    ),
                  ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48 + 56),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  hintText: context.tr(
                    'app.metadata_tools.search_titles_and_creators',
                  ),
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(
                    text: works == null
                        ? 'Gaps'
                        : context.tr('app.metadata_tools.gaps_n', {
                            'n': works.where((w) => w.gaps.isNotEmpty).length,
                          }),
                  ),
                  Tab(
                    text: _dups == null
                        ? 'Twice'
                        : context.tr('app.metadata_tools.saved_twice_n', {
                            'n': _dups!.length,
                          }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _problem != null && works == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _read,
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : works == null || _dups == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [_worksTab(), _dupsTab()]),
    );
  }
}

/// The changes a check found, for the reader to accept or leave: each field with what is stored and what the web
/// says, a choice of which supplier where several answered, and what is left alone if it changed meanwhile.
/// Pops with how many works were written.
class ReverifyReviewScreen extends StatefulWidget {
  const ReverifyReviewScreen({
    super.key,
    required this.service,
    required this.items,
    this.note = '',
  });

  final MetadataService service;
  final List<ReverifyItem> items;
  final String note;

  @override
  State<ReverifyReviewScreen> createState() => _ReverifyReviewScreenState();
}

class _ReverifyReviewScreenState extends State<ReverifyReviewScreen> {
  /// 'type:id:field' -> ticked
  final _on = <String, bool>{};

  /// 'type:id:field' -> the index of the supplier chosen (0 is the preferred)
  final _alt = <String, int>{};
  bool _saving = false;

  String _k(ReverifyItem i, FieldDiff d) => '${i.type}:${i.id}:${d.field}';

  @override
  void initState() {
    super.initState();
    for (final i in widget.items) {
      for (final d in i.diffs) {
        // fill what is empty by default; replacing something the reader has is theirs to tick
        _on[_k(i, d)] = _isEmpty(d.stored) && d.field != 'identity';
      }
    }
  }

  ({Object? value, String source}) _pick(ReverifyItem i, FieldDiff d) {
    final n = _alt[_k(i, d)] ?? 0;
    if (d.alts.isNotEmpty && n < d.alts.length) {
      return (value: d.alts[n].value, source: d.alts[n].source);
    }
    return (value: d.fresh, source: d.source.isEmpty ? i.source : d.source);
  }

  int get _count => _on.values.where((v) => v).length;

  Future<void> _apply() async {
    final out = <ApplyItem>[];
    for (final i in widget.items) {
      final set = <String, Object?>{};
      final sources = <String, String>{};
      final expect = <String, Object?>{};
      for (final d in i.diffs) {
        if (_on[_k(i, d)] != true) continue;
        final p = _pick(i, d);
        set[d.field] = p.value;
        if (p.source.isNotEmpty) sources[d.field] = p.source;
        expect[d.field] = d.stored;
      }
      if (set.isNotEmpty) {
        out.add(
          ApplyItem(
            type: i.type,
            id: i.id,
            set: set,
            sources: sources,
            expect: expect,
          ),
        );
      }
    }
    if (out.isEmpty) return;
    setState(() => _saving = true);
    try {
      final results = await widget.service.apply(out);
      if (!mounted) return;
      final ok = results.where((r) => r.ok).length;
      final bad = results.where((r) => !r.ok).toList();
      final notes = results.where((r) => r.note.isNotEmpty).toList();
      _say(
        context,
        [
          '$ok ${ok == 1 ? 'work' : 'works'} updated.',
          if (bad.isNotEmpty) '${bad.length} could not be: ${bad.first.error}',
          if (notes.isNotEmpty) notes.first.note,
        ].join(' '),
      );
      Navigator.of(context).pop(ok);
    } on ServerException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _say(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.metadata_tools.what_the_web_says')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (widget.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(widget.note, style: theme.textTheme.bodySmall),
            ),
          for (final i in widget.items) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                i.title.isEmpty ? context.tr('add.mode.work.label') : i.title,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final d in i.diffs)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Card(
                  child: CheckboxListTile(
                    value: _on[_k(i, d)] ?? false,
                    onChanged: (v) =>
                        setState(() => _on[_k(i, d)] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(fieldName(d.field)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('app.checks_tabs.now_x', {
                            'x': valueText(d.stored),
                          }),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          context.tr('app.metadata_tools.web_x', {
                            'x': valueText(_pick(i, d).value),
                          }),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.alts.length > 1)
                          Wrap(
                            spacing: 6,
                            children: [
                              for (var n = 0; n < d.alts.length; n++)
                                ChoiceChip(
                                  label: Text(d.alts[n].source),
                                  selected: (_alt[_k(i, d)] ?? 0) == n,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) =>
                                      setState(() => _alt[_k(i, d)] = n),
                                ),
                            ],
                          )
                        else if (_pick(i, d).source.isNotEmpty)
                          Text(
                            context.tr('app.metadata_tools.from_source', {
                              'source': _pick(i, d).source,
                            }),
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'apply-checks',
        onPressed: _count == 0 || _saving ? null : _apply,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.check_rounded),
        label: Text(_count == 0 ? 'Nothing ticked' : 'Apply $_count'),
      ),
    );
  }
}
