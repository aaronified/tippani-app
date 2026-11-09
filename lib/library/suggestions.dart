import 'models.dart';

/// The works whose characters count for [work]: the work itself and, when it belongs to a series, every work in that
/// series (so the third Harry Potter offers the characters of the second). A work with no series, or no work at all,
/// stands alone. The work comes first.
List<Work> seriesOf(Work? work, List<Work> all) {
  if (work == null) return const [];
  final series = work.details.series.trim().toLowerCase();
  if (series.isEmpty) return [work];
  return [
    work,
    for (final w in all)
      if (w.id != work.id &&
          w.kind == work.kind &&
          w.details.series.trim().toLowerCase() == series)
        w,
  ];
}

/// Chapters in reading order: those that begin with a number by that number ("2. Loomings" before "10. The Carpet-Bag"),
/// then the rest in the order they were first used.
List<String> sortChapters(List<String> chapters) {
  int? number(String c) {
    final m = RegExp(
      r'^\s*(?:chapter|ch\.?|part|book|act|scene|canto)?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(c);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  final indexed = [for (var i = 0; i < chapters.length; i++) (i, chapters[i])];
  indexed.sort((a, b) {
    final x = number(a.$2), y = number(b.$2);
    if (x != null && y != null) {
      final c = x.compareTo(y);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    }
    if (x != null) return -1;
    if (y != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// The languages to suggest: those already on the works in the library, then some common ones.
List<String> languageOptions(List<Work> works) {
  final seen = <String>{};
  final out = <String>[];
  void add(String l) {
    final t = l.trim();
    if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
  }

  for (final w in works) {
    add(w.language);
  }
  for (final l in const [
    'en',
    'bn',
    'hi',
    'ur',
    'sa',
    'ar',
    'fa',
    'fr',
    'de',
    'es',
    'it',
    'pt',
    'ru',
    'ja',
    'zh',
    'ko',
    'la',
    'el',
  ]) {
    add(l);
  }
  return out;
}

/// The people to suggest for a work's credit: the server's people of the kinds that suit the kind of work, then the
/// credits already on works of that kind in the library.
List<String> creditOptions(
  WorkKind kind,
  List<Work> works,
  List<String> Function(String kind) serverNames,
) {
  final kinds = switch (kind) {
    WorkKind.book => const ['author', 'translator', 'editor'],
    WorkKind.film => const ['director', 'author'],
    WorkKind.show => const ['director', 'author'],
    WorkKind.game => const ['studio', 'publisher'],
    WorkKind.other => const ['author', 'director', 'studio'],
  };
  final seen = <String>{};
  final out = <String>[];
  void add(String n) {
    final t = n.trim();
    if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
  }

  for (final w in works) {
    if (w.kind == kind) {
      for (final n in w.creator.split(RegExp(r'\s*[,;&/]\s*'))) {
        add(n);
      }
    }
  }
  for (final k in kinds) {
    for (final n in serverNames(k)) {
      add(n);
    }
  }
  return out;
}
