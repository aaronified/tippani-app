/// What kinds of work a quote can come from. A quote with no work is a standalone one (a proverb, a line
/// from a letter), which Tippani calls a quote and keeps on boards.
enum WorkKind { book, film, show, game, other }

WorkKind workKindOf(Object? name) {
  for (final k in WorkKind.values) {
    if (k.name == name) return k;
  }
  return WorkKind.other;
}

/// The colour categories a quote can wear. The names match Tippani's so a synced quote keeps its colour.
const quoteColors = ['yellow', 'green', 'blue', 'pink', 'orange', 'purple'];

/// A book, film, show or game the quotes come from.
class Work {
  const Work({
    required this.id,
    required this.kind,
    required this.title,
    required this.creator,
    required this.year,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.serverId,
    this.syncedHash,
    this.cover = '',
    this.details = const WorkDetails(),
  });

  final int id;
  final WorkKind kind;
  final String title;

  /// The author of a book, the director of a film, the studio of a game: whoever the reader would name.
  final String creator;
  final int? year;
  final String language;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// This work's id on the paired Tippani server, once it has been pushed there.
  final int? serverId;

  /// A fingerprint of what the phone and the server last agreed this work said (see `sync/fingerprint.dart`).
  /// Null until they have agreed once.
  final String? syncedHash;

  /// The name of this work's cover (or poster) file on the server, or '' when it has none. Read-only metadata:
  /// it is not part of what syncs, so a cover change is never a conflict.
  final String cover;

  /// What the server knows about the work beyond the few fields that sync: a description, genres, publisher,
  /// pages, ISBN, series and its cast. Read-only metadata fetched when the work's page is opened and kept for
  /// when the server is out of reach.
  final WorkDetails details;

  Work withDetails(WorkDetails d) => Work(
    id: id,
    kind: kind,
    title: title,
    creator: creator,
    year: year,
    language: language,
    createdAt: createdAt,
    updatedAt: updatedAt,
    serverId: serverId,
    syncedHash: syncedHash,
    cover: cover,
    details: d,
  );

  Work withCover(String name) => Work(
    id: id,
    kind: kind,
    title: title,
    creator: creator,
    year: year,
    language: language,
    createdAt: createdAt,
    updatedAt: updatedAt,
    serverId: serverId,
    syncedHash: syncedHash,
    cover: name,
    details: details,
  );

  Work withServerId(int? id) => Work(
    id: this.id,
    kind: kind,
    title: title,
    creator: creator,
    year: year,
    language: language,
    createdAt: createdAt,
    updatedAt: updatedAt,
    serverId: id,
    syncedHash: syncedHash,
    cover: cover,
    details: details,
  );

  Work withSyncedHash(String? hash) => Work(
    id: id,
    kind: kind,
    title: title,
    creator: creator,
    year: year,
    language: language,
    createdAt: createdAt,
    updatedAt: updatedAt,
    serverId: serverId,
    syncedHash: hash,
    cover: cover,
    details: details,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'creator': creator,
    'year': year,
    'language': language,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'server_id': serverId,
    'synced_hash': syncedHash,
    'cover': cover,
    'details': details.toJson(),
  };
}

/// A character in a work, and the actor who plays them (empty for a book).
class CastMember {
  const CastMember({required this.character, this.actor = ''});
  final String character;
  final String actor;

  Map<String, Object?> toJson() => {'character': character, 'actor': actor};

  static CastMember? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['character'], a = j['actor'];
    final character = c is String ? c.trim() : '';
    final actor = a is String ? a.trim() : '';
    if (character.isEmpty && actor.isEmpty) return null;
    return CastMember(character: character, actor: actor);
  }
}

/// The server's extra facts about a work. Every part may be empty.
class WorkDetails {
  const WorkDetails({
    this.description = '',
    this.genres = const [],
    this.publisher = '',
    this.pages = 0,
    this.isbn = '',
    this.subtitle = '',
    this.series = '',
    this.cast = const [],
    this.fetchedAt,
  });

  final String description;
  final List<String> genres;
  final String publisher;
  final int pages;
  final String isbn;
  final String subtitle;
  final String series;
  final List<CastMember> cast;

  /// When it was last fetched (null: never).
  final DateTime? fetchedAt;

  bool get isEmpty =>
      description.isEmpty &&
      genres.isEmpty &&
      publisher.isEmpty &&
      pages == 0 &&
      isbn.isEmpty &&
      subtitle.isEmpty &&
      series.isEmpty &&
      cast.isEmpty;

  WorkDetails copyWith({List<CastMember>? cast, DateTime? fetchedAt}) =>
      WorkDetails(
        description: description,
        genres: genres,
        publisher: publisher,
        pages: pages,
        isbn: isbn,
        subtitle: subtitle,
        series: series,
        cast: cast ?? this.cast,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );

  Map<String, Object?> toJson() => {
    'description': description,
    'genres': genres,
    'publisher': publisher,
    'pages': pages,
    'isbn': isbn,
    'subtitle': subtitle,
    'series': series,
    'cast': [for (final c in cast) c.toJson()],
    'fetched_at': fetchedAt?.toUtc().toIso8601String(),
  };

