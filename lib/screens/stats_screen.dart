import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../api/server_call.dart';
import '../harness/harness.dart' show BackupPicker;
import '../library/cover_cache.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../people/people_directory.dart';
import '../tools/server_tools.dart';
import 'filtered_quotes_screen.dart';
import 'quote_form_screen.dart' show quoteColour;
import '../l10n/l10n.dart';

const _green = Color(0xFF6BAA75);
const _amber = Color(0xFFE59A4A);
const _red = Color(0xFFD2685B);

/// The numbers the server keeps about the library, as the web's Statistics page shows them and a little more
/// at home on a phone: the totals, an activity calendar, where the library stands on the forgetting curve, the
/// most-this and most-that tiles with their covers and faces, a timeline, a breakdown by author, actor, character,
/// language and more with portraits, the colours and the top tags. Names and tags open the quotes behind them.
class StatsScreen extends StatefulWidget {
  const StatsScreen({
    super.key,
    required this.tools,
    this.store,
    this.picker,
    this.anthologies,
  });

  final ServerTools tools;

  /// The phone's library, so a name or a tag can open the quotes behind it; null leaves them as plain text.
  final LibraryStore? store;
  final BackupPicker? picker;
  final AnthologyService? anthologies;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  LibraryStats? _stats;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.tools.stats();
      if (mounted) {
        setState(() {
          _stats = s;
          _problem = null;
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  bool get _canOpen => widget.store != null && widget.picker != null;

  void _openQuery(String title, {String? tag, String? query}) {
    if (!_canOpen) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FilteredQuotesScreen(
          store: widget.store!,
          picker: widget.picker!,
          title: title,
          tag: tag,
          query: query ?? '',
          anthologies: widget.anthologies,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(String label, Object value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        context.tr('app.prefs.value', {'value': value}),
        style: theme.textTheme.titleMedium,
      ),
    );
    Widget big(String label, Object value) => Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('app.prefs.value', {'value': value}),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.settings.statistics'))),
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
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.1,
                    children: [
                      big(context.tr('nav.tab.quotes.label'), s.quotes),
                      big(
                        context.tr('stats.overview.favourites.label'),
                        s.favourites,
                      ),
                      big(context.tr('library.group.none.label'), s.books),
                      big(context.tr('stats.breakdown.films.label'), s.films),
                      big(context.tr('stats.breakdown.shows.label'), s.shows),
                      if (s.games > 0)
                        big(
                          context.tr('movies.filters.media.game.label'),
                          s.games,
                        ),
                      big(context.tr('common.field.tags.label'), s.tags),
                      big(
                        context.tr('nav.tab.anthologies.label'),
                        s.anthologies,
                      ),
                    ],
                  ),
                  if (s.saves.any((d) => d.count > 0) ||
                      s.quiz.any((d) => d.count > 0) ||
                      s.practice.any((d) => d.count > 0)) ...[
                    const SizedBox(height: 16),
                    _Activity(stats: s),
                  ],
                  if (s.recall.total > 0) ...[
                    const SizedBox(height: 16),
                    _Memory(recall: s.recall),
                  ],
                  const SizedBox(height: 16),
                  _Superlatives(
                    stats: s,
                    onOpen: _canOpen ? (n) => _openQuery(n, query: n) : null,
                  ),
                  if (s.timeline.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Timeline(years: s.timeline),
                  ],
                  if (s.breakdown.values.any((b) => b.top.isNotEmpty)) ...[
                    const SizedBox(height: 16),
                    _BreakdownCard(
                      breakdown: s.breakdown,
                      onOpen: _canOpen ? (n) => _openQuery(n, query: n) : null,
                    ),
                  ],
                  if (s.colours.values.any((n) => n > 0)) ...[
                    const SizedBox(height: 16),
                    _Colours(colours: s.colours),
                  ],
                  if (s.firstSaved.isNotEmpty ||
                      s.busiestMonth.isNotEmpty ||
                      s.mostQuoted.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          if (s.firstSaved.isNotEmpty)
                            row(
                              context.tr('app.stats.first_saved'),
                              s.firstSaved,
                            ),
                          if (s.busiestMonth.isNotEmpty)
                            row(
                              context.tr('stats.super.busiest-month.label'),
                              '${s.busiestMonth} (${s.busiestMonthCount})',
                            ),
                          if (s.mostQuoted.isNotEmpty)
                            row(
                              context.tr('app.stats.most_quoted_work'),
                              '${s.mostQuoted} (${s.mostQuotedCount})',
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (s.topTags.isNotEmpty) ...[
                    _Head(context.tr('stats.top-tags.title')),
                    Card(
                      child: Column(
                        children: [
                          for (final t in s.topTags)
                            InkWell(
                              onTap: _canOpen
                                  ? () => _openQuery('#${t.name}', tag: t.name)
                                  : null,
                              child: row('#${t.name}', t.count),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ---- activity calendar ------------------------------------------------------------------------------------

enum _Stream { saves, quiz, practice }

class _Activity extends StatefulWidget {
  const _Activity({required this.stats});
  final LibraryStats stats;

  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  _Stream _stream = _Stream.saves;
  DayCount? _day;

  List<DayCount> get _series => switch (_stream) {
    _Stream.saves => widget.stats.saves,
    _Stream.quiz => widget.stats.quiz,
    _Stream.practice => widget.stats.practice,
  };

  String get _noun => switch (_stream) {
    _Stream.saves => 'saved',
    _Stream.quiz => 'answered in the quiz',
    _Stream.practice => 'practised',
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final streams = [
      _Stream.saves,
      if (s.quiz.any((d) => d.count > 0)) _Stream.quiz,
      if (s.practice.any((d) => d.count > 0)) _Stream.practice,
    ];
    final total = _series.fold<int>(0, (a, d) => a + d.count);
    final day = _day;
    return _Titled(
      title: context.tr('app.stats.activity'),
      trailing: streams.length < 2
          ? null
          : SegmentedButton<_Stream>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final k in streams)
                  ButtonSegment(
                    value: k,
                    label: Text(switch (k) {
                      _Stream.saves => context.tr('settings.keys.saved.tip'),
                      _Stream.quiz => context.tr('stats.activity.quiz.label'),
                      _Stream.practice => context.tr('quiz.practice.label'),
                    }),
                  ),
              ],
              selected: {_stream},
              onSelectionChanged: (v) => setState(() {
                _stream = v.single;
                _day = null;
              }),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day == null
                ? '$total $_noun in all'
                : '${day.count} $_noun on ${day.date}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _Calendar(
            data: _series,
            selected: day?.date,
            onDay: (d) => setState(() => _day = d),
          ),
        ],
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.data, required this.onDay, this.selected});

  final List<DayCount> data;
  final String? selected;
  final ValueChanged<DayCount> onDay;

  static const weeks = 26;
  static const cell = 14.0;
  static const gap = 3.0;

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = {for (final d in data) d.date: d.count};
    final peak = counts.values.fold<int>(1, (a, b) => b > a ? b : a);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // columns are weeks starting on Monday; the last column holds today
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final first = thisMonday.subtract(const Duration(days: 7 * (weeks - 1)));
    Color fill(int n) {
      if (n <= 0) return scheme.surfaceContainerHighest;
      final level = (4 * n / peak).ceil().clamp(1, 4);
      return scheme.primary.withValues(alpha: 0.2 + level * 0.2);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var w = 0; w < weeks; w++)
            Padding(
              padding: const EdgeInsets.only(right: gap),
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Builder(
                      builder: (context) {
                        final day = DateTime(
                          first.year,
                          first.month,
                          first.day + w * 7 + d,
                        );
                        if (day.isAfter(today)) {
                          return const SizedBox(
                            width: cell,
                            height: cell + gap,
                          );
                        }
                        final k = _key(day);
                        final n = counts[k] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: gap),
                          child: Semantics(
                            label: context.tr('app.stats.n_on_k', {
                              'n': n,
                              'k': k,
                            }),
                            child: GestureDetector(
                              onTap: () => onDay(DayCount(k, n)),
                              child: Container(
                                width: cell,
                                height: cell,
                                decoration: BoxDecoration(
                                  color: fill(n),
                                  borderRadius: BorderRadius.circular(3),
                                  border: k == selected
                                      ? Border.all(
                                          color: scheme.onSurface,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- memory ----------------------------------------------------------------------------------------------

String _halfLife(double days) => days < 1
    ? '${(days * 24).round()} hours'
    : '${days.toStringAsFixed(days < 10 ? 1 : 0)} days';

class _Memory extends StatelessWidget {
  const _Memory({required this.recall});
  final Recall recall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tile(
      String label,
      Object value,
      Color dot, [
      String? sub,
    ]) => Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('app.prefs.value', {'value': value}),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            ],
          ),
          if (sub != null)
            Text(
              sub,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
    return _Titled(
      title: context.tr('stats.memory.title'),
      trailing: Text(
        context.tr('app.stats.reviewed_of_total_in_rotation', {
          'reviewed': recall.reviewed,
          'total': recall.total,
        }),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          tile(
            context.tr('common.status.remembered.label'),
            recall.remembered,
            _green,
          ),
          tile(
            context.tr('common.status.forgetting.label'),
            recall.forgetting,
            _amber,
          ),
          tile(
            context.tr('common.status.probably-forgotten.label'),
            recall.probablyForgotten,
            _red,
          ),
          tile('Unseen', recall.unseen, scheme.outline),
          if (recall.reviewed > 0)
            tile(
              context.tr('app.stats.average_half_life'),
              _halfLife(recall.avgHalfLife),
              scheme.primary,
            ),
          if (recall.longestStreak > 0)
            tile(
              context.tr('app.stats.longest_streak'),
              '${recall.longestStreak} days',
              scheme.primary,
              '${recall.streak} days now',
            ),
        ],
      ),
    );
  }
}

// ---- superlatives ----------------------------------------------------------------------------------------

class _Superlatives extends StatelessWidget {
  const _Superlatives({required this.stats, this.onOpen});
  final LibraryStats stats;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final people = s.breakdown['people'];
    final top = people == null || people.top.isEmpty ? null : people.top.first;
    final tiles = <Widget>[
      if (s.mostAnnotated != null)
        _SuperTile(
          label: context.tr('app.stats.most_annotated'),
          title: s.mostAnnotated!.title,
          detail: '${s.mostAnnotated!.count} quotes',
          cover: s.mostAnnotated!.cover,
          onOpen: onOpen,
        ),
      if (s.mostQuotedWork != null)
        _SuperTile(
          label: context.tr('app.stats.most_quoted_work'),
          title: s.mostQuotedWork!.title,
          detail: '${s.mostQuotedWork!.count} quotes',
          cover: s.mostQuotedWork!.cover,
          onOpen: onOpen,
        ),
      if (top != null)
        _SuperTile(
          label: context.tr('stats.super.most-quoted-person.label'),
          title: top.name,
          detail: '${top.quotes} quotes',
          face: true,
          onOpen: onOpen,
        ),
      if (s.favouritePerson != null)
        _SuperTile(
          label: context.tr('stats.super.most-favourited-person.label'),
          title: s.favouritePerson!.title,
          detail: '${s.favouritePerson!.count} favourites',
          face: true,
          onOpen: onOpen,
        ),
      if (people?.mostRemembered != null)
        _SuperTile(
          label: context.tr('stats.super.best-remembered.label'),
          title: people!.mostRemembered!.name,
          detail:
              '${people.mostRemembered!.remembered} of ${people.mostRemembered!.quotes}',
          face: true,
          onOpen: onOpen,
        ),
      if (people?.mostForgotten != null)
        _SuperTile(
          label: context.tr('stats.super.most-forgotten.label'),
          title: people!.mostForgotten!.name,
          detail:
              '${people.mostForgotten!.probablyForgotten} of ${people.mostForgotten!.quotes}',
          face: true,
          onOpen: onOpen,
        ),
      if (s.busiestMonth.isNotEmpty)
        _SuperTile(
          label: context.tr('stats.super.busiest-month.label'),
          title: s.busiestMonth,
          detail: '${s.busiestMonthCount} saved',
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return _Titled(
      title: context.tr('bin.kind.annotation.plural'),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      ),
    );
  }
}

Work _coverOnly(String cover) => Work(
  id: 0,
  kind: WorkKind.book,
  title: '',
  creator: '',
  year: null,
  language: '',
  createdAt: DateTime.utc(2000),
  updatedAt: DateTime.utc(2000),
  cover: cover,
);

class _SuperTile extends StatelessWidget {
  const _SuperTile({
    required this.label,
    required this.title,
    required this.detail,
    this.cover = '',
    this.face = false,
    this.onOpen,
  });

  final String label, title, detail, cover;
  final bool face;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final art = face
        ? PersonFace.any(
            anyName: title,
            radius: 20,
            fallback: _Initial(title, 20),
          )
        : cover.isNotEmpty
        ? WorkCover(
            work: _coverOnly(cover),
            width: 40,
            height: 56,
            fallback: const SizedBox(width: 40, height: 56),
          )
        : null;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen == null ? null : () => onOpen!(title),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (art != null) ...[art, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      detail,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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

class _Initial extends StatelessWidget {
  const _Initial(this.name, this.radius);
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        t.isEmpty ? '?' : t.characters.first.toUpperCase(),
        style: TextStyle(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

// ---- timeline --------------------------------------------------------------------------------------------

class _Timeline extends StatelessWidget {
  const _Timeline({required this.years});
  final List<YearCount> years;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = [...years]..sort((a, b) => a.year.compareTo(b.year));
    final span = sorted.last.year - sorted.first.year;
    // a long timeline is read by the decade, a short one by the year
    final size = span > 40 ? 10 : 1;
    final buckets = <int, (int, int)>{};
    for (final y in sorted) {
      final k = y.year - (y.year % size);
      final b = buckets[k] ?? (0, 0);
      buckets[k] = (b.$1 + y.works, b.$2 + y.quotes);
    }
    final keys = buckets.keys.toList()..sort();
    final peak = buckets.values.fold<int>(1, (a, b) => b.$2 > a ? b.$2 : a);
    String name(int k) => size == 1 ? '$k' : '${k}s';
    return _Titled(
      title: context.tr('stats.timeline.title'),
      trailing: Text(
        context.tr('app.stats.year_the_works_came_out'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: SizedBox(
        height: 170,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final k in keys)
              Tooltip(
                message: context.tr('app.stats.x_x2_quotes_from_x3_works', {
                  'x': name(k),
                  'x2': buckets[k]!.$2,
                  'x3': buckets[k]!.$1,
                }),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 38,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${buckets[k]!.$2}',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: 8 + 80 * buckets[k]!.$2 / peak,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name(k),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- breakdown -------------------------------------------------------------------------------------------

final _kinds = <(String, String, bool, bool)>[
  // key, label, spans several works, a work (cover) rather than a person
  ('authors', 'Authors', true, false),
  ('books', 'Books', false, true),
  ('series', 'Series', true, false),
  ('films', 'Films', false, true),
  ('shows', 'Shows', false, true),
  ('directors', 'Directors', true, false),
  ('actors', 'Actors', true, false),
  ('characters', 'Characters', true, false),
  ('speakers', 'Speakers', true, false),
  ('people', 'Everyone', true, false),
];

class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({required this.breakdown, this.onOpen});
  final Map<String, Breakdown> breakdown;
  final ValueChanged<String>? onOpen;

  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final have = [
      for (final k in _kinds)
        if ((widget.breakdown[k.$1]?.top ?? const []).isNotEmpty) k,
    ];
    if (have.isEmpty) return const SizedBox.shrink();
    final current = have.firstWhere(
      (k) => k.$1 == _kind,
      orElse: () => have.first,
    );
    final b = widget.breakdown[current.$1]!;
    final peak = b.top.fold<int>(1, (a, t) => t.quotes > a ? t.quotes : a);
    return _Titled(
      title: context.tr('app.stats.breakdown'),
      trailing: Text(
        context.tr('app.stats.count_to_lower_case', {
          'count': b.count,
          'to_lower_case': current.$2.toLowerCase(),
        }),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in have)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k.$2),
                      selected: k == current,
                      onSelected: (_) => setState(() => _kind = k.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < b.top.length; i++)
            _BreakdownRow(
              rank: i + 1,
              tally: b.top[i],
              peak: peak,
              spansWorks: current.$3,
              isWork: current.$4,
              onOpen: widget.onOpen,
            ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.rank,
    required this.tally,
    required this.peak,
    required this.spansWorks,
    required this.isWork,
    this.onOpen,
  });

  final int rank, peak;
  final Tally tally;
  final bool spansWorks, isWork;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = tally;
    final art = isWork
        ? WorkCover(
            work: _coverOnly(t.cover),
            width: 28,
            height: 40,
            fallback: const SizedBox(width: 28, height: 40),
          )
        : PersonFace.any(
            anyName: t.name,
            radius: 18,
            fallback: _Initial(t.name, 18),
          );
    final recalled =
        t.remembered + t.forgetting + t.probablyForgotten + t.unseen;
    Widget seg(int n, Color c) => n <= 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: n,
            child: Container(color: c),
          );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen == null ? null : () => onOpen!(t.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                context.tr('app.stats.rank', {'rank': rank}),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            art,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 6,
                      child: Row(
                        children: [
                          Expanded(
                            flex: t.quotes,
                            child: recalled == 0
                                ? Container(color: scheme.primary)
                                : Row(
                                    children: [
                                      seg(t.remembered, _green),
                                      seg(t.forgetting, _amber),
                                      seg(t.probablyForgotten, _red),
                                      seg(t.unseen, scheme.outlineVariant),
                                    ],
                                  ),
                          ),
                          Expanded(
                            flex: (peak - t.quotes).clamp(0, peak),
                            child: Container(
                              color: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  countWords('quote', t.quotes),
                  style: theme.textTheme.labelMedium,
                ),
                if (spansWorks && t.works > 0)
                  Text(
                    countWords('work', t.works),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- colours ---------------------------------------------------------------------------------------------

class _Colours extends StatelessWidget {
  const _Colours({required this.colours});
  final Map<String, int> colours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = colours.values.fold<int>(1, (a, b) => b > a ? b : a);
    final total = colours.values.fold<int>(0, (a, b) => a + b);
    return _Titled(
      title: context.tr('metadata.categories.colours.title'),
      trailing: Text(
        context.tr('app.stats.total_marked', {'total': total}),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        children: [
          for (final c in quoteColors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: quoteColour(c),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      c[0].toUpperCase() + c.substring(1),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (colours[c] ?? 0) / peak,
                        minHeight: 8,
                        color: quoteColour(c),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${colours[c] ?? 0}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
