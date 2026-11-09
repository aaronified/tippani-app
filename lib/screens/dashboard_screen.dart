import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../app_controller.dart';
import '../harness/harness.dart' show BackupPicker;
import '../imports/import_service.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../quiz/quiz.dart';
import '../sync/auto_sync.dart';
import '../library/quote_chips.dart' show creditNames;
import '../widgets/token_search.dart';
import 'library_widgets.dart' show QuoteTile;
import 'quiz_screen.dart';
import 'quote_screen.dart';
import 'search_screen.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// The words at the top of Home for [now]: a greeting for the time of day (with [name] when the phone knows who it is
/// paired as), and one line about keeping quotes for the day.
String greetingFor(DateTime now, String? name) {
  final h = now.hour;
  final String hello;
  if (h < 5) {
    hello = tx('app.dashboard.up_late');
  } else if (h < 8) {
    hello = tx('app.dashboard.early_start');
  } else if (h < 12) {
    hello = tx('app.dashboard.good_morning');
  } else if (h < 17) {
    hello = tx('app.dashboard.good_afternoon');
  } else if (h < 21) {
    hello = tx('app.dashboard.good_evening');
  } else {
    hello = tx('app.dashboard.winding_down');
  }
  return name == null || name.isEmpty ? hello : '$hello, $name';
}

final _epigraphs = [
  'A margin is a promise: that there is always room to answer back.',
  tx('greeting.epigraph.2'),
  tx('greeting.epigraph.3'),
  'A quote you cannot find again is a quote you did not keep.',
  tx('greeting.epigraph.5'),
  tx('greeting.epigraph.6'),
  tx('greeting.epigraph.7'),
  tx('greeting.epigraph.8'),
  'A commonplace book is a memory you are allowed to lend.',
  tx('greeting.epigraph.10'),
];

