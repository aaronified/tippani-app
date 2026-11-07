import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../checks/checks_service.dart';
import 'library_widgets.dart';
import '../l10n/l10n.dart';

/// Reads something from the server and draws it, with the same loading, failure and retry for every tab.
class _Loader<T> extends StatefulWidget {
  const _Loader({
    super.key,
    required this.load,
    required this.builder,
    this.unavailable,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;
  final Widget? unavailable;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  T? _data;
  String? _problem;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _problem = null;
          _loading = false;
        });
      }
    } on ServerException catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.builder(context, _data as T, _reload);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _problem ?? context.tr('app.checks_tabs.something_went_wrong'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() => _loading = true);
                _reload();
              },
              child: Text(context.tr('common.source.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// [text] with the first [mark] drawn highlighted.
Widget markedText(
  BuildContext context,
  String text,
  String mark, {
  TextStyle? style,
  int? maxLines,
}) {
  final scheme = Theme.of(context).colorScheme;
  final base = style ?? Theme.of(context).textTheme.bodyMedium;
  final i = mark.isEmpty ? -1 : text.indexOf(mark);
  if (i < 0) {
    return Text(
      text,
      style: base,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
  return Text.rich(
    TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, i)),
        TextSpan(
          text: mark,
          style: TextStyle(
            backgroundColor: scheme.tertiaryContainer,
            color: scheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: text.substring(i + mark.length)),
      ],
    ),
    maxLines: maxLines,
    overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
  );
}

/// A snippet the server marked with « and » around the match: drawn with the match highlighted and the marks gone.
Widget guillemetText(BuildContext context, String snippet, {int maxLines = 4}) {
  final a = snippet.indexOf('«');
  final b = snippet.indexOf('»', a + 1);
  if (a < 0 || b < 0) {
    return Text(snippet, maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
  final scheme = Theme.of(context).colorScheme;
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: snippet.substring(0, a)),
        TextSpan(
          text: snippet.substring(a + 1, b).isEmpty
              ? '␣'
              : snippet.substring(a + 1, b),
          style: TextStyle(
            backgroundColor: scheme.tertiaryContainer,
            color: scheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: snippet.substring(b + 1)),
      ],
    ),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );
}

void _say(BuildContext context, String m) {
  if (m.isEmpty) return;
  final s = ScaffoldMessenger.of(context);
  s.clearSnackBars();
  s.showSnackBar(SnackBar(content: Text(m)));
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String action,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('common.action.cancel.label')),
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

const _batchMax = 500;

List<List<T>> _chunks<T>(List<T> all, int n) => [
  for (var i = 0; i < all.length; i += n)
    all.sublist(i, i + n > all.length ? all.length : i + n),
];

String _kindLabel(String kind) => switch (kind) {
  'book' => 'Book quote',
  'screen' => 'Film or show quote',
  _ => 'Quote on its own',
};

// ============================================================ stray marks

/// Quotes that carry something that came from the page and not the writer (a footnote number, a soft hyphen, a
/// doubled space): see each, fix it where the fix is safe, or say it is meant.
class StrayMarksTab extends StatefulWidget {
  const StrayMarksTab({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final ChecksService service;
  final Future<void> Function() onChanged;

  @override
  State<StrayMarksTab> createState() => _StrayMarksTabState();
}

class _StrayMarksTabState extends State<StrayMarksTab> {
  bool _ignored = false;
  String _rule = 'all';
  final _picked = <String>{};
  bool _busy = false;
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.service.available) return const _NeedsServer();
    return _Loader<CleanupScan>(
      key: ValueKey('$_ignored-$_nonce'),
      load: () => widget.service.cleanup(ignored: _ignored),
      builder: (context, scan, reload) => _body(context, scan, () async {
        setState(() => _nonce++);
      }),
    );
  }

