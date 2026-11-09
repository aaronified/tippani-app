import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../api/server_call.dart';
import '../harness/harness.dart' show BackupPicker;
import '../library/library_store.dart';
import '../library/models.dart' show quoteColors;
import '../tags/tag_ops.dart';
import '../tags/tag_service.dart';
import 'filtered_quotes_screen.dart';
import 'library_widgets.dart';
import 'quote_form_screen.dart' show quoteColour;
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

class _Row {
  _Row(this.name, this.local, this.server);
  String name;
  final int local;
  final ServerTag? server;

  int get count => local > 0 ? local : (server?.quotes ?? 0);
}

enum _Sort { name, used }

/// Every tag: its colour, how many quotes wear it, and the ways to change it: rename, colour and style, merge
/// several into one, delete. A change is made on the server first (where the tag's colour and style live) and then
/// on every quote on the phone, so the next sync finds both sides alike. With no server in reach the phone's quotes
/// are still changed, and the screen says the server was not.
class TagsScreen extends StatefulWidget {
  const TagsScreen({
    super.key,
    required this.store,
    required this.picker,
    this.service,
    this.anthologies,
  });

  final LibraryStore store;
  final BackupPicker picker;

  /// The server's tags; null (or not available) leaves out colours and styles.
  final TagService? service;
  final AnthologyService? anthologies;

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  List<_Row>? _rows;
  String? _note;
  _Sort _sort = _Sort.name;
  String _query = '';
  final _picked = <String>{};
  bool _busy = false;

  TagService? get _svc {
    final s = widget.service;
    return s != null && s.available ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final local = await localTagCounts(widget.store);
    List<ServerTag> server = const [];
    String? note;
    final svc = _svc;
    if (svc != null) {
      try {
        server = await svc.list();
      } on ServerException catch (e) {
        note = '${e.message} Colours and styles are on the server.';
      }
    }
    final byFold = <String, _Row>{};
    final serverBy = {for (final t in server) foldTag(t.name): t};
    for (final e in local.entries) {
      byFold[foldTag(e.key)] = _Row(e.key, e.value, serverBy[foldTag(e.key)]);
    }
    for (final t in server) {
      byFold.putIfAbsent(foldTag(t.name), () => _Row(t.name, 0, t));
    }
    if (!mounted) return;
    setState(() {
      _rows = byFold.values.toList();
      _note = note;
      _picked.removeWhere((n) => !byFold.containsKey(foldTag(n)));
    });
  }

  List<_Row> get _shown {
    final q = foldTag(_query);
    final rows = [
      for (final r in _rows ?? const <_Row>[])
        if (q.isEmpty || foldTag(r.name).contains(q)) r,
    ];
    rows.sort(
      (a, b) => _sort == _Sort.used && a.count != b.count
          ? b.count.compareTo(a.count)
          : foldTag(a.name).compareTo(foldTag(b.name)),
    );
    return rows;
  }

