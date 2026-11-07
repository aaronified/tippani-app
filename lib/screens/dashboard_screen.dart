import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../app_controller.dart';
import '../harness/harness.dart' show BackupPicker;
import '../library/library_store.dart';
import '../library/models.dart';
import '../quiz/quiz.dart';
import '../sync/auto_sync.dart';
import 'library_widgets.dart' show QuoteTile;
import 'quiz_screen.dart';
import 'quote_screen.dart';

/// The words at the top of Home for [now]: a greeting for the time of day (with [name] when the phone knows who it is
/// paired as), and one line about keeping quotes for the day.
String greetingFor(DateTime now, String? name) {
  final h = now.hour;
  final String hello;
  if (h < 5) {
    hello = 'Up late';
  } else if (h < 8) {
    hello = 'Early start';
  } else if (h < 12) {
    hello = 'Good morning';
  } else if (h < 17) {
    hello = 'Good afternoon';
  } else if (h < 21) {
    hello = 'Good evening';
  } else {
    hello = 'Winding down';
  }
  return name == null || name.isEmpty ? hello : '$hello, $name';
}

const _epigraphs = [
  'A margin is a promise: that there is always room to answer back.',
  'The book is the author’s. The margin is yours.',
  'Nothing is really read until something is written beside it.',
  'A quote you cannot find again is a quote you did not keep.',
  'Reading twice is not repetition. It is the second half of reading once.',
  'Keep the line, and the book keeps you.',
  'Underlining is a question. A note is the answer.',
  'What you copied out by hand is what you actually read.',
  'A commonplace book is a memory you are allowed to lend.',
  'The margin is the only part of a book that is about you.',
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
const _months = [
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
    widget.quiz.drain();
  }

  @override
  void dispose() {
    _changes?.cancel();
    widget.quiz.removeListener(_rebuild);
    widget.controller.removeListener(_pairingChanged);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _pairingChanged() {
    if (mounted) _loadScores();
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
          _tiles(context),
          if (widget.quiz.waiting > 0) _waitingBanner(context),
          _dailyCard(context),
          _practiceCard(context),
          if (_scores != null && _scores!.states.total > 0)
            _states(context, _scores!),
          _shuffleSection(context),
          if (today.isNotEmpty) ...[
            _heading(context, 'On this day', '${today.length}'),
            for (final q in today.take(5)) _quoteTile(q),
          ],
          if (favourites.isNotEmpty) ...[
            _heading(context, 'Favourites', '★ ${favourites.length}'),
            for (final q in shownFavourites) _quoteTile(q),
            if (favourites.length > _favouritesShown)
              Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _allFavourites = !_allFavourites),
                  child: Text(
                    _allFavourites
                        ? 'Show fewer'
                        : 'View more (${favourites.length - _favouritesShown})',
                  ),
                ),
              ),
          ],
          if (_loaded && _quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: Text(
                'Nothing saved yet. Add a quote from the Quotes tab, or scan a page, and it will show up here.',
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
              icon: Icons.auto_stories_outlined,
              big: '$books',
              label: books == 1 ? 'book' : 'books',
              small: '$bookQuotes ${bookQuotes == 1 ? 'quote' : 'quotes'}',
              onTap: widget.onOpenLibrary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _tile(
              context,
              icon: Icons.movie_outlined,
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
                '$label · $small',
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

  Widget _waitingBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = widget.quiz.waiting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: scheme.tertiaryContainer,
        child: ListTile(
          leading: Icon(
            Icons.cloud_upload_outlined,
            color: scheme.onTertiaryContainer,
          ),
          title: Text(
            n == 1
                ? '1 answer waiting to be sent'
                : '$n answers waiting to be sent',
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
          trailing: TextButton(
            onPressed: widget.quiz.drain,
            child: const Text('Send now'),
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
        'Connect to your server in Settings to get a few quotes to recall each day.',
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
              _scoresError ?? 'Could not load today’s quiz.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: _loadScores, child: const Text('Try again')),
        ],
      );
    } else {
      final due = s.remaining;
      final done = s.dailyAnswered;
      final String headline;
      final String sub;
      if (due == 0 && done > 0) {
        headline = 'All caught up ✓';
        sub =
            '${s.dailyGot} recalled · ${s.dailyAnswered - s.dailyGot} to resurface · back tomorrow';
      } else if (due == 0) {
        headline = 'Nothing due today';
        sub = 'Add or review more quotes to build your schedule.';
      } else {
        headline = due == 1 ? '1 card due today' : '$due cards due today';
        sub = done > 0 ? '$done answered so far' : 'A few minutes, no more.';
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
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(done > 0 ? 'Continue' : 'Start'),
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
                  Icon(Icons.bolt_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'DAILY QUIZ',
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
                      avatar: const Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                      ),
                      label: Text('${s.streak}-day streak'),
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
                  Icon(
                    Icons.fitness_center_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PRACTICE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'unlimited',
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
                    : 'Go through your library as long as you like, and skip whatever you like.',
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
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start practice'),
                  ),
                  if (s != null && s.practiceAnswered > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _resetPractice,
                      child: const Text('Reset score'),
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
                'WHERE YOU STAND',
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
                  'Your library is bigger than the schedule can keep up with: about ${s.capacity} quotes stay current, and you have ${st.total}. The quiz still leads with the stalest.',
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
              icon: const Icon(Icons.shuffle_rounded),
              label: Text(shuffled == null ? 'Shuffle' : 'Another one'),
            ),
          ),
        ),
        if (shuffled != null) _quoteTile(shuffled),
      ],
    );
  }
}
