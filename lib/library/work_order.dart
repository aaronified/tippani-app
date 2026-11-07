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

/// How the quotes of a work are ordered.
enum QuoteOrder {
  reading('In reading order'),
  newest('Newest first'),
  oldest('Oldest first');

  const QuoteOrder(this.label);
  final String label;
}

/// What the quotes of a work are gathered under.
enum QuoteGroup {
  chapter('Chapter'),
  colour('Colour'),
  tag('Tag'),
  speaker('Who said it'),
  month('Month noted'),
  none('No grouping');

  const QuoteGroup(this.label);
  final String label;
}

/// [quotes] in the order asked for. Never changes the list it is given.
List<Quote> orderQuotes(List<Quote> quotes, QuoteOrder order) {
  switch (order) {
    case QuoteOrder.reading:
      return readingOrder(quotes);
    case QuoteOrder.newest:
      return [...quotes]..sort((a, b) {
        final c = b.notedAt.compareTo(a.notedAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    case QuoteOrder.oldest:
      return [...quotes]..sort((a, b) {
        final c = a.notedAt.compareTo(b.notedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
  }
}

/// A heading's key (empty: "none of these") and its quotes.
class QuoteSection {
  const QuoteSection(this.key, this.quotes);
  final String key;
  final List<Quote> quotes;
}

const _colourOrder = ['yellow', 'blue', 'pink', 'orange', 'green', 'purple'];

String _two(int n) => n.toString().padLeft(2, '0');

/// [ordered] cut into sections by [group], each keeping the order [ordered] has. A quote with several tags (or
/// several speakers) is in the section of each. Keys are not words: the screen says what each one is called.
/// For [QuoteGroup.chapter] the sections follow [ordered] (so reading order reads as a book); the others are
/// ordered by their key, the untagged and unnamed last, the months newest first.
List<QuoteSection> sectionQuotes(List<Quote> ordered, QuoteGroup group) {
  if (group == QuoteGroup.none) return [QuoteSection('', ordered)];
  final by = <String, List<Quote>>{};
  void put(String k, Quote q) => by.putIfAbsent(k, () => []).add(q);
  for (final q in ordered) {
    switch (group) {
      case QuoteGroup.chapter:
        put(q.chapter.trim(), q);
      case QuoteGroup.colour:
        put(q.color.isEmpty ? 'yellow' : q.color, q);
      case QuoteGroup.tag:
        if (q.tags.isEmpty) {
          put('', q);
        } else {
          for (final t in q.tags) {
            put(t, q);
          }
        }
      case QuoteGroup.speaker:
        final names = speakerNamesOf(q.speaker);
        if (names.isEmpty) {
          put('', q);
        } else {
          for (final n in names) {
            put(n, q);
          }
        }
      case QuoteGroup.month:
        final d = q.notedAt.toLocal();
        put('${d.year}-${_two(d.month)}', q);
      case QuoteGroup.none:
        break;
    }
  }
  final keys = by.keys.toList();
  int lastIfEmpty(String a, String b) {
    if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
    return 0;
  }

  switch (group) {
    case QuoteGroup.chapter:
      // first appearance; a chapter-less run is last when the order is reading order
      break;
    case QuoteGroup.colour:
      keys.sort((a, b) {
        final i = _colourOrder.indexOf(a), j = _colourOrder.indexOf(b);
        return (i < 0 ? 99 : i).compareTo(j < 0 ? 99 : j);
      });
    case QuoteGroup.month:
      keys.sort((a, b) => b.compareTo(a));
    default:
      keys.sort((a, b) {
        final c = lastIfEmpty(a, b);
        return c != 0 ? c : a.toLowerCase().compareTo(b.toLowerCase());
      });
  }
  return [for (final k in keys) QuoteSection(k, by[k]!)];
}

/// The names in a "who said it" field, each once, in the order typed.
List<String> speakerNamesOf(String speaker) {
  final seen = <String>{};
  return [
    for (final n in speaker.split(RegExp(r'\s*(?:,|;|/|&|\band\b)\s*')))
      if (n.trim().isNotEmpty && seen.add(n.trim().toLowerCase())) n.trim(),
  ];
}
