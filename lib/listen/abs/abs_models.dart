/// What an Audiobookshelf (ABS) server says, kept to the fields the app uses.
///
/// Every reader is forgiving: ABS adds fields between releases and leaves others null, so a missing or
/// oddly typed field becomes an empty value instead of an error.
library;

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
double _dbl(Object? v) => v is num ? v.toDouble() : 0;
String _s(Object? v) => v == null ? '' : '$v';
Map<String, Object?> _map(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const {};
List<Object?> _list(Object? v) => v is List ? v : const [];

/// `GET /status`: what the server is and how a person may sign in. Needs no credential.
class AbsStatus {
  const AbsStatus({
    required this.version,
    required this.authMethods,
    this.initialised = true,
    this.openIdButtonText = '',
    this.openIdAutoLaunch = false,
  });

  final String version;

  /// `local`, `openid`, or both.
  final List<String> authMethods;
  final bool initialised;
  final String openIdButtonText;
  final bool openIdAutoLaunch;

  bool get hasPassword => authMethods.contains('local');
  bool get hasOpenId => authMethods.contains('openid');

  static AbsStatus fromJson(Object? j) {
    final m = _map(j);
    final form = _map(m['authFormData']);
    return AbsStatus(
      version: _s(m['serverVersion']),
      authMethods: [for (final x in _list(m['authMethods'])) _s(x)],
      initialised: m['isInit'] != false,
      openIdButtonText: _s(form['authOpenIDButtonText']),
      openIdAutoLaunch: form['authOpenIDAutoLaunch'] == true,
    );
  }
}

/// The pair of tokens ABS issues, and who they belong to. A credential: never log it.
class AbsTokens {
  const AbsTokens({
    required this.access,
    required this.refresh,
    required this.userId,
    required this.username,
    this.isRoot = false,
  });

  final String access, refresh, userId, username;
  final bool isRoot;

  /// Reads a login or refresh answer. ABS puts the tokens on the `user` object; a bare object is accepted too.
  static AbsTokens? fromJson(Object? j, {AbsTokens? previous}) {
    final root = _map(j);
    final user = root['user'] is Map ? _map(root['user']) : root;
    final access = _s(user['accessToken']);
    if (access.isEmpty) return null;
    final refresh = _s(user['refreshToken']);
    return AbsTokens(
      access: access,
      // A refresh answer that carries no new refresh token keeps the one we had.
      refresh: refresh.isNotEmpty ? refresh : (previous?.refresh ?? ''),
      userId: _s(user['id']).isNotEmpty
          ? _s(user['id'])
          : (previous?.userId ?? ''),
      username: _s(user['username']).isNotEmpty
          ? _s(user['username'])
          : (previous?.username ?? ''),
      isRoot: user['type'] != null
          ? _s(user['type']) == 'root'
          : (previous?.isRoot ?? false),
    );
  }

  Map<String, Object?> toJson() => {
    'access': access,
    'refresh': refresh,
    'userId': userId,
    'username': username,
    'isRoot': isRoot,
  };

  static AbsTokens? fromStored(Object? j) {
    final m = _map(j);
    if (_s(m['access']).isEmpty) return null;
    return AbsTokens(
      access: _s(m['access']),
      refresh: _s(m['refresh']),
      userId: _s(m['userId']),
      username: _s(m['username']),
      isRoot: m['isRoot'] == true,
    );
  }
}

class AbsLibrary {
  const AbsLibrary({
    required this.id,
    required this.name,
    required this.mediaType,
  });
  final String id, name, mediaType;

  bool get isBooks => mediaType == 'book';

  static AbsLibrary fromJson(Object? j) {
    final m = _map(j);
    return AbsLibrary(
      id: _s(m['id']),
      name: _s(m['name']),
      mediaType: _s(m['mediaType']),
    );
  }
}

/// A chapter, in seconds from the start of the whole book.
class AbsChapter {
  const AbsChapter({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });
  final int id;
  final String title;
  final double start, end;

  static AbsChapter fromJson(Object? j) {
    final m = _map(j);
    return AbsChapter(
      id: _int(m['id']),
      title: _s(m['title']),
      start: _dbl(m['start']),
      end: _dbl(m['end']),
    );
  }
}

/// One audio file of a book. [offset] is where it starts in the whole book.
class AbsTrack {
  const AbsTrack({
    required this.index,
    required this.contentUrl,
    required this.mimeType,
    required this.offset,
    required this.duration,
  });
  final int index;

  /// A path on the server, to be streamed with the access token in an `Authorization` header.
  final String contentUrl, mimeType;
  final double offset, duration;

  static AbsTrack fromJson(Object? j) {
    final m = _map(j);
    return AbsTrack(
      index: _int(m['index']),
      contentUrl: _s(m['contentUrl']),
      mimeType: _s(m['mimeType']),
      offset: _dbl(m['startOffset']),
      duration: _dbl(m['duration']),
    );
  }
}

/// A book in a library list: enough for a card, nothing that needs a second request.
class AbsBook {
  const AbsBook({
    required this.id,
    required this.libraryId,
    required this.title,
    required this.author,
    this.narrator = '',
    this.series = '',
    this.subtitle = '',
    this.asin = '',
    this.isbn = '',
    this.language = '',
    this.year = '',
    this.duration = 0,
    this.numChapters = 0,
    this.size = 0,
    this.addedAt = 0,
    this.updatedAt = 0,
  });

  final String id, libraryId, title, author, narrator, series, subtitle;
  final String asin, isbn, language, year;
  final double duration;
  final int numChapters, size, addedAt, updatedAt;

  static AbsBook fromJson(Object? j) {
    final m = _map(j);
    final media = _map(m['media']);
    final meta = _map(media['metadata']);
    return AbsBook(
      id: _s(m['id']),
      libraryId: _s(m['libraryId']),
      title: _s(meta['title']),
      subtitle: _s(meta['subtitle']),
      author: _s(meta['authorName']),
      narrator: _s(meta['narratorName']),
      series: _s(meta['seriesName']),
      asin: _s(meta['asin']),
      isbn: _s(meta['isbn']),
      language: _s(meta['language']),
      year: _s(meta['publishedYear']),
      duration: _dbl(media['duration']),
      numChapters: _int(media['numChapters']),
      size: _int(m['size']),
      addedAt: _int(m['addedAt']),
      updatedAt: _int(m['updatedAt']),
    );
  }
}

/// A page of books and how many there are in all.
class AbsBookPage {
  const AbsBookPage(this.books, this.total);
  final List<AbsBook> books;
  final int total;
}

/// A book with what playing it needs: its chapters and audio files.
class AbsBookDetail {
  const AbsBookDetail({
    required this.book,
    required this.chapters,
    required this.tracks,
  });
  final AbsBook book;
  final List<AbsChapter> chapters;
  final List<AbsTrack> tracks;

  static AbsBookDetail fromJson(Object? j) {
    final m = _map(j);
    final media = _map(m['media']);
    final tracks = [
      for (final t in _list(media['tracks'])) AbsTrack.fromJson(t),
    ];
    return AbsBookDetail(
      book: AbsBook.fromJson(m),
      chapters: [
        for (final c in _list(media['chapters'])) AbsChapter.fromJson(c),
      ],
      tracks: tracks,
    );
  }
}

class AbsBookmark {
  const AbsBookmark({
    required this.itemId,
    required this.time,
    required this.title,
    this.createdAt = 0,
  });
  final String itemId, title;

  /// Whole seconds into the book. ABS keys a bookmark by this, so two in one second collide.
  final int time;
  final int createdAt;

  static AbsBookmark fromJson(Object? j) {
    final m = _map(j);
    return AbsBookmark(
      itemId: _s(m['libraryItemId']),
      time: _int(m['time']),
      title: _s(m['title']),
      createdAt: _int(m['createdAt']),
    );
  }
}

/// Where a listener is in a book.
class AbsProgress {
  const AbsProgress({
    required this.itemId,
    required this.currentTime,
    required this.duration,
    required this.finished,
    this.lastUpdate = 0,
  });
  final String itemId;
  final double currentTime, duration;
  final bool finished;
  final int lastUpdate;

  static AbsProgress fromJson(Object? j) {
    final m = _map(j);
    return AbsProgress(
      itemId: _s(m['libraryItemId']),
      currentTime: _dbl(m['currentTime']),
      duration: _dbl(m['duration']),
      finished: m['isFinished'] == true,
      lastUpdate: _int(m['lastUpdate']),
    );
  }
}

/// `GET /api/me`: who this is, their bookmarks and where they are in each book.
class AbsMe {
  const AbsMe({
    required this.id,
    required this.username,
    required this.bookmarks,
    required this.progress,
  });
  final String id, username;
  final List<AbsBookmark> bookmarks;
  final List<AbsProgress> progress;

  static AbsMe fromJson(Object? j) {
    final m = _map(j);
    return AbsMe(
      id: _s(m['id']),
      username: _s(m['username']),
      bookmarks: [
        for (final b in _list(m['bookmarks'])) AbsBookmark.fromJson(b),
      ],
      progress: [
        for (final p in _list(m['mediaProgress'])) AbsProgress.fromJson(p),
      ],
    );
  }
}

/// An open play session: what to stream and where to start.
class AbsPlaySession {
  const AbsPlaySession({
    required this.id,
    required this.itemId,
    required this.startTime,
    required this.duration,
    required this.chapters,
    required this.tracks,
  });
  final String id, itemId;
  final double startTime, duration;
  final List<AbsChapter> chapters;
  final List<AbsTrack> tracks;

  static AbsPlaySession fromJson(Object? j) {
    final m = _map(j);
    return AbsPlaySession(
      id: _s(m['id']),
      itemId: _s(m['libraryItemId']),
      startTime: _dbl(m['startTime']),
      duration: _dbl(m['duration']),
      chapters: [for (final c in _list(m['chapters'])) AbsChapter.fromJson(c)],
      tracks: [for (final t in _list(m['audioTracks'])) AbsTrack.fromJson(t)],
    );
  }
}