/// The line for the day: the same all day, a different one tomorrow.
String epigraphFor(DateTime now) {
  final day = now.difference(DateTime(now.year)).inDays;
  return _epigraphs[day % _epigraphs.length];
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
final _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String dateLine(DateTime now) =>
    '${_weekdays[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}';

/// The quotes saved on this day of the year in an earlier year (by the date the reader noted them).
List<Quote> onThisDay(List<Quote> all, DateTime now) => [
  for (final q in all)
    if (q.notedAt.toLocal().month == now.month &&
        q.notedAt.toLocal().day == now.day &&
        q.notedAt.toLocal().year != now.year)
      q,
];

/// Home: the day's greeting, what the library holds, the Daily Quiz and Practice, where the reader stands, a line at
/// random, the quotes saved on this day in earlier years, and the favourites.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.store,
    required this.quiz,
    required this.controller,
    required this.picker,
    this.anthologies,
    this.auto,
    this.onOpenLibrary,
    this.onOpenCatalogue,
    this.imports,
    this.onOpenImports,
    this.clock,
    this.random,
  });

  final LibraryStore store;
  final QuizService quiz;
  final AppController controller;
  final BackupPicker picker;
  final AnthologyService? anthologies;
  final AutoSync? auto;

  /// Taken when a tile is pressed; null leaves the tile as plain information.
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenCatalogue;

  /// Where imported quotes wait for approval, and the way to look at them; null leaves the card out.
  final ImportService? imports;
  final VoidCallback? onOpenImports;

  /// The time and the dice, so a test can fix them.
  final DateTime Function()? clock;
  final math.Random? random;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _favouritesShown = 4;

  List<Work> _works = const [];
  List<Quote> _quotes = const [];
  final _byId = <int, Work>{};
  bool _loaded = false;
  QuizScores? _scores;
  String? _scoresError;
  bool _scoresLoading = false;
  Quote? _shuffled;
  bool _allFavourites = false;
  int _pendingImports = 0;
  StreamSubscription<void>? _changes;

  DateTime get _now => (widget.clock ?? DateTime.now)();
  math.Random get _random => widget.random ?? math.Random();

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => _loadLibrary());
    widget.quiz.addListener(_rebuild);
    widget.controller.addListener(_pairingChanged);
    _loadLibrary();
    _loadScores();
    _loadImports();
    _loadSearchSources();
    widget.quiz.drain();
  }

  final _searchBox = TextEditingController();
  SearchSources _sources = const SearchSources();

  /// What the search box can suggest after `tag:`, `by:` and `in:`.
  Future<void> _loadSearchSources() async {
    try {
      final tags = await widget.store.tags();
      final works = await widget.store.works();
      final seen = <String>{};
      final people = <String>[];
      for (final w in works) {
        for (final n in creditNames(w.creator)) {
          if (seen.add(n.toLowerCase())) people.add(n);
        }
      }
      if (mounted) {
        setState(() {
          _sources = SearchSources(
            tags: tags,
            people: people,
            works: [for (final w in works) w.title],
          );
        });
      }
    } on Object {
      // the box still searches, it just suggests less
    }
  }

  /// How many imported quotes wait for approval (the same count the Settings row is badged with).
  Future<void> _loadImports() async {
    final s = widget.imports;
    if (s == null || !s.available) {
      if (_pendingImports != 0 && mounted) setState(() => _pendingImports = 0);
      return;
    }
    try {
      final n = await s.pending();
      if (mounted) setState(() => _pendingImports = n);
    } on Object {
      // the card is a nicety; the Import screen says what is wrong
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.quiz.removeListener(_rebuild);
    widget.controller.removeListener(_pairingChanged);
    _searchBox.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _pairingChanged() {
    if (mounted) {
      _loadScores();
      _loadImports();
    }
  }

  Future<void> _loadLibrary() async {
    final works = await widget.store.works();
    final quotes = await widget.store.quotes(limit: 100000);
    if (!mounted) return;
    setState(() {
      _works = works;
      _quotes = quotes;
      _byId
        ..clear()
        ..addEntries(works.map((w) => MapEntry(w.id, w)));
      _loaded = true;
      // a shuffled quote that has been deleted or changed is let go
      final s = _shuffled;
      if (s != null) {
        _shuffled = quotes.where((q) => q.id == s.id).firstOrNull;
      }
    });
  }

  Future<void> _loadScores() async {
    if (!widget.quiz.available) {
      if (mounted) setState(() => _scores = null);
      return;
    }
    setState(() {
      _scoresLoading = true;
      _scoresError = null;
    });
    try {
      final s = await widget.quiz.scores();
      if (mounted) {
        setState(() {
          _scores = s;
          _scoresLoading = false;
        });
      }
    } on QuizException catch (e) {
      if (mounted) {
        setState(() {
          _scoresError = e.message;
          _scoresLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadLibrary(), _loadScores(), widget.quiz.drain()]);
  }

  Future<void> _play(QuizMode mode) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizScreen(service: widget.quiz, mode: mode),
      ),
    );
    if (mounted) await _loadScores();
  }

  Future<void> _openQuote(Quote q) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => QuoteScreen(
          store: widget.store,
          quoteId: q.id,
          picker: widget.picker,
          anthologies: widget.anthologies,
        ),
      ),
    );
    await _loadLibrary();
  }

  void _shuffle() {
    if (_quotes.isEmpty) return;
    Quote pick;
    do {
      pick = _quotes[_random.nextInt(_quotes.length)];
    } while (_quotes.length > 1 && pick.id == _shuffled?.id);
    setState(() => _shuffled = pick);
  }

  Widget _quoteTile(Quote q) => QuoteTile(
    key: ValueKey('home-quote-${q.id}'),
    quote: q,
    work: _byId[q.workId],
    onTap: () => _openQuote(q),
    onChip: (_) => _openQuote(q),
    onFavourite: () async {
      await widget.store.setFavorite(q.id, !q.favorite);
      await _loadLibrary();
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = _now;
    final today = onThisDay(_quotes, now);
    final favourites = [
      for (final q in _quotes)
        if (q.favorite) q,
    ];
    final shownFavourites = _allFavourites
        ? favourites
        : favourites.take(_favouritesShown).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              dateLine(now).toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              greetingFor(now, widget.controller.username),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Text(
              epigraphFor(now),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TokenSearchField(
              controller: _searchBox,
              hintText: context.tr(
                'app.search.search_words_names_tags_and_titles',
              ),
              sources: () => _sources,
              onSubmitted: (text) => openSearch(
                context,
                store: widget.store,
                picker: widget.picker,
                anthologies: widget.anthologies,
                initial: text,
              ),
            ),
          ),
          _tiles(context),
          if (_pendingImports > 0 && widget.onOpenImports != null)
            _importsCard(context),
          if (widget.quiz.waiting > 0) _waitingBanner(context),
          _dailyCard(context),
          _practiceCard(context),
          if (_scores != null && _scores!.states.total > 0)
            _states(context, _scores!),
          _shuffleSection(context),
          if (today.isNotEmpty) ...[
            _heading(
              context,
              context.tr('app.dashboard.on_this_day'),
              '${today.length}',
            ),
            for (final q in today.take(5)) _quoteTile(q),
          ],
          if (favourites.isNotEmpty) ...[
            _heading(
              context,
              context.tr('stats.overview.favourites.label'),
              '★ ${favourites.length}',
            ),
            for (final q in shownFavourites) _quoteTile(q),
            if (favourites.length > _favouritesShown)
              Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _allFavourites = !_allFavourites),
                  child: Text(
                    _allFavourites
                        ? context.tr('app.dashboard.show_fewer')
                        : context.tr(
                            'app.dashboard.view_more_favourites_shown',
                            {
                              'favourites_shown':
                                  favourites.length - _favouritesShown,
                            },
                          ),
                  ),
                ),
              ),
          ],
          if (_loaded && _quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: Text(
                context.tr('app.dashboard.nothing_saved_yet_add_a_quote'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String trailing) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Text(
            trailing,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tiles(BuildContext context) {
    var books = 0, titles = 0, bookQuotes = 0, screenQuotes = 0;
    for (final w in _works) {
      if (_isScreen(w)) {
        titles++;
      } else {
        books++;
      }
    }
    for (final q in _quotes) {
      final w = _byId[q.workId];
      if (w == null) continue;
      if (_isScreen(w)) {
        screenQuotes++;
      } else {
        bookQuotes++;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _tile(
              context,
              icon: Ti.notebook,
              big: '$books',
              label: books == 1
                  ? context.tr('app.count.book_word.one')
                  : context.tr('app.count.book_word.other'),
              small: countWords('quote', bookQuotes),
              onTap: widget.onOpenLibrary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              context,
              icon: Ti.movie,
              big: '$titles',
              label: titles == 1 ? 'title' : 'titles',
              small: '$screenQuotes ${screenQuotes == 1 ? 'line' : 'lines'}',
              onTap: widget.onOpenCatalogue,
            ),
          ),
        ],
      ),
    );
  }

  bool _isScreen(Work w) =>
      w.kind == WorkKind.film ||
      w.kind == WorkKind.show ||
      w.kind == WorkKind.game;

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String big,
    required String label,
    required String small,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(height: 10),
              Text(
                big,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                context.tr('app.dashboard.label_small', {
                  'label': label,
                  'small': small,
                }),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: scheme.secondaryContainer,
        child: ListTile(
          leading: Icon(Ti.archive, color: scheme.onSecondaryContainer),
          title: Text(
            trn('app.dashboard.imports_waiting', _pendingImports),
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          trailing: TextButton(
            onPressed: () async {
              widget.onOpenImports?.call();
            },
            child: Text(context.tr('app.dashboard.review')),
          ),
        ),
      ),
    );
  }

  Widget _waitingBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = widget.quiz.waiting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: scheme.tertiaryContainer,
        child: ListTile(
          leading: Icon(Ti.cloudUpload, color: scheme.onTertiaryContainer),
          title: Text(
            trn('app.dashboard.answers_waiting', n),
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
          trailing: TextButton(
            onPressed: widget.quiz.drain,
            child: Text(context.tr('app.dashboard.send_now')),
          ),
        ),
      ),
    );
  }

  Widget _dailyCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _scores;
    Widget body;
    if (!widget.quiz.available) {
      body = Text(
        context.tr('app.dashboard.connect_to_your_server_in_settings'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    } else if (s == null && _scoresLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    } else if (s == null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              _scoresError ??
                  context.tr('app.dashboard.could_not_load_today_s_quiz'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadScores,
            child: Text(context.tr('common.source.retry')),
          ),
        ],
      );
    } else {
      final due = s.remaining;
      final done = s.dailyAnswered;
      final String headline;
      final String sub;
      if (due == 0 && done > 0) {
        headline = context.tr('app.dashboard.all_caught_up');
        sub = context.tr('app.dashboard.recalled_resurface', {
          'got': s.dailyGot,
          'again': s.dailyAnswered - s.dailyGot,
        });
      } else if (due == 0) {
        headline = context.tr('app.dashboard.nothing_due_today');
        sub = context.tr('app.dashboard.add_or_review_more_quotes_to');
      } else {
        headline = trn('app.dashboard.cards_due', due);
        sub = done > 0
            ? context.tr('app.dashboard.answered_so_far', {'n': done})
            : context.tr('app.dashboard.a_few_minutes');
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            sub,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (s.quota > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: math.min(1, done / s.quota),
              ),
            ),
          ],
          if (due > 0) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _play(QuizMode.daily),
              icon: const Icon(Ti.playerPlayFilled),
              label: Text(
                done > 0
                    ? context.tr('home.daily.resume.label')
                    : context.tr('home.daily.start.label'),
              ),
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Ti.bolt, color: scheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('app.dashboard.daily_quiz'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (s != null && s.streak > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Ti.flame, size: 18),
                      label: Text(
                        context.tr('app.dashboard.streak_day_streak', {
                          'streak': s.streak,
                        }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _practiceCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _scores;
    final available = widget.quiz.available;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Ti.barbell, color: scheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('app.dashboard.practice'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.tr('home.practice.unlimited.label'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s != null && s.practiceAnswered > 0
                    ? '${s.practiceGot} of ${s.practiceAnswered} recalled'
                    : context.tr(
                        'app.dashboard.go_through_your_library_as_long',
                      ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: available
                        ? () => _play(QuizMode.practice)
                        : null,
                    icon: const Icon(Ti.playerPlayFilled),
                    label: Text(context.tr('home.practice.start.label')),
                  ),
                  if (s != null && s.practiceAnswered > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _resetPractice,
                      child: Text(context.tr('app.dashboard.reset_score')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetPractice() async {
    try {
      await widget.quiz.resetPractice();
      await _loadScores();
    } on QuizException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _states(BuildContext context, QuizScores s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final st = s.states;
    final parts = <(String, int, Color)>[
      ('remembered', st.remembered, scheme.primary),
      ('forgetting', st.forgetting, scheme.tertiary),
      ('probably forgotten', st.probablyForgotten, scheme.error),
      ('unseen', st.unseen, scheme.outlineVariant),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('app.dashboard.where_you_stand'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final p in parts)
                        if (p.$2 > 0)
                          Expanded(
                            flex: p.$2,
                            child: ColoredBox(color: p.$3),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (final p in parts)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 5, backgroundColor: p.$3),
                        const SizedBox(width: 6),
                        Text(
                          '${p.$2} ${p.$1}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                ],
              ),
              if (s.capacity > 0 && st.total > s.capacity) ...[
                const SizedBox(height: 10),
                Text(
                  context.tr('app.dashboard.your_library_is_bigger_than_the', {
                    'capacity': s.capacity,
                    'total': st.total,
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shuffleSection(BuildContext context) {
    final shuffled = _shuffled;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _quotes.isEmpty ? null : _shuffle,
              icon: const Icon(Ti.arrowsShuffle),
              label: Text(shuffled == null ? 'Shuffle' : 'Another one'),
            ),
          ),
        ),
        if (shuffled != null) _quoteTile(shuffled),
      ],
    );
  }
}
