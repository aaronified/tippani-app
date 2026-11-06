import 'models.dart';

/// Compares two strings the way a reader counts: case does not matter and a run of digits is a number, so
/// "p. 8" comes before "p. 10" and "Chapter 2" before "Chapter 10".
int naturalCompare(String a, String b) {
  final x = _parts(a.toLowerCase());
  final y = _parts(b.toLowerCase());
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i], q = y[i];
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = pn != null && qn != null ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

final _digitRuns = RegExp(r'\d+|\D+');

List<String> _parts(String s) => [
  for (final m in _digitRuns.allMatches(s)) m.group(0)!,
];

/// [quotes] as they read in the work: by chapter (a quote with no chapter last), then by where in the chapter,
/// then by when the reader met it.
List<Quote> readingOrder(List<Quote> quotes) {
  final sorted = List.of(quotes);
  sorted.sort((a, b) {
    final ac = a.chapter.trim(), bc = b.chapter.trim();
    if (ac.isEmpty != bc.isEmpty) return ac.isEmpty ? 1 : -1;
    var c = naturalCompare(ac, bc);
    if (c != 0) return c;
    c = naturalCompare(a.location, b.location);
    if (c != 0) return c;
    c = a.notedAt.compareTo(b.notedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return sorted;
}

/// A chapter and its quotes. [name] is empty for the quotes that have none.
class ChapterGroup {
  const ChapterGroup(this.name, this.quotes);
  final String name;
  final List<Quote> quotes;
}

/// [quotes], already in [readingOrder], cut into their chapters.
List<ChapterGroup> groupByChapter(List<Quote> quotes) {
  final groups = <ChapterGroup>[];
  for (final q in quotes) {
    final name = q.chapter.trim();
    if (groups.isEmpty || groups.last.name != name) {
      groups.add(ChapterGroup(name, [q]));
    } else {
      groups.last.quotes.add(q);
    }
  }
  return groups;
}
