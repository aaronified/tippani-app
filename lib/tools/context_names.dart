/// A place in a text where a character is named: [start] to [end], for the character at [who] in the list the search was
/// given.
class NameSpan {
  const NameSpan(this.start, this.end, this.who);

  final int start, end, who;
}

/// Splits what the server sent for one side of a quote into its units: one paragraph (or, for a film, one subtitle line) per
/// line. Empty lines are dropped.
List<String> splitUnits(String text) => [
  for (final l in text.split(RegExp(r'\r?\n')))
    if (l.trim().isNotEmpty) l.trim(),
];

/// Where each of [names] is named in [text]. `names[i]` is every way character `i` is called (its name and its other
/// spellings). A name has to stand alone (a letter or digit on either side is no match), case does not matter, and when two
/// names overlap the longer wins ("Mr. Bennet" over "Bennet"), then the earlier. The spans come back in order and never
/// overlap.
List<NameSpan> findNames(String text, List<List<String>> names) {
  if (text.isEmpty) return const [];
  final all = <(String, int)>[];
  for (var i = 0; i < names.length; i++) {
    final seen = <String>{};
    for (final n in names[i]) {
      final t = n.trim();
      if (t.length < 2) continue;
      if (seen.add(t.toLowerCase())) all.add((t, i));
    }
  }
  all.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  final found = <NameSpan>[];
  for (final (name, who) in all) {
    final re = RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(name)}(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in re.allMatches(text)) {
      final clash = found.any((s) => m.start < s.end && s.start < m.end);
      if (!clash) found.add(NameSpan(m.start, m.end, who));
    }
  }
  found.sort((a, b) => a.start.compareTo(b.start));
  return found;
}
