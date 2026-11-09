/// The ways a quote can be added, one for each kind the app and the server keep.
enum AddKind {
  /// A line from a book, as an annotation.
  book,

  /// A line from a film, show or game, as a dialogue.
  screen,

  /// A quote from anywhere else, with no work behind it.
  loose,

  /// A page photographed, its words read.
  scan,

  /// Words spoken, written down.
  voice,

  /// A file brought in: Kindle clippings, Markdown.
  file,
}
