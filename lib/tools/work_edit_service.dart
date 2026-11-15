import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart';

/// What a reader changes about a work on the server from the phone: its cast rows now, and (as the work page
/// gains them) its details and its cover. Every write goes THROUGH to the server, which owns these, so the web and
/// the phone agree; a refusal throws a [ServerException] carrying the server's own words. An interface so a test
/// can stand in for the server.
abstract class WorkEditService {
  /// Whether the server can be asked right now (the phone is paired).
  bool get available;

  /// Pulls the cast from TheTVDB for a film or show. [tvdbId] names the record when the work has none yet.
  Future<void> fetchCastFromTvdb(Work work, {int? tvdbId});

  /// Pulls the cast from IMDb; [imdb] is a title link or a `tt…` id.
  Future<void> fetchCastFromImdb(Work work, String imdb);

  /// Adds one row to the work's cast. A book has characters and no [actor].
  Future<void> addCast(
    Work work, {
    required String character,
    String actor = '',
  });

  /// Corrects one row: both names are sent, as the server reads an edit without them as no edit.
  Future<void> editCast(int castId, {required String character, String actor});

  /// Takes the row off the list.
  Future<void> removeCast(int castId);

  /// The server's whole record for [work], as the edit form shows it (including what the page does not: its
  /// links and series number).
  Future<Map<String, Object?>> record(Work work);

  /// Has the server fetch [url] as the work's cover (its poster, for a film) and returns the name of the file it
  /// now holds. A link that is not a picture is refused in the server's words.
  Future<String> setCoverFromLink(Work work, String url);

  /// Takes the work's cover off on the server.
  Future<void> clearCover(Work work);

  /// What the server's catalogues (Google Books and Open Library, or TMDB, TheTVDB and IGDB) say [work] might be,
  /// found by its title, creator, year and ISBN.
  Future<List<SourceCandidate>> findSources(Work work);

  /// Links [work] to the catalogue entry [c] on the server, so its metadata can be fetched from there. A book only
  /// has its source ids pinned (its own fields stay as they are); a film or show is re-pulled from the source, as
  /// the web does.
  Future<void> linkSource(Work work, SourceCandidate c);

  /// Saves the details the form edits. The server REPLACES the whole record on a save, so this reads it fresh,
  /// puts the edited fields over it and sends it all back: nothing the phone does not show is lost.
  Future<void> saveDetails(Work work, WorkDetailsEdit edit);

  /// Keeps the character and takes the performer off it.
  Future<void> removeCastActor(int castId);
}

/// One catalogue entry a work might be, as the server's lookup offers it.
class SourceCandidate {
  const SourceCandidate({
    required this.source,
    required this.sourceId,
    required this.title,
    this.creator = '',
    this.year,
    this.cover = '',
    this.mediaType = '',
    this.tmdbId = 0,
    this.googleId = '',
    this.openLibraryId = '',
  });

  /// The catalogue ('google', 'openlibrary', 'tmdb', 'tvdb', 'igdb') and the work's id within it.
  final String source, sourceId;
  final String title;

  /// The author (books) where the catalogue gives one.
  final String creator;
  final int? year;

  /// A picture to show beside it, as an address ('' for none).
  final String cover;
  final String mediaType;
  final int tmdbId;
  final String googleId, openLibraryId;

  String get summary =>
      [if (creator.isNotEmpty) creator, if (year != null) '$year'].join(' · ');

  static SourceCandidate? fromJson(Object? j, {required bool book}) {
    if (j is! Map) return null;
    String s(String k) => j[k] is String ? (j[k] as String).trim() : '';
    final title = s('title');
    final source = s('source');
    final id = j['source_id'];
    final sourceId = id is String
        ? id.trim()
        : (id is num ? '${id.toInt()}' : '');
    if (title.isEmpty || source.isEmpty || sourceId.isEmpty) return null;
    final y = j[book ? 'published_year' : 'release_year'];
    final t = j['tmdb_id'];
    return SourceCandidate(
      source: source,
      sourceId: sourceId,
      title: title,
      creator: s('author'),
      year: y is int && y > 0 ? y : null,
      cover: s(book ? 'cover_url' : 'poster_url'),
      mediaType: s('media_type'),
      tmdbId: t is int ? t : 0,
      googleId: s('google_id'),
      openLibraryId: s('openlibrary_id'),
    );
  }
}

/// The details of a work a reader edits from the phone. A null field is one this kind of work does not have
/// (pages and ISBN on a film), and is left out of what is sent.
class WorkDetailsEdit {
  const WorkDetailsEdit({
    required this.description,
    required this.genres,
    required this.series,
    required this.seriesIndex,
    required this.links,
    this.publisher,
    this.subtitle,
    this.pages,
    this.isbn,
  });

  final String description;
  final List<String> genres;
  final String series;
  final double seriesIndex;
  final String links;
  final String? publisher, subtitle, isbn;
  final int? pages;
}

