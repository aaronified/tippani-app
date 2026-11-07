import '../l10n/l10n.dart';

/// Which part of the library a search covers. Each is a value of the server's `scope` parameter.
enum SearchScope {
  all('all', 'Everything'),
  books('books', 'library.group.none.label'),
  movies('movies', 'app.search_models.films_and_shows'),
  highlights('annotations', 'bin.kind.annotation.plural'),
  lines('dialogues', 'bin.kind.dialogue.plural'),
  quotes('quotes', 'nav.tab.quotes.label');

  const SearchScope(this.param, this.label);
  final String param;
  final String label;

  bool get inBooks => this == all || this == SearchScope.books;
  bool get inMovies => this == all || this == SearchScope.movies;
  bool get inHighlights => this == all || this == SearchScope.highlights;
  bool get inLines => this == all || this == SearchScope.lines;
  bool get inStandalone => this == all || this == SearchScope.quotes;
}

/// A narrowing of a search: a [field] (the server's facet name) and the [value] it must have.
class SearchFacet {
  const SearchFacet(this.field, this.value);
  final String field;
  final String value;

  /// The facets the page offers, with the word each is called.
  static final fields = {
    'author': tx('common.field.author.label'),
    'director': tx('common.field.director.label'),
    'actor': tx('common.field.actor.label'),
    'character': tx('common.field.character.label'),
    'speaker': tx('common.field.speaker.label'),
    'tag': tx('common.field.tag.label'),
    'genre': tx('movies.group.genre.label'),
    'colour': tx('common.field.colour.label'),
    'language': tx('common.field.language.label'),
    'series': tx('common.field.series.label'),
  };

  String get label => '${fields[field] ?? field}: $value';

  @override
  bool operator ==(Object other) =>
      other is SearchFacet &&
      other.field == field &&
      other.value.toLowerCase() == value.toLowerCase();

  @override
  int get hashCode => Object.hash(field, value.toLowerCase());
}

/// A book, film, show or game found. [serverId] is its id on the server (null for a hit of the phone's own search,
/// which has [localId] instead).
class WorkHit {
  const WorkHit({
    this.serverId,
    this.localId,
    required this.title,
    this.creator = '',
    this.year,
    this.cover = '',
    this.screen = false,
    this.mediaType = '',
    this.genres = const [],
  });

  final int? serverId;
  final int? localId;
  final String title;
  final String creator;
  final int? year;

  /// The cover or poster file on the server, or ''.
  final String cover;
  final bool screen;

  /// For a film row: movie, show or game.
  final String mediaType;
  final List<String> genres;
}

/// A quote found: a highlight of a book, a line of a film or show, or a standalone quote.
class QuoteHit {
  const QuoteHit({
    this.serverId,
    this.localId,
    required this.text,
    this.translation = '',
    this.note = '',
    this.color = '',
    this.speaker = '',
    this.workTitle = '',
    this.credit = '',
    this.place = '',
    this.kind = QuoteHitKind.highlight,
  });

  final int? serverId;
  final int? localId;
  final String text;
  final String translation;
  final String note;
  final String color;

  /// Who said it: a character, a speaker.
  final String speaker;
  final String workTitle;

  /// The author, director or actor to credit.
  final String credit;

  /// A chapter, a timestamp or an occasion.
  final String place;
  final QuoteHitKind kind;

  /// The hit's own identity, so the same quote is not listed twice in a page.
  String get key =>
      '${kind.name}:${serverId ?? 'l${localId ?? text.hashCode}'}';
}

enum QuoteHitKind { highlight, line, standalone }

/// A person the search matched, and what they made or said.
class PersonGroup {
  const PersonGroup({
    required this.name,
    required this.role,
    this.works = const [],
    this.quotes = const [],
  });

  final String name;

  /// 'author', 'director', 'actor' or 'speaker'.
  final String role;
  final List<WorkHit> works;
  final List<QuoteHit> quotes;
}

/// A tag the search matched, with how many quotes wear it and a few of them.
class TagGroup {
  const TagGroup({
    required this.name,
    required this.count,
    this.quotes = const [],
  });

