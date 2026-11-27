/// One quote on one book, as the Tippani Markdown the server's importer reads, so a quote made on the phone can be sent
/// to the server's import queue to be looked at later instead of straight into the library.
///
/// THE FORMAT IS THE SERVER'S, READ FROM ITS PARSER (`importer/markdown.go`): frontmatter between `---` lines (`title`
/// is required; `author`, `language` and `isbn` are optional), a `## ` heading for the chapter, the words on `> ` lines,
/// and `- key: value` lines directly under them for `location`, `date`, `note` and `tags`. The importer collapses white
/// space inside a quote and ends it at a blank line, so the words are written as one line and nothing inside a value may
/// hold a line break.
///
/// A WORK ALREADY IN THE LIBRARY IS JOINED, NOT DUPLICATED, but only if the file names it the way the library does: the
/// server matches a staged book by ISBN or ASIN, or by its title and author exactly (letters' case aside). So the
/// caller passes the work's own `title`, `author` and `isbn`, the strings it already holds, and does not tidy them.
String bookQuoteMarkdown({
  required String title,
  required String text,
  String author = '',
  String language = '',
  String isbn = '',
  String chapter = '',
  String location = '',
  String note = '',
  List<String> tags = const [],
  DateTime? notedAt,
}) {
  final words = _line(text);
  if (_line(title).isEmpty) {
    throw ArgumentError.value(title, 'title', 'a book needs a title');
  }
  if (words.isEmpty) {
    throw ArgumentError.value(text, 'text', 'a quote needs words');
  }
  String binding(String key, String value) {
    final v = _line(value);
    return v.isEmpty ? '' : '- $key: $v\n';
  }

  String front(String key, String value) {
    final v = _line(value);
    return v.isEmpty ? '' : '$key: $v\n';
  }

  final day = notedAt?.toUtc();
  final cleanTags = [
    for (final t in tags)
      if (_line(t.replaceAll(',', ' ')).isNotEmpty)
        _line(t.replaceAll(',', ' ')),
  ];
  return '---\n'
      'type: book\n'
      '${front('title', title)}'
      '${front('author', author)}'
      '${front('language', language)}'
      '${front('isbn', isbn)}'
      '---\n\n'
      '${_line(chapter).isEmpty ? '' : '## ${_line(chapter)}\n\n'}'
      '> $words\n'
      '${binding('location', location)}'
      '${day == null ? '' : '- date: ${_day(day)}\n'}'
      '${binding('note', note)}'
      '${cleanTags.isEmpty ? '' : '- tags: ${cleanTags.join(', ')}\n'}';
}

/// The name a bookmark's file goes up under. The server names the queue's batch after the file, so a name that is
/// the same each time for one bookmark is what lets a retry see its own batch and send nothing.
String bookmarkFileName(String uuid) => 'bookmark-$uuid.md';

/// White space of every kind, runs of it included, as one space; none at either end.
String _line(String s) =>
    s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ');

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
