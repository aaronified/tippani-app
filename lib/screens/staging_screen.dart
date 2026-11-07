import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../imports/import_service.dart';
import '../library/models.dart';
import 'library_widgets.dart';
import 'quote_form_screen.dart' show quoteColour;

String _kindWord(String kind) => switch (kind) {
  'book' => 'book',
  'movie' => 'film',
  'show' => 'show',
  'game' => 'game',
  _ => 'title',
};

/// What importing from [source] is called.
String sourceName(String source) {
  final k = source.replaceAll('_', '-');
  for (final s in importSources) {
    if (s.kind == k ||
        s.kind == '$k-html' ||
        s.kind.replaceAll('-html', '') == k) {
      return s.title;
    }
  }
  return switch (source) {
    'kindle_clippings' => 'My Clippings',
    'readest_json' => 'Readest',
    'kindle_notebook' => 'Kindle notebook',
    'imdb' => 'IMDb quotes',
    _ => source.isEmpty ? 'Import' : source.replaceAll('_', ' '),
  };
}

/// The server's queue of imported quotes, waiting for the reader to say yes: look them over, fix where each came
/// from, move a group onto the right book or film, then approve or discard. Nothing imported reaches the library
/// until it is approved here.
class StagingScreen extends StatefulWidget {
  const StagingScreen({
    super.key,
    required this.service,
    this.onApproved,
    this.onChanged,
  });

  final ImportService service;

  /// Called after quotes were added to the library on the server, so the phone can pull them.
  final Future<void> Function()? onApproved;

  /// Called after the queue changed (its size is the argument).
  final ValueChanged<int>? onChanged;

  @override
  State<StagingScreen> createState() => _StagingScreenState();
}

class _StagingScreenState extends State<StagingScreen> {
  static const _page = 300;

