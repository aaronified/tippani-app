import 'models.dart';

/// Who and what a quote is from, on one line: "Thoreau, Walden (Henry David Thoreau), Economy, p. 8". Parts
/// that are empty are left out, and nothing is invented for them.
String quoteAttribution(Quote q, Work? w) {
  final from = w == null
      ? ''
      : (w.creator.trim().isEmpty ? w.title : '${w.title} (${w.creator})');
  return [
    q.speaker,
    from,
    q.chapter,
    q.location,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
}

/// A quote as plain text to send to someone: the words in quotation marks, the translation under them if
/// there is one, then where it is from.
String quoteShareText(Quote q, Work? w) {
  final from = quoteAttribution(q, w);
  return [
    '“${q.text.trim()}”',
    if (q.translation.trim().isNotEmpty) q.translation.trim(),
    if (from.isNotEmpty) '— $from',
  ].join('\n');
}

/// A whole work as plain text to read or send: its title line, then each chapter's quotes in reading order.
/// [quotes] must already be in reading order. The translation and the reader's note are added only when asked for.
String workShareText(
  Work w,
  List<Quote> quotes, {
  bool translations = true,
  bool notes = false,
}) {
  final head = w.creator.trim().isEmpty ? w.title : '${w.title} — ${w.creator}';
  final out = StringBuffer(head);
  String? chapter;
  for (final q in quotes) {
    final c = q.chapter.trim();
    if (chapter != c) {
      chapter = c;
      if (c.isNotEmpty) out.write('\n\n$c');
    }
    out.write('\n\n“${q.text.trim()}”');
    if (q.location.trim().isNotEmpty) out.write(' (${q.location.trim()})');
    if (translations && q.translation.trim().isNotEmpty) {
      out.write('\n${q.translation.trim()}');
    }
    if (notes && q.note.trim().isNotEmpty)
      out.write('\nNote: ${q.note.trim()}');
  }
  return out.toString();
}