class PairedWorkEdit implements WorkEditService {
  PairedWorkEdit(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  String _route(Work w) => workRoute(realmOfKind(w.kind));

  int _id(Work w) => w.serverId ?? (throw const ServerException('not synced'));

  @override
  Future<void> fetchCastFromTvdb(Work work, {int? tvdbId}) => serverCall<void>(
    _controller,
    (c) async {
      await c.postJson('/movies/${_id(work)}/cast/tvdb', {'tvdb_id': ?tvdbId});
    },
  );

  @override
  Future<void> fetchCastFromImdb(Work work, String imdb) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/movies/${_id(work)}/cast/imdb', {'imdb': imdb});
      });

  @override
  Future<void> addCast(
    Work work, {
    required String character,
    String actor = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.postJson('${_route(work)}/${_id(work)}/cast', {
      'character': character,
      if (actor.isNotEmpty) 'actor': actor,
    });
  });

  @override
  Future<void> editCast(
    int castId, {
    required String character,
    String actor = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.putJson('/cast/$castId', {'character': character, 'actor': actor});
  });

  @override
  Future<void> removeCast(int castId) =>
      serverCall<void>(_controller, (c) async {
        await c.delete('/cast/$castId');
      });

  @override
  Future<Map<String, Object?>> record(Work work) =>
      serverCall<Map<String, Object?>>(_controller, (c) async {
        return asMap(await c.getJsonLive('${_route(work)}/${_id(work)}'));
      });

  /// The whole record with [over] written on it, sent back (the server replaces the record on a save), and the
  /// record the server answers with.
  Future<Map<String, Object?>> _overlay(Work work, Map<String, Object?> over) =>
      serverCall<Map<String, Object?>>(_controller, (c) async {
        final path = '${_route(work)}/${_id(work)}';
        final cur = asMap(await c.getJsonLive(path));
        final answer = await c.putJson(path, {...cur, ...over});
        return answer is Map ? Map<String, Object?>.from(answer) : {};
      });

  @override
  Future<void> saveDetails(Work work, WorkDetailsEdit edit) => _overlay(work, {
    'description': edit.description,
    'genres': edit.genres,
    'series': edit.series,
    'series_index': edit.seriesIndex,
    'links': edit.links,
    'publisher': ?edit.publisher,
    'subtitle': ?edit.subtitle,
    'pages': ?edit.pages,
    'isbn': ?edit.isbn,
  });

  String _coverName(Work work, Map<String, Object?> record) {
    final v = record[_route(work) == '/books' ? 'cover_path' : 'poster_path'];
    return v is String ? v : '';
  }

  @override
  Future<String> setCoverFromLink(Work work, String url) async => _coverName(
    work,
    await _overlay(work, {
      _route(work) == '/books' ? 'cover_url' : 'poster_url': url,
    }),
  );

  @override
  Future<void> clearCover(Work work) => _overlay(work, {'clear_cover': true});

  @override
  Future<List<SourceCandidate>> findSources(Work work) =>
      serverCall<List<SourceCandidate>>(_controller, (c) async {
        final book = _route(work) == '/books';
        final isbn = work.details.isbn;
        final body = asMap(
          book
              ? await c.postJson('/books/lookup', {
                  'title': work.title,
                  if (work.creator.trim().isNotEmpty)
                    'author': work.creator.trim(),
                  if (isbn.isNotEmpty) 'isbn': isbn,
                })
              : await c.postJson('/movies/lookup', {
                  'title': work.title,
                  if (work.year != null) 'year': work.year,
                  'media_type': switch (work.kind) {
                    WorkKind.show => 'show',
                    WorkKind.game => 'game',
                    _ => 'movie',
                  },
                }),
        );
        final all = body['candidates'];
        return [
          if (all is List)
            for (final x in all)
              if (SourceCandidate.fromJson(x, book: book) != null)
                SourceCandidate.fromJson(x, book: book)!,
        ];
      });

  @override
  Future<void> linkSource(Work work, SourceCandidate c) {
    if (_route(work) == '/books') {
      return _overlay(work, {
        'source': c.source,
        'source_id': c.sourceId,
        if (c.googleId.isNotEmpty) 'google_id': c.googleId,
        if (c.openLibraryId.isNotEmpty) 'openlibrary_id': c.openLibraryId,
      });
    }
    return serverCall<void>(_controller, (client) async {
      await client.putJson('/movies/${_id(work)}', {
        'source': c.source,
        // TheTVDB's id is its own; TMDB's is the number, where the candidate says it
        'source_id': c.source != 'tvdb' && c.tmdbId > 0
            ? '${c.tmdbId}'
            : c.sourceId,
        'media_type': c.mediaType.isNotEmpty
            ? c.mediaType
            : switch (work.kind) {
                WorkKind.show => 'show',
                WorkKind.game => 'game',
                _ => 'movie',
              },
      });
    });
  }

  @override
  Future<void> removeCastActor(int castId) =>
      serverCall<void>(_controller, (c) async {
        await c.delete('/cast/$castId/actor');
      });
}

/// Gives the work page the [WorkEditService] without every screen taking one.
class WorkEditScope extends InheritedWidget {
  const WorkEditScope({super.key, required this.service, required super.child});

  final WorkEditService? service;

  static WorkEditService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkEditScope>()?.service;

  @override
  bool updateShouldNotify(WorkEditScope old) => old.service != service;
}
