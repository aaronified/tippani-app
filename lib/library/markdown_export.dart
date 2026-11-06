import 'models.dart';

/// The library as Tippani Markdown, the file the server's importer reads, so a library made on the phone can
/// be imported into a server later with nothing lost that the server keeps.
///
/// It follows the server's own exports (`export_handlers.go`, `export_quotes.go`): a book is a frontmatter
/// block (`type: book`, always written, because the importer routes on it) and quotes under `## chapter`
/// headings; a film, show or game says `type: movie|show|game` and has no headings; quotes that belong to no
/// work are one `type: quotes` block. A binding is written only when it has a value, and the default colour
/// (yellow) is left out, so a file mentions a colour only when one was chosen.
///
/// One file holds every work, one after another: the importer takes a multi-work file apart at each
/// frontmatter block.
String libraryMarkdown(List<Work> works, List<Quote> quotes) {
  final byWork = <int, List<Quote>>{};
  final loose = <Quote>[];
  for (final q in _inOrder(quotes)) {
    final id = q.workId;
    if (id == null) {
      loose.add(q);
    } else {
      (byWork[id] ??= []).add(q);
    }
  }
  final parts = <String>[];
  for (final w in works) {
    final its = byWork[w.id] ?? const <Quote>[];
    // A work with no quotes is not worth a file of its own: the importer would create an empty book.
    if (its.isEmpty) continue;
    parts.add(_work(w, its));
  }
  if (loose.isNotEmpty) parts.add(_standalone(loose));
  return parts.join('\n');
}

/// The order they were saved in, as the server writes them.
List<Quote> _inOrder(List<Quote> quotes) =>
    [...quotes]..sort((a, b) => a.id.compareTo(b.id));

String _work(Work w, List<Quote> quotes) {
  final isBook = w.kind == WorkKind.book || w.kind == WorkKind.other;
  final sb = StringBuffer();
  _frontmatter(sb, [
    ('title', w.title),
    (isBook ? 'author' : 'director', w.creator),
    ('language', w.language),
    ('year', w.year?.toString() ?? ''),
    (
      'type',
      isBook ? 'book' : (w.kind == WorkKind.film ? 'movie' : w.kind.name),
    ),
  ]);
  if (isBook) {
    _grouped(sb, quotes, (q) => q.chapter, (sb, q) {
      _binding(sb, 'character', q.speaker);
      _binding(sb, 'translation', q.translation);
      _binding(sb, 'language', q.language);
      _binding(sb, 'note', q.note);
      _colour(sb, q);
      _binding(sb, 'tags', q.tags.join(', '));
      _binding(sb, 'loc', q.location);
      _binding(sb, 'date', _day(q.notedAt));
      _favourite(sb, q);
    });
  } else {
    for (final q in quotes) {
      sb.write('\n');
      _block(sb, q, () {
        _binding(sb, 'character', q.speaker);
        _binding(sb, 'timestamp', q.location);
        _binding(sb, 'translation', q.translation);
        _binding(sb, 'language', q.language);
        _binding(sb, 'note', q.note);
        _colour(sb, q);
        _binding(sb, 'tags', q.tags.join(', '));
        _favourite(sb, q);
      });
    }
  }
  return sb.toString();
}

String _standalone(List<Quote> quotes) {
  final sb = StringBuffer();
  _frontmatter(sb, [('type', 'quotes')]);
  // The occasion is the heading, so it is not repeated as a binding. A quote with none (a proverb) goes
  // first: the parser gives a quote the heading above it.
  _grouped(sb, quotes, (q) => q.chapter, (sb, q) {
    _binding(sb, 'speaker', q.speaker);
    _binding(sb, 'place', q.location);
    _binding(sb, 'language', q.language);
    _binding(sb, 'translation', q.translation);
    _binding(sb, 'note', q.note);
    _colour(sb, q);
    _binding(sb, 'tags', q.tags.join(', '));
    _binding(sb, 'date', _day(q.notedAt));
    _favourite(sb, q);
  });
  return sb.toString();
}

void _grouped(
  StringBuffer sb,
  List<Quote> quotes,
  String Function(Quote) heading,
  void Function(StringBuffer, Quote) bindings,
) {
  final order = <String>[''];
  final groups = <String, List<Quote>>{};
  for (final q in quotes) {
    final h = _line(heading(q));
    if (h.isNotEmpty && !groups.containsKey(h)) order.add(h);
    (groups[h] ??= []).add(q);
  }
  for (final h in order) {
    final its = groups[h];
    if (its == null) continue;
    if (h.isNotEmpty) sb.write('\n## $h\n');
    for (final q in its) {
      sb.write('\n');
      _block(sb, q, () => bindings(sb, q));
    }
  }
}

void _block(StringBuffer sb, Quote q, void Function() bindings) {
  for (final line in q.text.split(RegExp(r'\r\n|\r|\n'))) {
    sb.write('> $line\n');
  }
  bindings();
}

void _frontmatter(StringBuffer sb, List<(String, String)> pairs) {
  sb.write('---\n');
  for (final (k, v) in pairs) {
    final value = _line(v);
    if (value.isNotEmpty) sb.write('$k: $value\n');
  }
  sb.write('---\n');
}

/// A binding is one line: whitespace inside the value is collapsed, as the importer expects.
void _binding(StringBuffer sb, String key, String value) {
  final v = _line(value);
  if (v.isNotEmpty) sb.write('- $key: $v\n');
}

void _colour(StringBuffer sb, Quote q) {
  if (q.color != 'yellow') _binding(sb, 'color', q.color);
}

void _favourite(StringBuffer sb, Quote q) {
  if (q.favorite) sb.write('- favorite: true\n');
}

String _line(String s) => s.trim().split(RegExp(r'\s+')).join(' ');

String _day(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}
