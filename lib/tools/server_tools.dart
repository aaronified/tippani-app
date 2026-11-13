import '../api/offline_writes.dart';
import '../api/server_call.dart';
import '../app_controller.dart';

/// Something in the server's bin: a quote, work or other record deleted not long ago and still restorable.
class BinEntry {
  const BinEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.childCount,
    required this.deletedAt,
  });

  final int id;

  /// "annotation", "dialogue", "book" and so on: what was deleted.
  final String kind;

  /// Its words or title.
  final String label;

  /// What was deleted with it (a book's quotes).
  final int childCount;
  final String deletedAt;

  factory BinEntry.fromJson(Map<String, Object?> j) => BinEntry(
    id: (j['id'] as num).toInt(),
    kind: (j['kind'] as String?) ?? '',
    label: (j['label'] as String?) ?? '',
    childCount: (j['child_count'] as num?)?.toInt() ?? 0,
    deletedAt: (j['deleted_at'] as String?) ?? '',
  );
}

class Bin {
  const Bin(this.keptDays, this.entries);

  /// How long the server keeps what is in it.
  final int keptDays;
  final List<BinEntry> entries;
}

/// A count and a name, for a top-ten list.
class Counted {
  const Counted(this.name, this.count);
  final String name;
  final int count;
}

/// One day on the activity calendar: how many things happened that day.
class DayCount {
  const DayCount(this.date, this.count);

  /// `2026-11-07`.
  final String date;
  final int count;
}

/// One row of a breakdown: a person, a work, a series, and how their quotes stand on the forgetting curve.
class Tally {
  const Tally({
    required this.name,
    this.cover = '',
    this.works = 0,
    this.quotes = 0,
    this.remembered = 0,
    this.forgetting = 0,
    this.probablyForgotten = 0,
    this.unseen = 0,
  });

  final String name;

  /// The cover or poster of the entity's first work, for the work kinds; '' for a person or a series.
  final String cover;
  final int works, quotes, remembered, forgetting, probablyForgotten, unseen;

  factory Tally.fromJson(Map<String, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return Tally(
      name: (j['name'] as String?) ?? '',
      cover: (j['cover_path'] as String?) ?? '',
      works: n('works'),
      quotes: n('quotes'),
      remembered: n('remembered'),
      forgetting: n('forgetting'),
      probablyForgotten: n('probably_forgotten'),
      unseen: n('unseen'),
    );
  }
}

/// One kind in the breakdown (authors, actors, characters...): how many there are, the top rows by quotes, and
/// the best and worst remembered.
class Breakdown {
  const Breakdown({
    this.count = 0,
    this.top = const [],
    this.mostRemembered,
    this.mostForgotten,
  });

  final int count;
  final List<Tally> top;
  final Tally? mostRemembered, mostForgotten;

  factory Breakdown.fromJson(Object? v) {
    if (v is! Map) return const Breakdown();
    final j = Map<String, Object?>.from(v);
    Tally? one(Object? t) =>
        t is Map ? Tally.fromJson(Map<String, Object?>.from(t)) : null;
    final top = j['top'];
    return Breakdown(
      count: (j['count'] as num?)?.toInt() ?? 0,
      top: [
        if (top is List)
          for (final t in top)
            if (t is Map) Tally.fromJson(Map<String, Object?>.from(t)),
      ],
      mostRemembered: one(j['most_remembered']),
      mostForgotten: one(j['most_forgotten']),
    );
  }
}

/// A "most" tile: a work or a person, and how many.
class Top {
  const Top(this.title, this.count, [this.cover = '']);

  final String title;
  final int count;
  final String cover;

  static Top? fromJson(Object? v) {
    if (v is! Map) return null;
    final title = (v['title'] as String?) ?? '';
    if (title.isEmpty) return null;
    return Top(
      title,
      (v['count'] as num?)?.toInt() ?? 0,
      (v['cover_path'] as String?) ?? '',
    );
  }
}

