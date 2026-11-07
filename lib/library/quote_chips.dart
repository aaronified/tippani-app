import 'models.dart';

/// What a chip names.
enum ChipKind {
  /// The author of the book a quote is from.
  author,

  /// Someone who said a quote that is not from a work, or from a book.
  speaker,

  /// A character named as the speaker of a quote from a film, show or game; the actor who plays them, where the
  /// work's cast says, is its second line.
  character,
}

/// One chip on a quote: a name, and under it (for a character) the actor.
class QuoteChip {
  const QuoteChip(this.kind, this.name, [this.actor = '']);

  final ChipKind kind;
  final String name;

  /// The actor who plays this character, or '' when the work's cast does not say.
  final String actor;

  @override
  bool operator ==(Object other) =>
      other is QuoteChip &&
      other.kind == kind &&
      other.name == name &&
      other.actor == actor;

  @override
  int get hashCode => Object.hash(kind, name, actor);
}

/// A chip was pressed: show the library for this name.
class ChipFilter {
  const ChipFilter(this.name);
  final String name;
}

String _fold(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

final _separators = RegExp(r'\s*(?:,|;|/|&|\band\b)\s*', caseSensitive: false);

/// The names in a "who said it" field: one, or several where the reader typed an ensemble ("Rick, Ilsa and Victor"),
/// in the order typed, each once.
List<String> speakerNames(String speaker) {
  final seen = <String>{};
  return [
    for (final n in speaker.split(_separators))
      if (n.trim().isNotEmpty && seen.add(_fold(n))) n.trim(),
  ];
}

/// The chips for a quote, in the order the web app draws them: the author of a book first, then each named speaker.
/// A film's, show's or game's speaker is a character, and carries the actor when the work's cast lists that
/// character; a speaker anywhere else is just a person. A quote with neither has none.
List<QuoteChip> chipsFor(Quote q, Work? w) {
  final out = <QuoteChip>[];
  final isBook =
      w != null && (w.kind == WorkKind.book || w.kind == WorkKind.other);
  if (isBook && w.creator.trim().isNotEmpty) {
    out.add(QuoteChip(ChipKind.author, w.creator.trim()));
  }
  final screen = w != null && !isBook;
  final cast = {
    if (screen)
      for (final c in w.details.cast)
        if (c.character.isNotEmpty && c.actor.isNotEmpty)
          _fold(c.character): c.actor,
  };
  for (final n in speakerNames(q.speaker)) {
    out.add(
      screen
          ? QuoteChip(ChipKind.character, n, cast[_fold(n)] ?? '')
          : QuoteChip(ChipKind.speaker, n),
    );
  }
  return out;
}