  Staging _staging = Staging.empty;
  final _quotes = <StagedQuote>[];
  bool _loading = true;
  String? _problem;
  int _batch = 0;
  final _picked = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!more) setState(() => _loading = true);
    try {
      final s = await widget.service.staged(
        batchId: _batch,
        limit: _page,
        offset: more ? _quotes.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _staging = s;
        if (!more) _quotes.clear();
        _quotes.addAll(s.quotes);
        _picked.removeWhere((id) => !_quotes.any((q) => q.id == id));
        _loading = false;
        _problem = null;
      });
      widget.onChanged?.call(s.pending);
    } on ServerException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _problem = e.message;
        });
      }
    }
  }

  void _say(String m) {
    final s = ScaffoldMessenger.of(context);
    s.clearSnackBars();
    s.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on ServerException catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes == true;
  }

  StagedSelector get _selection => _picked.isNotEmpty
      ? StagedSelector.quotes(_picked.toList())
      : _batch > 0
      ? StagedSelector.batch(_batch)
      : const StagedSelector.everything();

  Future<void> _approve(StagedSelector sel) async {
    final progress = ValueNotifier<(int, int)>((0, 0));
    ApprovalOutcome? out;
    // a dialog that cannot be dismissed while the server works
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Approving'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
                const SizedBox(height: 12),
                Text(
                  p.$2 == 0
                      ? 'Waiting for the server…'
                      : 'Done ${p.$1} of ${p.$2}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    String? error;
    try {
      out = await widget.service.approve(
        sel,
        onProgress: (d, t) => progress.value = (d, t),
      );
    } on ServerException catch (e) {
      error = e.message;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    if (error != null || out == null || !out.ok) {
      _say(error ?? out?.message ?? 'The server could not add those quotes.');
      await _load();
      return;
    }
    final parts = [
      if (out.added > 0) '${out.added} added',
      if (out.enriched > 0) '${out.enriched} enriched',
      if (out.relinked > 0)
        '${out.relinked} matched to a quote you already have',
      if (out.skipped > 0) '${out.skipped} skipped',
    ];
    _say(parts.isEmpty ? 'Approved.' : parts.join(' · '));
    _picked.clear();
    await _load();
    await widget.onApproved?.call();
  }

  Future<void> _discard(StagedSelector sel, int n) async {
    if (!await _confirm(
      n == 1 ? 'Discard this quote?' : 'Discard $n quotes?',
      'They leave the queue without ever entering your library.',
      'Discard',
    )) {
      return;
    }
    await _run(() async {
      final gone = await widget.service.discard(sel);
      _picked.clear();
      if (mounted) _say('Discarded $gone');
      await _load();
    });
  }

  Future<void> _edit(StagedSelector sel, StagedEdit change, String said) =>
      _run(() async {
        final n = await widget.service.edit(sel, change);
        if (mounted) _say('$said ($n)');
        await _load();
      });

  Future<void> _move(StagedSelector sel) async {
    final others = [
      for (final w in _staging.works)
        if (!_quotes
            .where((q) => _picked.contains(q.id))
            .any((q) => q.workId == w.id))
          w,
    ];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MoveSheet(service: widget.service, groups: others),
    );
    if (choice == null) return;
    await _run(() async {
      if (choice is WorkChoice) {
        await widget.service.move(sel, onto: choice);
      } else if (choice is StagedWork) {
        await widget.service.move(sel, mergeInto: choice.id);
      }
      _picked.clear();
      if (mounted) _say('Moved');
      await _load();
    });
  }

  Future<void> _editQuote(StagedQuote q) async {
    final r = await showModalBottomSheet<StagedEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _QuoteSheet(quote: q),
    );
    if (r != null) await _edit(StagedSelector.quotes([q.id]), r, 'Saved');
  }

  Future<void> _bulkFields(StagedSelector sel, int n) async {
    final r = await showModalBottomSheet<StagedEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FieldsSheet(count: n),
    );
    if (r != null) await _edit(sel, r, 'Edited');
  }

  Future<void> _shift(StagedSelector sel, int n) async {
    final r = await showModalBottomSheet<StagedEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ShiftSheet(count: n),
    );
    if (r != null) await _edit(sel, r, 'Shifted');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = _staging.pending;
    final batches = _staging.batches;
    final groups = <StagedWork>[
      for (final w in _staging.works)
        if (_batch == 0 || w.batchId == _batch) w,
    ];
    final byWork = <int, List<StagedQuote>>{};
    for (final q in _quotes) {
      (byWork[q.workId] ??= []).add(q);
    }
    final hasSelection = _picked.isNotEmpty;
    final shown = _quotes.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending import'),
        actions: [
          if (pending > 0)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'approve') {
                  await _approve(
                    _batch > 0
                        ? StagedSelector.batch(_batch)
                        : const StagedSelector.everything(),
                  );
                } else if (v == 'discard') {
                  await _discard(
                    _batch > 0
                        ? StagedSelector.batch(_batch)
                        : const StagedSelector.everything(),
                    _batch > 0
                        ? batches.firstWhere((b) => b.id == _batch).quotes
                        : pending,
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'approve',
                  child: Text(
                    _batch > 0 ? 'Approve this file' : 'Approve all $pending',
                  ),
                ),
                PopupMenuItem(
                  value: 'discard',
                  child: Text(_batch > 0 ? 'Discard this file' : 'Discard all'),
                ),
              ],
            ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : pending == 0 && groups.isEmpty
          ? const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing waiting.',
              hint: 'An import lands here first and stays until you say yes to it.',
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, hasSelection ? 96 : 32),
              children: [
                if (batches.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('All files ($pending)'),
                            selected: _batch == 0,
                            onSelected: (_) {
                              _batch = 0;
                              _picked.clear();
                              _load();
                            },
                          ),
                        ),
                        for (final b in batches)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                '${b.filename.isEmpty ? sourceName(b.source) : b.filename} · ${b.quotes}',
                              ),
                              selected: _batch == b.id,
                              onSelected: (_) {
                                _batch = b.id;
                                _picked.clear();
                                _load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    pending == 1
                        ? '1 quote waiting'
                        : '$pending quotes waiting',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final w in groups)
                  _GroupCard(
                    work: w,
                    quotes: byWork[w.id] ?? const [],
                    picked: _picked,
                    onToggle: (id) => setState(
                      () => _picked.contains(id)
                          ? _picked.remove(id)
                          : _picked.add(id),
                    ),
                    onToggleGroup: (on) => setState(() {
                      final ids = (byWork[w.id] ?? const []).map((q) => q.id);
                      on ? _picked.addAll(ids) : _picked.removeAll(ids);
                    }),
                    onTapQuote: _editQuote,
                    onApprove: () => _approve(StagedSelector.works([w.id])),
                    onDiscard: () =>
                        _discard(StagedSelector.works([w.id]), w.quotes),
                    onMove: () {
                      _picked
                        ..clear()
                        ..addAll((byWork[w.id] ?? const []).map((q) => q.id));
                      _move(StagedSelector.works([w.id]));
                    },
                  ),
                if (shown < _staging.total)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: () => _load(more: true),
                      child: Text('Show more ($shown of ${_staging.total})'),
                    ),
                  ),
              ],
            ),
      bottomSheet: hasSelection
          ? _SelectionBar(
              count: _picked.length,
              onClear: () => setState(_picked.clear),
              onApprove: () => _approve(_selection),
              onDiscard: () => _discard(_selection, _picked.length),
              onColour: (c) =>
                  _edit(_selection, StagedEdit(color: c), 'Colour changed'),
              onFavourite: (on) => _edit(
                _selection,
                StagedEdit(favorite: on),
                on ? 'Favourited' : 'Un-favourited',
              ),
              onFields: () => _bulkFields(_selection, _picked.length),
              onShift: () => _shift(_selection, _picked.length),
              onMove: () => _move(_selection),
            )
          : null,
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.work,
    required this.quotes,
    required this.picked,
    required this.onToggle,
    required this.onToggleGroup,
    required this.onTapQuote,
    required this.onApprove,
    required this.onDiscard,
    required this.onMove,
  });

  final StagedWork work;
  final List<StagedQuote> quotes;
  final Set<int> picked;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onToggleGroup;
  final ValueChanged<StagedQuote> onTapQuote;
  final VoidCallback onApprove, onDiscard, onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final standalone = work.standalone || work.title.isEmpty;
    final allPicked =
        quotes.isNotEmpty && quotes.every((q) => picked.contains(q.id));
    final destination = standalone
        ? 'Will be saved as quotes of their own, from no book or film'
        : work.targetId > 0
        ? 'Joins your ${work.targetTitle}${work.targetYear > 0 ? ' (${work.targetYear})' : ''}'
        : 'Will be added as a new ${_kindWord(work.kind)}';
    final who = [
      if (work.author.isNotEmpty) work.author,
      if (work.year > 0) '${work.year}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: allPicked,
                  onChanged: quotes.isEmpty
                      ? null
                      : (v) => onToggleGroup(v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          standalone ? 'Quotes of their own' : work.title,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (who.isNotEmpty)
                          Text(
                            who,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          destination,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        if (work.ambiguous)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'You have more than one title with this name. Check it joined the right one.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                        if (work.pinned)
                          Text(
                            'You chose this destination',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'This group',
                  onSelected: (v) => switch (v) {
                    'approve' => onApprove(),
                    'discard' => onDiscard(),
                    _ => onMove(),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'approve',
                      child: Text('Approve this group'),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      child: Text('Move to another work…'),
                    ),
                    PopupMenuItem(
                      value: 'discard',
                      child: Text('Discard this group'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                standalone
                    ? 'No quotes left in this group.'
                    : 'No quotes. Approving adds the ${_kindWord(work.kind)} itself.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final q in quotes)
            _QuoteRow(
              quote: q,
              selected: picked.contains(q.id),
              onToggle: () => onToggle(q.id),
              onTap: () => onTapQuote(q),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    required this.quote,
    required this.selected,
    required this.onToggle,
    required this.onTap,
  });

  final StagedQuote quote;
  final bool selected;
  final VoidCallback onToggle, onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final where = [
      if (quote.chapter.isNotEmpty) quote.chapter,
      if (quote.location.isNotEmpty) quote.location,
      if (quote.timestamp.isNotEmpty) quote.timestamp,
      if (quote.character.isNotEmpty) quote.character,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: quoteColour(quote.color), width: 4),
          ),
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.5)
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (quote.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Note: ${quote.note}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (quote.translation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          quote.translation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    if (where.isNotEmpty || quote.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (where.isNotEmpty) where,
                            if (quote.tags.isNotEmpty)
                              quote.tags.map((t) => '#$t').join(' '),
                          ].join('   '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (quote.favorite)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Icon(Icons.favorite, size: 16, color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onApprove,
    required this.onDiscard,
    required this.onColour,
    required this.onFavourite,
    required this.onFields,
    required this.onShift,
    required this.onMove,
  });

  final int count;
  final VoidCallback onClear, onApprove, onDiscard, onFields, onShift, onMove;
  final ValueChanged<String> onColour;
  final ValueChanged<bool> onFavourite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Clear the selection',
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  ),
                  Expanded(
                    child: Text(
                      '$count selected',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: onDiscard,
                    child: const Text('Discard'),
                  ),
                  FilledButton(
                    onPressed: onApprove,
                    child: Text('Approve $count'),
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in quoteColors)
                      IconButton(
                        tooltip: 'Make it $c',
                        icon: CircleAvatar(
                          radius: 9,
                          backgroundColor: quoteColour(c),
                        ),
                        onPressed: () => onColour(c),
                      ),
                    IconButton(
                      tooltip: 'Favourite',
                      icon: const Icon(Icons.favorite_border),
                      onPressed: () => onFavourite(true),
                    ),
                    IconButton(
                      tooltip: 'Remove the favourite mark',
                      icon: const Icon(Icons.heart_broken_outlined),
                      onPressed: () => onFavourite(false),
                    ),
                    TextButton.icon(
                      onPressed: onFields,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit fields'),
                    ),
                    TextButton.icon(
                      onPressed: onShift,
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('Locations'),
                    ),
                    TextButton.icon(
                      onPressed: onMove,
                      icon: const Icon(Icons.drive_file_move_outlined),
                      label: const Text('Move to…'),
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

/// A sheet's frame: scrolls and rides above the keyboard.
Widget _sheet(BuildContext context, String title, List<Widget> children) =>
    Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );

/// Edits one staged quote's colour, favourite mark and where it came from. The words are not editable here (a
/// staged row records what the file said); fix wording after approving.
class _QuoteSheet extends StatefulWidget {
  const _QuoteSheet({required this.quote});
  final StagedQuote quote;

  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  late String _color = widget.quote.color;
  late bool _fav = widget.quote.favorite;
  late final _chapter = TextEditingController(text: widget.quote.chapter);
  late final _location = TextEditingController(text: widget.quote.location);
  late final _character = TextEditingController(text: widget.quote.character);
  late final _actor = TextEditingController(text: widget.quote.actor);
  late final _timestamp = TextEditingController(text: widget.quote.timestamp);

  @override
  void dispose() {
    for (final c in [_chapter, _location, _character, _actor, _timestamp]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    Widget field(String label, TextEditingController c, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
    return _sheet(context, 'Edit staged quote', [
      Text(
        '“${q.text}”',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Text(
        'A staged quote keeps both kinds of location. Approval uses the one its destination needs.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final c in quoteColors)
            ChoiceChip(
              label: const SizedBox(width: 4),
              avatar: CircleAvatar(radius: 9, backgroundColor: quoteColour(c)),
              tooltip: c,
              selected: _color == c,
              onSelected: (_) => setState(() => _color = c),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Favourite'),
        value: _fav,
        onChanged: (v) => setState(() => _fav = v),
      ),
      field('Chapter', _chapter, 'optional'),
      field('Location', _location, 'p.142'),
      field('Character', _character, 'Philip Marlowe'),
      field('Actor', _actor, 'Elliott Gould'),
      field('Timestamp', _timestamp, '01:02:03'),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () {
            String? ch(String old, TextEditingController c) =>
                c.text.trim() == old ? null : c.text.trim();
            Navigator.of(context).pop(
              StagedEdit(
                color: _color == q.color ? null : _color,
                favorite: _fav == q.favorite ? null : _fav,
                chapter: ch(q.chapter, _chapter),
                location: ch(q.location, _location),
                character: ch(q.character, _character),
                actor: ch(q.actor, _actor),
                timestamp: ch(q.timestamp, _timestamp),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ),
    ]);
  }
}

/// Sets fields and tags on every selected quote. A field left alone is not touched; a field emptied is cleared.
class _FieldsSheet extends StatefulWidget {
  const _FieldsSheet({required this.count});
  final int count;

  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
  final _touched = <String>{};
  final _c = {
    for (final k in ['chapter', 'location', 'character', 'actor', 'timestamp'])
      k: TextEditingController(),
  };
  final _add = TextEditingController();
  final _remove = TextEditingController();

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _add.dispose();
    _remove.dispose();
    super.dispose();
  }

  List<String> _tags(TextEditingController c) => [
    for (final t in c.text.split(','))
      if (t.trim().isNotEmpty) t.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    String? v(String k) => _touched.contains(k) ? _c[k]!.text.trim() : null;
    return _sheet(context, 'Edit ${widget.count} selected', [
      Text(
        'Only the boxes you type in change. Empty a box you have touched to clear that field.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (final e in _c.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: e.value,
            onChanged: (_) => _touched.add(e.key),
            decoration: InputDecoration(
              labelText: '${e.key[0].toUpperCase()}${e.key.substring(1)}',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _add,
          decoration: const InputDecoration(
            labelText: 'Add tags',
            helperText: 'Separate with commas',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _remove,
          decoration: const InputDecoration(
            labelText: 'Remove tags',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(
            StagedEdit(
              chapter: v('chapter'),
              location: v('location'),
              character: v('character'),
              actor: v('actor'),
              timestamp: v('timestamp'),
              addTags: _tags(_add),
              removeTags: _tags(_remove),
            ),
          ),
          child: Text('Apply to ${widget.count}'),
        ),
      ),
    ]);
  }
}

/// Shifts the page numbers or timestamps of the selected quotes, for a file whose locations are off by a fixed
/// amount.
class _ShiftSheet extends StatefulWidget {
  const _ShiftSheet({required this.count});
  final int count;

  @override
  State<_ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends State<_ShiftSheet> {
  String _field = 'location';
  String _op = 'subtract';
  final _by = TextEditingController();

  @override
  void dispose() {
    _by.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsNumber = const {
      'add',
      'subtract',
      'multiply',
      'divide',
    }.contains(_op);
    final number = double.tryParse(_by.text.trim());
    final ready =
        _op == 'reset' ||
        (needsNumber ? number != null : _by.text.trim().isNotEmpty);
    return _sheet(context, 'Shift locations on ${widget.count} selected', [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'location', label: Text('Page / location')),
          ButtonSegment(value: 'timestamp', label: Text('Timestamp')),
        ],
        selected: {_field},
        onSelectionChanged: (s) => setState(() => _field = s.single),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final o in const [
            'add',
            'subtract',
            'multiply',
            'divide',
            'set',
            'reset',
          ])
            ChoiceChip(
              label: Text(switch (o) {
                'set' => 'set to',
                _ => o,
              }),
              selected: _op == o,
              onSelected: (_) => setState(() => _op = o),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (_op != 'reset')
        TextField(
          controller: _by,
          onChanged: (_) => setState(() {}),
          keyboardType: needsNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: needsNumber ? 'By' : 'To',
            hintText: needsNumber ? '5' : 'p.1',
            border: const OutlineInputBorder(),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'Only the numbers in the text change: p.142 minus 5 is p.137, and a range like 610-612 moves at both ends. Timestamps shift in seconds. Reset puts back what the file said.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: !ready
              ? null
              : () => Navigator.of(context).pop(
                  StagedEdit(
                    shiftField: _field,
                    shiftOp: _op,
                    shiftValue: needsNumber ? number : null,
                    shiftText: _op == 'set' ? _by.text.trim() : null,
                  ),
                ),
          child: const Text('Apply'),
        ),
      ),
    ]);
  }
}

/// Picks where staged quotes should go: a book or film already in the library, or another group in the queue.
class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.service, required this.groups});
  final ImportService service;
  final List<StagedWork> groups;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  List<WorkChoice>? _all;
  String? _problem;
  String _q = '';

  @override
  void initState() {
    super.initState();
    widget.service.destinations().then(
      (v) {
        if (mounted) setState(() => _all = v);
      },
      onError: (Object e) {
        if (mounted) {
          setState(
            () => _problem = e is ServerException
                ? e.message
                : 'Could not read your library.',
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final needle = _q.trim().toLowerCase();
    final shown = all == null
        ? const <WorkChoice>[]
        : [
            for (final w in all)
              if (needle.isEmpty ||
                  w.title.toLowerCase().contains(needle) ||
                  w.creator.toLowerCase().contains(needle))
                w,
          ].take(60).toList();
    return _sheet(context, 'Move to…', [
      TextField(
        onChanged: (v) => setState(() => _q = v),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Find a book or film in your library',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      if (_problem != null) Text(_problem!),
      if (all == null && _problem == null)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      for (final w in shown)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            w.kind == 'book' ? Icons.menu_book_outlined : Icons.movie_outlined,
          ),
          title: Text(w.title),
          subtitle: Text(
            [
              if (w.creator.isNotEmpty) w.creator,
              if (w.year > 0) '${w.year}',
            ].join(' · '),
          ),
          onTap: () => Navigator.of(context).pop(w),
        ),
      if (widget.groups.isNotEmpty) ...[
        const Divider(),
        Text(
          'Or merge into another group in this queue',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        for (final g in widget.groups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.merge_type),
            title: Text(g.title.isEmpty ? 'Quotes of their own' : g.title),
            subtitle: Text('${g.quotes} quotes'),
            onTap: () => Navigator.of(context).pop(g),
          ),
      ],
    ]);
  }
}
