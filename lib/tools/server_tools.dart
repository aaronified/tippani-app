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
  });

  /// Every quote: from books, from films and shows, and standalone.
  final int quotes;
  final int books, films, shows, games, favourites, tags, anthologies;
  final String firstSaved;
  final String busiestMonth;
  final int busiestMonthCount;
  final Map<String, int> colours;
  final List<Counted> topTags;
  final String mostQuoted;
  final int mostQuotedCount;

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
    return LibraryStats(
      quotes: n('annotations') + n('dialogues') + n('quotes'),
      books: n('books'),
      films: n('films'),
      shows: n('shows'),
      games: n('games'),
      favourites: n('favorites'),
      tags: n('tags'),
      anthologies: n('anthologies'),
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
  PairedServerTools(this._controller);
  final AppController _controller;

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
    await c.postJson('/trash/$id/restore', {});
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
    return LibraryStats.fromJson(asMap(await c.getJson('/stats')));
  });
}