  /// Reads what [toJson] wrote, or anything shaped like the server's own record (a book's or a film's), leaving
  /// out whatever is not there. Never throws.
  factory WorkDetails.fromJson(Object? j) {
    if (j is! Map) return const WorkDetails();
    String s(String k) => j[k] is String ? (j[k] as String).trim() : '';
    final g = j['genres'];
    final c = j['cast'];
    final at = j['fetched_at'];
    return WorkDetails(
      description: s('description'),
      genres: [
        if (g is List)
          for (final x in g)
            if (x is String && x.trim().isNotEmpty) x.trim(),
      ],
      publisher: s('publisher'),
      pages: j['pages'] is int ? j['pages'] as int : 0,
      isbn: s('isbn'),
      subtitle: s('subtitle'),
      series: s('series'),
      cast: [
        if (c is List)
          for (final x in c)
            if (CastMember.fromJson(x) != null) CastMember.fromJson(x)!,
      ],
      fetchedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }
}

/// What a reader fills in to make or change a work.
class WorkDraft {
  const WorkDraft({
    required this.title,
    this.kind = WorkKind.book,
    this.creator = '',
    this.year,
    this.language = '',
  });

  final String title;
  final WorkKind kind;
  final String creator;
  final int? year;
  final String language;
}

/// A quote, kept on the phone. [workId] is null for a standalone quote.
class Quote {
  const Quote({
    required this.id,
    required this.workId,
    required this.text,
    required this.translation,
    required this.language,
    required this.speaker,
    required this.chapter,
    required this.location,
    required this.note,
    required this.color,
    required this.favorite,
    required this.notedAt,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    this.serverId,
    this.syncedHash,
    this.boardId,
  });

  final int id;
  final int? workId;
  final String text;
  final String translation;

  /// Free text, as on the server: "Bengali", "bn", "বাংলা". Read aloud and typography resolve it later.
  final String language;

  /// Who said it: a character, a person, a narrator.
  final String speaker;
  final String chapter;

  /// A page, a percent, a timestamp: whatever places the quote in its work.
  final String location;

  /// The reader's own margin note.
  final String note;
  final String color;
  final bool favorite;

  /// When the reader met the quote (as opposed to when it was typed in).
  final DateTime notedAt;

  /// `manual`, `capture`, `import`: where it came from.
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;

  /// This quote's id on the paired server, once pushed.
  final int? serverId;

  /// What the phone and the server last agreed this quote said; null until they have agreed once.
  final String? syncedHash;

  /// The board a standalone quote is filed on (null: none). A quote from a work is never on a board.
  final int? boardId;

  Quote withServerId(int? id) => Quote(
    id: this.id,
    workId: workId,
    text: text,
    translation: translation,
    language: language,
    speaker: speaker,
    chapter: chapter,
    location: location,
    note: note,
    color: color,
    favorite: favorite,
    notedAt: notedAt,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
    tags: tags,
    serverId: id,
    syncedHash: syncedHash,
    boardId: boardId,
  );

  Quote withSyncedHash(String? hash) => Quote(
    id: id,
    workId: workId,
    text: text,
    translation: translation,
    language: language,
    speaker: speaker,
    chapter: chapter,
    location: location,
    note: note,
    color: color,
    favorite: favorite,
    notedAt: notedAt,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
    tags: tags,
    serverId: serverId,
    syncedHash: hash,
    boardId: boardId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'work_id': workId,
    'text': text,
    'translation': translation,
    'language': language,
    'speaker': speaker,
    'chapter': chapter,
    'location': location,
    'note': note,
    'color': color,
    'favorite': favorite,
    'noted_at': notedAt.toUtc().toIso8601String(),
    'source': source,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'tags': tags,
    'server_id': serverId,
    'synced_hash': syncedHash,
    'board_id': boardId,
  };
}

/// A shelf for standalone quotes, to group and filter them by.
class Board {
  const Board({
    required this.id,
    required this.name,
    this.color = '',
    this.quotes = 0,
  });

  final int id;
  final String name;

  /// One of [quoteColors], or '' for none.
  final String color;

  /// How many quotes are filed on it.
  final int quotes;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color};
}

/// What a reader fills in to make or change a quote.
class QuoteDraft {
  const QuoteDraft({
    required this.text,
    this.workId,
    this.translation = '',
    this.language = '',
    this.speaker = '',
    this.chapter = '',
    this.location = '',
    this.note = '',
    this.color = 'yellow',
    this.favorite = false,
    this.notedAt,
    this.source = 'manual',
    this.tags = const [],
    this.boardId,
  });

  final String text;
  final int? workId;
  final String translation;
  final String language;
  final String speaker;
  final String chapter;
  final String location;
  final String note;
  final String color;
  final bool favorite;

  /// Null means now.
  final DateTime? notedAt;
  final String source;
  final List<String> tags;

  /// The board to file a standalone quote on. Ignored when [workId] is set.
  final int? boardId;
}

/// How many of each thing the library holds.
class LibraryCounts {
  const LibraryCounts({
    required this.works,
    required this.quotes,
    required this.favourites,
    required this.tags,
  });

  final int works;
  final int quotes;
  final int favourites;
  final int tags;
}