/// Where the whole library stands on the forgetting curve.
class Recall {
  const Recall({
    this.total = 0,
    this.remembered = 0,
    this.forgetting = 0,
    this.probablyForgotten = 0,
    this.unseen = 0,
    this.reviewed = 0,
    this.avgHalfLife = 0,
    this.streak = 0,
    this.longestStreak = 0,
  });

  final int total, remembered, forgetting, probablyForgotten, unseen;
  final int reviewed, streak, longestStreak;

  /// In days.
  final double avgHalfLife;

  factory Recall.fromJson(Object? v) {
    if (v is! Map) return const Recall();
    final j = Map<String, Object?>.from(v);
    final st = j['states'] is Map
        ? Map<String, Object?>.from(j['states']! as Map)
        : <String, Object?>{};
    int n(Map<String, Object?> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return Recall(
      total: n(st, 'total'),
      remembered: n(st, 'remembered'),
      forgetting: n(st, 'forgetting'),
      probablyForgotten: n(st, 'probably_forgotten'),
      unseen: n(st, 'unseen'),
      reviewed: n(j, 'reviewed'),
      avgHalfLife: (j['avg_half_life'] as num?)?.toDouble() ?? 0,
      streak: n(j, 'streak'),
      longestStreak: n(j, 'longest_streak'),
    );
  }
}

/// How many works and quotes belong to one year of the timeline.
class YearCount {
  const YearCount(this.year, this.works, this.quotes);
  final int year, works, quotes;
}

List<DayCount> _days(Object? v) => [
  if (v is List)
    for (final d in v)
      if (d is Map)
        DayCount(
          (d['date'] as String?) ?? '',
          (d['count'] as num?)?.toInt() ?? 0,
        ),
];

/// The numbers the server keeps about the library.
class LibraryStats {
  const LibraryStats({
    required this.quotes,
    required this.books,
    required this.films,
    required this.shows,
    required this.games,
    required this.favourites,
    required this.tags,
    required this.anthologies,
    required this.firstSaved,
    required this.busiestMonth,
    required this.busiestMonthCount,
    required this.colours,
    required this.topTags,
    required this.mostQuoted,
    required this.mostQuotedCount,
    this.saves = const [],
    this.quiz = const [],
    this.practice = const [],
    this.recall = const Recall(),
    this.breakdown = const {},
    this.timeline = const [],
    this.mostAnnotated,
    this.mostQuotedWork,
    this.favouritePerson,
    this.genres = 0,
  });

  /// Every quote: from books, from films and shows, and standalone.
  final int quotes;
  final int books, films, shows, games, favourites, tags, anthologies, genres;
  final String firstSaved;
  final String busiestMonth;
  final int busiestMonthCount;
  final Map<String, int> colours;
  final List<Counted> topTags;
  final String mostQuoted;
  final int mostQuotedCount;

  /// What was saved, quizzed and practised, by day.
  final List<DayCount> saves, quiz, practice;
  final Recall recall;

  /// By kind: `authors`, `actors`, `characters`, `speakers`, `people`, `books`, `films`, `shows`, `series`...
  final Map<String, Breakdown> breakdown;
  final List<YearCount> timeline;
  final Top? mostAnnotated, mostQuotedWork, favouritePerson;

