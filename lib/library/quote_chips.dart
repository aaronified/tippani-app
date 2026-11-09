import '../account/prefs_effects.dart';
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
  const QuoteChip(this.kind, this.name, [this.actor = '', this.image = '']);

  final ChipKind kind;
  final String name;

  /// The actor who plays this character, or '' when the work's cast does not say.
  final String actor;

  /// The picture the work's cast gives this chip (a character's, or failing that the actor's); '' when it gives none.
  final String image;

  @override
  bool operator ==(Object other) =>
      other is QuoteChip &&
      other.kind == kind &&
      other.name == name &&
      other.actor == actor &&
      other.image == image;

  @override
  int get hashCode => Object.hash(kind, name, actor, image);
}

/// A chip was pressed: show the library for this name.
class ChipFilter {
  const ChipFilter(this.name);
  final String name;
}

String _fold(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The names in a "who said it" field: one, or several where the reader typed an ensemble ("Rick, Ilsa and Victor"),
/// in the order typed, each once.
List<String> speakerNames(String speaker) =>
    _names(speaker, PrefsEffects.creditPattern(slash: true));

/// The names in a credit such as a book's author ("Pratchett & Gaiman"), split on the separators the reader chose.
List<String> creditNames(String credit) =>
    _names(credit, PrefsEffects.creditPattern());

List<String> _names(String s, RegExp pattern) {
  final seen = <String>{};
  return [
    for (final n in s.split(pattern))
      if (n.trim().isNotEmpty && seen.add(_fold(n))) n.trim(),
  ];
}

/// The chips for a quote, in the order the web app draws them: the author of a book first, then each named speaker.
/// A film's, show's or game's speaker is a character, and carries the actor when the work's cast lists that
/// character; a speaker anywhere else is just a person. A quote with neither has none.
List<QuoteChip> chipsFor(Quote q, Work? w, {bool omitAuthor = false}) {
  final out = <QuoteChip>[];
  final isBook =
      w != null && (w.kind == WorkKind.book || w.kind == WorkKind.other);
  if (isBook && !omitAuthor) {
    for (final n in creditNames(w.creator)) {
      out.add(QuoteChip(ChipKind.author, n));
    }
  }
  final screen = w != null && !isBook;
  final cast = {
    if (screen)
      for (final c in w.details.cast)
        if (c.character.isNotEmpty && c.actor.isNotEmpty)
          _fold(c.character): c.actor,
  };
  final faces = {
    if (w != null)
      for (final c in w.details.cast)
        if (c.character.isNotEmpty &&
            (c.characterImage.isNotEmpty || c.actorImage.isNotEmpty))
          _fold(c.character): c.characterImage.isNotEmpty
              ? c.characterImage
              : c.actorImage,
  };
  for (final n in speakerNames(q.speaker)) {
    final face = faces[_fold(n)] ?? '';
    out.add(
      screen
          ? QuoteChip(ChipKind.character, n, cast[_fold(n)] ?? '', face)
          : QuoteChip(ChipKind.speaker, n, '', face),
    );
  }
  return out;
}
