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