  void _say(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// Runs [server] against the server (when there is one), then [local] on the phone. Returns what to tell the
  /// reader when the server could not be asked, or null.
  Future<String?> _both(
    Future<void> Function(TagService svc)? server,
    Future<int> Function() local,
  ) async {
    setState(() => _busy = true);
    String? failed;
    try {
      final svc = _svc;
      if (svc != null && server != null) {
        try {
          await server(svc);
        } on ServerException catch (e) {
          failed = e.message;
        }
      }
      await local();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    return failed;
  }

  Future<String?> _ask(
    String title, {
    String initial = '',
    String action = 'Save',
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          textCapitalization: TextCapitalization.none,
          controller: c,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(
            labelText: context.tr('app.tags.tag_name'),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(c.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(_Row r) async {
    final got = (await _ask(
      'Rename #${r.name}',
      initial: r.name,
    ))?.trim().replaceAll(RegExp(r'^#+'), '').trim();
    if (got == null || got.isEmpty || got == r.name) return;
    final into = _rows!
        .where((o) => o != r && foldTag(o.name) == foldTag(got))
        .firstOrNull;
    final failed = await _both((svc) async {
      final mine = r.server;
      if (mine == null) return;
      final other = into?.server;
      if (other != null) {
        await svc.merge(other, [mine]);
      } else {
        await svc.save(mine, name: got);
      }
    }, () => renameTagLocal(widget.store, r.name, into?.name ?? got));
    _say(
      failed == null
          ? (into == null ? 'Renamed to #$got.' : 'Merged into #${into.name}.')
          : '$failed Changed on this phone only.',
    );
  }

  Future<void> _look(_Row r) async {
    final t = r.server;
    final svc = _svc;
    if (t == null || svc == null) return;
    var colour = t.color;
    var style = t.style;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('app.search.name', {'name': r.name}),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('common.field.colour.label'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final c in quoteColors)
                      Semantics(
                        button: true,
                        selected: c == colour,
                        label: c,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setSheet(() => colour = c),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: quoteColour(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: c == colour ? 3 : 1,
                                color: c == colour
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('common.field.style.label'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in tagStyles)
                      ChoiceChip(
                        label: Text(s),
                        selected: s == style,
                        onSelected: (_) => setSheet(() => style = s),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(context.tr('common.action.save.label')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await svc.save(t, color: colour, style: style);
    } on ServerException catch (e) {
      _say(e.message);
    }
    await _load();
  }

  Future<void> _delete(List<_Row> rows) async {
    final n = rows.fold<int>(0, (a, r) => a + r.count);
    final what = rows.length == 1
        ? '#${rows.single.name}'
        : '${rows.length} tags';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.tags.delete_what', {'what': what})),
        content: Text(
          n == 0
              ? context.tr('app.tags.no_quote_wears_it')
              : 'It comes off $n ${n == 1 ? 'quote' : 'quotes'}. The quotes stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.delete.label')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    String? failed;
    for (final r in rows) {
      final f = await _both((svc) async {
        final t = r.server;
        if (t != null) await svc.delete(t);
      }, () => deleteTagLocal(widget.store, r.name));
      failed ??= f;
    }
    _picked.clear();
    _say(failed == null ? 'Deleted.' : '$failed Changed on this phone only.');
  }

  Future<void> _merge(List<_Row> rows) async {
    var keep = rows.first;
    final chosen = await showDialog<_Row>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(context.tr('app.tags.merge_into_which_tag')),
          content: RadioGroup<_Row>(
            groupValue: keep,
            onChanged: (v) => setDialog(() => keep = v ?? keep),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in rows)
                  RadioListTile<_Row>(
                    value: r,
                    title: Text(
                      context.tr('app.search.name', {'name': r.name}),
                    ),
                    subtitle: Text(_count(r.count)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('common.action.cancel.label')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(keep),
              child: Text(context.tr('staging.move.merge.button.label')),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final drops = [
      for (final r in rows)
        if (r != chosen) r,
    ];
    final failed = await _both(
      (svc) async {
        final k = chosen.server;
        final d = [
          for (final r in drops)
            if (r.server != null) r.server!,
        ];
        if (k != null && d.isNotEmpty) await svc.merge(k, d);
      },
      () => mergeTagsLocal(widget.store, chosen.name, [
        for (final r in drops) r.name,
      ]),
    );
    _picked.clear();
    _say(
      failed == null
          ? 'Merged into #${chosen.name}.'
          : '$failed Changed on this phone only.',
    );
  }

  Future<void> _create() async {
    final svc = _svc;
    if (svc == null) return;
    final got = (await _ask(
      context.tr('tags.new.title'),
      action: context.tr('common.action.add.label'),
    ))?.trim().replaceAll(RegExp(r'^#+'), '').trim();
    if (got == null || got.isEmpty) return;
    try {
      await svc.create(got);
    } on ServerException catch (e) {
      _say(e.message);
    }
    await _load();
  }

  String _count(int n) => n == 1 ? '1 quote' : '$n quotes';

  void _open(_Row r) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => FilteredQuotesScreen(
        store: widget.store,
        picker: widget.picker,
        title: context.tr('app.search.name', {'name': r.name}),
        tag: r.name,
        anthologies: widget.anthologies,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = _rows;
    final selecting = _picked.isNotEmpty;
    final picked = [
      for (final r in rows ?? const <_Row>[])
        if (_picked.contains(foldTag(r.name))) r,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          selecting
              ? '${picked.length} selected'
              : context.tr('common.field.tags.label'),
        ),
        leading: selecting
            ? IconButton(
                tooltip: context.tr('app.tags.clear_selection'),
                icon: const Icon(Ti.x),
                onPressed: () => setState(_picked.clear),
              )
            : null,
        actions: [
          if (selecting) ...[
            IconButton(
              tooltip: context.tr('staging.move.merge.button.label'),
              icon: const Icon(Ti.arrowsJoin),
              onPressed: picked.length < 2 || _busy
                  ? null
                  : () => _merge(picked),
            ),
            IconButton(
              tooltip: context.tr('common.action.delete.label'),
              icon: const Icon(Ti.trash),
              onPressed: _busy ? null : () => _delete(picked),
            ),
          ] else
            PopupMenuButton<_Sort>(
              tooltip: context.tr('common.filters.sort.aria'),
              icon: const Icon(Ti.arrowsSort),
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _Sort.name,
                  child: Text(context.tr('app.tags.by_name')),
                ),
                PopupMenuItem(
                  value: _Sort.used,
                  child: Text(context.tr('app.tags.most_used')),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: _svc == null || selecting
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-tag',
              onPressed: _create,
              icon: const Icon(Ti.plus),
              label: Text(context.tr('tags.new.title')),
            ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? EmptyState(
              icon: Ti.tag,
              title: context.tr('app.library.no_tags_yet'),
              hint: context.tr('app.tags.tag_a_quote_and_it_appears'),
            )
          : Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Ti.search),
                      hintText: context.tr('app.tags.find_a_tag'),
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final r in _shown) _tile(context, r, selecting),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(BuildContext context, _Row r, bool selecting) {
    final scheme = Theme.of(context).colorScheme;
    final on = _picked.contains(foldTag(r.name));
    final colour = r.server == null
        ? scheme.outlineVariant
        : quoteColour(r.server!.color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: on ? scheme.secondaryContainer : null,
        child: ListTile(
          leading: selecting
              ? Checkbox(value: on, onChanged: (_) => _toggle(r))
              : Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                  ),
                ),
          title: Text(context.tr('app.search.name', {'name': r.name})),
          subtitle: Text(
            [
              _count(r.count),
              if (r.server != null) r.server!.style,
            ].join(' · '),
          ),
          onTap: selecting ? () => _toggle(r) : () => _open(r),
          onLongPress: () => _toggle(r),
          trailing: selecting
              ? null
              : PopupMenuButton<String>(
                  tooltip: context.tr('app.tags.tag_actions'),
                  onSelected: (a) => switch (a) {
                    'rename' => _rename(r),
                    'look' => _look(r),
                    'select' => _toggle(r),
                    _ => _delete([r]),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(context.tr('app.tags.rename')),
                    ),
                    if (r.server != null && _svc != null)
                      PopupMenuItem(
                        value: 'look',
                        child: Text(context.tr('app.tags.colour_and_style')),
                      ),
                    PopupMenuItem(
                      value: 'select',
                      child: Text(context.tr('app.tags.select_to_merge')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.tr('common.action.delete.label')),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _toggle(_Row r) => setState(() {
    final k = foldTag(r.name);
    if (!_picked.remove(k)) _picked.add(k);
  });
}
