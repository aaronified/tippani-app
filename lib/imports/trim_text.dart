/// Splits a quote into sentences so a long transcript can be cut down to the part worth keeping.
///
/// A sentence ends at `.`, `!`, `?` or `…` (a run of them, and any closing quote or bracket straight after) that is
/// followed by white space or the end. Text with no such end is one sentence. This is a convenience for trimming and
/// not a grammar: "Mr. Gudd" splits after "Mr." and the reader can still edit the words by hand, so a wrong split costs
/// one extra tap and never loses a word. Every character of the input that is not white space survives in the output.
List<String> sentencesOf(String text) {
  final out = <String>[];
  final end = RegExp(r'[.!?…]+["”’)\]]*(?=\s|$)');
  var start = 0;
  for (final m in end.allMatches(text)) {
    final piece = text.substring(start, m.end).trim();
    if (piece.isNotEmpty) out.add(piece);
    start = m.end;
  }
  final rest = text.substring(start).trim();
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// Sentences [from] to [to], both included, joined with a single space.
String keepSentences(List<String> sentences, int from, int to) =>
    sentences.sublist(from, to + 1).join(' ');