  Widget _body(
    BuildContext context,
    CleanupScan scan,
    Future<void> Function() reload,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hits = <String, int>{};
    for (final it in scan.items) {
      for (final f in it.findings) {
        hits[f.rule] = (hits[f.rule] ?? 0) + 1;
      }
    }
    final chips = [
      for (final r in scan.rules)
        if (hits.containsKey(r)) r,
    ];
    final rule = chips.contains(_rule) ? _rule : 'all';
    final items = [
      for (final it in scan.items)
        if (rule == 'all' || it.findings.any((f) => f.rule == rule)) it,
    ];
    final targets = <CleanupTarget>[
      for (final it in items)
        for (final f in it.findings)
          if (rule == 'all' || f.rule == rule) CleanupTarget(it, f),
    ];
    final groups = <String, List<CleanupItem>>{};
    for (final it in items) {
      final key = it.kind == 'quote' ? 'quote' : '${it.kind}:${it.workId}';
      (groups[key] ??= []).add(it);
    }

    Future<void> answer(
      List<CleanupTarget> ts, {
      required bool fix,
      bool? ignore,
    }) async {
      setState(() => _busy = true);
      try {
        var applied = 0, stale = 0, dup = 0;
        for (final part in _chunks(ts, _batchMax)) {
          if (fix) {
            final r = await widget.service.cleanupAccept(part);
            applied += r.applied;
            stale += r.stale;
            dup += r.duplicates;
          } else {
            await widget.service.cleanupIgnore(part, ignore: ignore!);
          }
        }
        if (!mounted) return;
        _picked.clear();
        _say(
          this.context,
          fix
              ? ChangeResult(
                  applied: applied,
                  stale: stale,
                  duplicates: dup,
                ).words
              : ignore!
              ? 'Ignored ${ts.length}'
              : 'Restored ${ts.length}',
        );
        setState(() => _nonce++);
        if (fix) await widget.onChanged();
      } on ServerException catch (e) {
        if (mounted) _say(this.context, e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    final fixable = [
      for (final t in targets)
        if (t.finding.fixable && !t.finding.ignored) t,
    ];
    final chosen = [
      for (final t in targets)
        if (_picked.contains(t.key)) t,
    ];

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, chosen.isEmpty ? 32 : 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(
                          context.tr('app.checks_tabs.to_look_at_open', {
                            'open': scan.open,
                          }),
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(
                          context.tr('app.checks_tabs.ignored_ignored', {
                            'ignored': scan.ignored,
                          }),
                        ),
                      ),
                    ],
                    selected: {_ignored},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _ignored = s.single;
                      _picked.clear();
                      _rule = 'all';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('app.checks_tabs.quotes_can_carry_things_that_came'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (scan.truncated)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr('app.checks_tabs.your_library_is_large_so_only'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (chips.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          context.tr('app.checks_tabs.all_x', {
                            'x': hits.values.fold<int>(0, (a, b) => a + b),
                          }),
                        ),
                        selected: rule == 'all',
                        onSelected: (_) => setState(() => _rule = 'all'),
                      ),
                    ),
                    for (final r in chips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${cleanupRuleWords[r]?.$1 ?? r} (${hits[r]})',
                          ),
                          selected: rule == r,
                          onSelected: (_) => setState(() => _rule = r),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (!_ignored && fixable.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                              context,
                              'Fix all ${fixable.length}?',
                              context.tr(
                                'app.checks_tabs.each_is_rewritten_as_shown_the',
                              ),
                              context.tr('app.checks_tabs.fix_all'),
                            )) {
                              await answer(fixable, fix: true);
                            }
                          },
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      context.tr('app.checks_tabs.fix_all_n', {
                        'n': fixable.length,
                      }),
                    ),
                  ),
                ),
              ),
            if (items.isEmpty)
              SizedBox(
                height: 360,
                child: EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: _ignored
                      ? context.tr('app.checks_tabs.nothing_ignored')
                      : context.tr('app.checks_tabs.no_stray_marks'),
                  hint: _ignored
                      ? context.tr(
                          'app.checks_tabs.marks_you_say_are_meant_stay',
                        )
                      : context.tr(
                          'app.checks_tabs.nothing_in_your_quotes_looks_like',
                        ),
                ),
              ),
            for (final g in groups.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(
                  g.first.kind == 'quote'
                      ? context.tr('app.checks_tabs.quotes_on_their_own')
                      : g.first.workTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final it in g)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindLabel(it.kind),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        for (final f in it.findings)
                          if (rule == 'all' || f.rule == rule)
                            _FindingRow(
                              item: it,
                              finding: f,
                              selected: _picked.contains(
                                CleanupTarget(it, f).key,
                              ),
                              busy: _busy,
                              onSelect: (on) => setState(() {
                                final k = CleanupTarget(it, f).key;
                                on ? _picked.add(k) : _picked.remove(k);
                              }),
                              onFix: () =>
                                  answer([CleanupTarget(it, f)], fix: true),
                              onIgnore: (ig) => answer(
                                [CleanupTarget(it, f)],
                                fix: false,
                                ignore: ig,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
        if (chosen.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              color: scheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: context.tr('common.selection.clear.aria'),
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_picked.clear),
                      ),
                      Expanded(
                        child: Text(
                          context.tr('common.selection.count.one', {
                            'n': chosen.length,
                          }),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  answer(chosen, fix: false, ignore: !_ignored),
                        child: Text(_ignored ? 'Restore' : 'Ignore'),
                      ),
                      if (!_ignored)
                        FilledButton(
                          onPressed:
                              _busy || chosen.every((t) => !t.finding.fixable)
                              ? null
                              : () => answer([
                                  for (final t in chosen)
                                    if (t.finding.fixable) t,
                                ], fix: true),
                          child: Text(context.tr('app.checks_tabs.fix')),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.item,
    required this.finding,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onFix,
    required this.onIgnore,
  });

  final CleanupItem item;
  final CleanupFinding finding;
  final bool selected, busy;
  final ValueChanged<bool> onSelect;
  final VoidCallback onFix;
  final ValueChanged<bool> onIgnore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final words = cleanupRuleWords[finding.rule];
    final field = finding.field.isEmpty
        ? ''
        : '${finding.field[0].toUpperCase()}${finding.field.substring(1)}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => onSelect(v ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('app.checks_tabs.rule_fieldx', {
                    'rule': words?.$1 ?? finding.rule,
                    'field': field,
                    'x': finding.count > 1 ? ' · ${finding.count} places' : '',
                  }),
                  style: theme.textTheme.labelLarge,
                ),
                if (words != null)
                  Text(
                    words.$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                guillemetText(context, finding.snippet),
                if (finding.afterSnippet.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: guillemetText(context, finding.afterSnippet),
                      ),
                    ],
                  ),
                ],
                Row(
                  children: [
                    if (finding.fixable && !finding.ignored)
                      TextButton(
                        onPressed: busy ? null : onFix,
                        child: Text(context.tr('app.checks_tabs.fix')),
                      ),
                    TextButton(
                      onPressed: busy ? null : () => onIgnore(!finding.ignored),
                      child: Text(finding.ignored ? 'Restore' : 'Ignore'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ corrections

/// Quotes whose words differ from the file the server holds for their work, grouped by how they differ.
class CorrectionsTab extends StatefulWidget {
  const CorrectionsTab({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final ChecksService service;
  final Future<void> Function() onChanged;

  @override
  State<CorrectionsTab> createState() => _CorrectionsTabState();
}

class _CorrectionsTabState extends State<CorrectionsTab> {
  String _bucket = 'all';
  bool _busy = false;
  int _nonce = 0;

  Future<void> _answer(
    List<Correction> items, {
    required bool accept,
    String? bucket,
    bool bulk = false,
  }) async {
    setState(() => _busy = true);
    try {
      var applied = 0, stale = 0, skipped = 0, edited = 0, dup = 0;
      for (final part in _chunks(items, 5000)) {
        if (accept) {
          final r = await widget.service.correctionsAccept(
            bucket ?? part.first.bucket,
            part,
            bulk: bulk,
          );
          applied += r.applied;
          stale += r.stale;
          skipped += r.skipped;
          edited += r.skippedEdited;
          dup += r.duplicates;
        } else {
          await widget.service.correctionsIgnore(part);
        }
      }
      if (!mounted) return;
      _say(
        context,
        accept
            ? ChangeResult(
                applied: applied,
                stale: stale,
                skipped: skipped,
                skippedEdited: edited,
                duplicates: dup,
              ).words
            : 'Ignored ${items.length}',
      );
      setState(() => _nonce++);
      if (accept) await widget.onChanged();
    } on ServerException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.available) return const _NeedsServer();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Loader<CorrectionsScan>(
      key: ValueKey(_nonce),
      load: widget.service.corrections,
      builder: (context, scan, reload) {
        if (scan.proposals.isEmpty && scan.wrongFile.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt_rounded,
            title: context.tr('app.checks_tabs.nothing_differs'),
            hint: context.tr('app.checks_tabs.where_a_quote_differs_from_the'),
          );
        }
        final byBucket = <String, List<Correction>>{};
        for (final p in scan.proposals) {
          (byBucket[p.bucket] ??= []).add(p);
        }
        final order = [
          for (final b in correctionBuckets.keys)
            if (byBucket.containsKey(b)) b,
          for (final b in byBucket.keys)
            if (!correctionBuckets.containsKey(b)) b,
        ];
        final bucket = order.contains(_bucket) ? _bucket : 'all';
        final shown = bucket == 'all' ? order : [bucket];
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  context.tr('app.checks_tabs.a_work_s_attached_file_knows'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                for (final w in scan.wrongFile)
                  Card(
                    color: scheme.errorContainer,
                    margin: const EdgeInsets.only(top: 12),
                    child: ListTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer,
                      ),
                      title: Text(
                        context.tr(
                          'app.checks_tabs.work_title_differing_of_total_quotes',
                          {
                            'work_title': w.workTitle,
                            'differing': w.differing,
                            'total': w.total,
                          },
                        ),
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                      subtitle: Text(
                        context.tr(
                          'app.checks_tabs.the_attached_file_is_probably_not',
                        ),
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ),
                if (order.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              context.tr('app.checks_tabs.all_n', {
                                'n': scan.proposals.length,
                              }),
                            ),
                            selected: bucket == 'all',
                            onSelected: (_) => setState(() => _bucket = 'all'),
                          ),
                        ),
                        for (final b in order)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                '${correctionBuckets[b]?.$1 ?? b} (${byBucket[b]!.length})',
                              ),
                              selected: bucket == b,
                              onSelected: (_) => setState(() => _bucket = b),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                for (final b in shown) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            correctionBuckets[b]?.$1 ?? b,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final rows = byBucket[b]!;
                                  final edited = rows
                                      .where((r) => r.edited)
                                      .length;
                                  if (await _confirm(
                                    context,
                                    'Accept all ${rows.length}?',
                                    '${correctionBuckets[b]?.$2 ?? ''}\n\nEach quote takes the file’s words.${edited > 0 ? ' $edited you edited yourself are left alone.' : ''}',
                                    context.tr('app.checks_tabs.accept_all'),
                                  )) {
                                    await _answer(
                                      rows,
                                      accept: true,
                                      bucket: b,
                                      bulk: true,
                                    );
                                  }
                                },
                          child: Text(
                            context.tr('found.accept.all', {
                              'n': byBucket[b]!.length,
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text(
                      correctionBuckets[b]?.$2 ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final p in byBucket[b]!)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.workTitle.isNotEmpty)
                              Text(
                                p.workTitle,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('corrections.yours'),
                              style: theme.textTheme.labelSmall,
                            ),
                            markedText(context, p.quote, p.from, maxLines: 6),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('app.checks_tabs.the_file_s'),
                              style: theme.textTheme.labelSmall,
                            ),
                            markedText(context, p.proposed, p.to, maxLines: 6),
                            if (p.edited)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  context.tr(
                                    'app.checks_tabs.you_edited_this_quote_yourself',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _answer([p], accept: false),
                                  child: Text(
                                    context.tr('cleanup.ignore.label'),
                                  ),
                                ),
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _answer([p], accept: true),
                                  child: Text(
                                    context.tr(
                                      'app.checks_tabs.use_the_file_s',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================ times and places

/// The times a film or show's subtitle file proposes for its lines, and the chapters and places a book's file
/// proposes for its highlights.
class LocatorsTab extends StatefulWidget {
  const LocatorsTab({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final ChecksService service;
  final Future<void> Function() onChanged;

  @override
  State<LocatorsTab> createState() => _LocatorsTabState();
}

class _LocatorsTabState extends State<LocatorsTab> {
  bool _busy = false;
  int _nonce = 0;

  Future<void> _answer(
    List<LocatorProposal> items, {
    required bool accept,
    String bucket = 'exact',
  }) async {
    setState(() => _busy = true);
    try {
      var applied = 0, stale = 0, skipped = 0;
      for (final part in _chunks(items, 5000)) {
        if (accept) {
          final r = await widget.service.locatorsAccept(bucket, part);
          applied += r.applied;
          stale += r.stale;
          skipped += r.skipped;
        } else {
          await widget.service.locatorsIgnore(part);
        }
      }
      if (!mounted) return;
      _say(
        context,
        accept
            ? ChangeResult(
                applied: applied,
                stale: stale,
                skipped: skipped,
              ).words
            : 'Ignored ${items.length}',
      );
      setState(() => _nonce++);
      if (accept) await widget.onChanged();
    } on ServerException catch (e) {
      if (mounted) _say(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _where(LocatorProposal p, {required bool proposed}) {
    final v = proposed ? p.proposed : p.current;
    final end = proposed ? p.proposedEnd : p.currentEnd;
    final chapter = proposed ? p.proposedChapter : p.currentChapter;
    final text = [
      if (chapter.isNotEmpty) chapter,
      if (v.isNotEmpty) end.isNotEmpty ? '$v – $end' : v,
    ].join(' · ');
    return text.isEmpty ? (p.isBook ? 'no location' : 'no time') : text;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.available) return const _NeedsServer();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Loader<List<LocatorProposal>>(
      key: ValueKey(_nonce),
      load: widget.service.locators,
      builder: (context, all, reload) {
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt_rounded,
            title: context.tr('app.checks_tabs.nothing_proposed'),
            hint: context.tr(
              'app.checks_tabs.a_subtitle_file_knows_when_each_2',
            ),
          );
        }
        final exact = [
          for (final p in all)
            if (p.bucket == 'exact') p,
        ];
        final review = [
          for (final p in all)
            if (p.bucket != 'exact') p,
        ];
        Widget section(
          String title,
          String note,
          List<LocatorProposal> rows,
          String bucket,
        ) {
          if (rows.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(
                                context,
                                'Accept all ${rows.length}?',
                                context.tr(
                                  'app.checks_tabs.each_quote_takes_the_file_s',
                                ),
                                context.tr('app.checks_tabs.accept_all'),
                              )) {
                                await _answer(
                                  rows,
                                  accept: true,
                                  bucket: bucket,
                                );
                              }
                            },
                      child: Text(
                        context.tr('found.accept.all', {'n': rows.length}),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final p in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            p.workTitle,
                            if (p.season > 0 || p.episode > 0)
                              'S${p.season}·E${p.episode}',
                          ].where((s) => s.isNotEmpty).join('  '),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.quote,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.tr('app.checks_tabs.now_x', {
                                  'x': _where(p, proposed: false),
                                }),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const Icon(Icons.arrow_forward, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('app.checks_tabs.file_says_x', {
                                  'x': _where(p, proposed: true),
                                }),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (p.evidence.isNotEmpty && p.bucket != 'exact')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              context.tr('app.checks_tabs.evidence', {
                                'evidence': p.evidence,
                              }),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _answer([p], accept: false),
                              child: Text(context.tr('cleanup.ignore.label')),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _answer(
                                      [p],
                                      accept: true,
                                      bucket: bucket,
                                    ),
                              child: Text(
                                p.isBook
                                    ? context.tr(
                                        'app.checks_tabs.use_this_place',
                                      )
                                    : context.tr('locators.accept.tip'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  context.tr('app.checks_tabs.a_subtitle_file_knows_when_each'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                section(
                  'Exact matches (${exact.length})',
                  context.tr('locators.exact.note'),
                  exact,
                  'exact',
                ),
                section(
                  'Worth a look (${review.length})',
                  'A near match: the file’s words differ a little from yours.',
                  review,
                  'review',
                ),
              ],
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        );
      },
    );
  }
}

class _NeedsServer extends StatelessWidget {
  const _NeedsServer();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    title: context.tr('app.checks_tabs.this_needs_your_server'),
    hint: context.tr('app.checks_tabs.pair_this_phone_in_settings_and'),
  );
}