  final String name;
  final int count;
  final List<QuoteHit> quotes;
}

class GenreGroup {
  const GenreGroup({required this.name, this.works = const []});
  final String name;
  final List<WorkHit> works;
}

/// Everything one search found, in the sections the web page has.
class SearchResults {
  const SearchResults({
    this.works = const [],
    this.people = const [],
    this.characters = const [],
    this.tags = const [],
    this.genres = const [],
    this.notes = const [],
    this.quotes = const [],
    this.corrected = '',
    this.fromServer = false,
    this.fellBack = false,
  });

  /// Titles (and series) that matched.
  final List<WorkHit> works;

  /// Authors, directors, actors and speakers whose names matched.
  final List<PersonGroup> people;

  /// Characters named on a line, with their lines.
  final List<PersonGroup> characters;
  final List<TagGroup> tags;
  final List<GenreGroup> genres;

  /// Quotes whose note matched.
  final List<QuoteHit> notes;

  /// Quotes whose words (or translation) matched.
  final List<QuoteHit> quotes;

  /// The typo-corrected query these came from, when the words as typed found nothing.
  final String corrected;

  /// Whether the server answered (and so forgave typos), or this is what the phone found alone.
  final bool fromServer;

  /// The server was to be asked but could not be reached, so the phone searched instead.
  final bool fellBack;

  int get total =>
      works.length +
      people.length +
      characters.length +
      tags.length +
      genres.length +
      notes.length +
      quotes.length;

  bool get isEmpty => total == 0;

  SearchResults withFallback() => SearchResults(
    works: works,
    people: people,
    characters: characters,
    tags: tags,
    genres: genres,
    notes: notes,
    quotes: quotes,
    corrected: corrected,
    fromServer: false,
    fellBack: true,
  );
}

/// What a facet can be, from the reader's own library: the server's `/search/vocabulary` (or the phone's own lists).
class SearchVocabulary {
  const SearchVocabulary(this.byField);

  final Map<String, List<String>> byField;

  static const empty = SearchVocabulary({});

  List<String> of(String field) => byField[field] ?? const [];

  /// Values across every field that match [text], as facets, best first: a value that starts with the text before
  /// one that only contains it. At most [limit].
  List<SearchFacet> suggest(String text, {int limit = 6}) {
    final t = text.trim().toLowerCase();
    if (t.length < 2) return const [];
    final starts = <SearchFacet>[];
    final holds = <SearchFacet>[];
    for (final e in byField.entries) {
      for (final v in e.value) {
        final l = v.toLowerCase();
        if (l == t) continue;
        if (l.startsWith(t)) {
          starts.add(SearchFacet(e.key, v));
        } else if (l.contains(t)) {
          holds.add(SearchFacet(e.key, v));
        }
      }
    }
    return [...starts, ...holds].take(limit).toList();
  }
}

/// The words of a query, lower-cased, for marking where they match.
List<String> queryWords(String q) => [
  for (final w in q.toLowerCase().split(RegExp(r'[\s,;]+')))
    if (w.trim().length >= 2) w.trim(),
];

/// A query with `field:value` parts taken out: what is left of the words, and the facets found. A value with spaces
/// may be quoted (`author:"Le Guin"`). Unknown field names are left in the words.
({String words, List<SearchFacet> facets}) parseQuery(String q) {
  final facets = <SearchFacet>[];
  final rest = q.replaceAllMapped(
    RegExp(r'''\b([a-z]+):(?:"([^"]+)"|(\S+))''', caseSensitive: false),
    (m) {
      final field = _alias(m.group(1)!.toLowerCase());
      if (!SearchFacet.fields.containsKey(field)) return m.group(0)!;
      facets.add(SearchFacet(field, (m.group(2) ?? m.group(3))!));
      return '';
    },
  );
  return (words: rest.replaceAll(RegExp(r'\s+'), ' ').trim(), facets: facets);
}

String _alias(String f) => switch (f) {
  'color' => 'colour',
  'tags' => 'tag',
  'authors' => 'author',
  _ => f,
};