  factory LibraryStats.fromJson(Map<String, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    final busiest = j['busiest_month'] is Map
        ? asMap(j['busiest_month'])
        : <String, Object?>{};
    final most = j['most_quoted'] is Map
        ? asMap(j['most_quoted'])
        : <String, Object?>{};
    final colors = j['colors'] is Map
        ? asMap(j['colors'])
        : <String, Object?>{};
    final tags = j['top_tags'];
    final bd = j['breakdown'];
    final tl = j['timeline'];
    return LibraryStats(
      quotes: n('annotations') + n('dialogues') + n('quotes'),
      books: n('books'),
      films: n('films'),
      shows: n('shows'),
      games: n('games'),
      favourites: n('favorites'),
      tags: n('tags'),
      anthologies: n('anthologies'),
      genres: n('genres'),
      firstSaved: (j['first_saved'] as String?) ?? '',
      busiestMonth: (busiest['month'] as String?) ?? '',
      busiestMonthCount: (busiest['count'] as num?)?.toInt() ?? 0,
      colours: {
        for (final e in colors.entries) e.key: (e.value as num?)?.toInt() ?? 0,
      },
      topTags: [
        if (tags is List)
          for (final t in tags)
            if (t is Map)
              Counted(
                (t['name'] as String?) ?? '',
                (t['count'] as num?)?.toInt() ?? 0,
              ),
      ],
      mostQuoted: (most['title'] as String?) ?? '',
      mostQuotedCount: (most['count'] as num?)?.toInt() ?? 0,
      saves: _days(j['daily_activity']),
      quiz: _days(j['daily_quiz']),
      practice: _days(j['daily_practice']),
      recall: Recall.fromJson(j['recall']),
      breakdown: {
        if (bd is Map)
          for (final e in bd.entries) '${e.key}': Breakdown.fromJson(e.value),
      },
      timeline: [
        if (tl is List)
          for (final y in tl)
            if (y is Map)
              YearCount(
                (y['year'] as num?)?.toInt() ?? 0,
                (y['works'] as num?)?.toInt() ?? 0,
                (y['quotes'] as num?)?.toInt() ?? 0,
              ),
      ],
      mostAnnotated: Top.fromJson(j['most_annotated']),
      mostQuotedWork: Top.fromJson(j['most_quoted']),
      favouritePerson: Top.fromJson(j['favourite_person']),
    );
  }
}

/// What the server offers beyond the library itself: its bin, and its numbers. An interface so a test can
/// stand in for the server.
abstract class ServerTools {
  bool get available;
  Future<Bin> bin();
  Future<void> restore(int id);
  Future<void> deleteForever(int id);
  Future<void> emptyBin();
  Future<LibraryStats> stats();
}

class PairedServerTools implements ServerTools {
  PairedServerTools(this._controller, {this.writes});
  final AppController _controller;

  /// Where a restore waits when the server cannot be reached. Deleting for good and emptying the bin cannot be
  /// undone, so they are not queued.
  final OfflineWrites? writes;

  @override
  bool get available => _controller.paired;

  @override
  Future<Bin> bin() => serverCall(_controller, (c) async {
    final body = asMap(await c.getJson('/trash'));
    final all = body['trash'];
    return Bin((body['days'] as num?)?.toInt() ?? 30, [
      if (all is List)
        for (final e in all) BinEntry.fromJson(asMap(e)),
    ]);
  });

  @override
  Future<void> restore(int id) => serverCall(_controller, (c) async {
    final w = writes;
    if (w == null) {
      await c.postJson('/trash/$id/restore', {});
      return;
    }
    await w.write(
      'POST',
      '/trash/$id/restore',
      const {},
      local: () => w.patchKept('/trash', (j) {
        final m = Map<String, Object?>.from(asMap(j));
        m['trash'] = [
          for (final e in (m['trash'] as List? ?? const []))
            if (!(e is Map && e['id'] == id)) e,
        ];
        return m;
      }),
    );
  });

  @override
  Future<void> deleteForever(int id) => serverCall(_controller, (c) async {
    await c.delete('/trash/$id');
  });

  @override
  Future<void> emptyBin() => serverCall(_controller, (c) async {
    await c.delete('/trash');
  });

  @override
  Future<LibraryStats> stats() => serverCall(_controller, (c) async {
    return LibraryStats.fromJson(
      asMap(
        await c.getJson(
          '/stats?offset=${DateTime.now().timeZoneOffset.inMinutes}',
        ),
      ),
    );
  });
}
