import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../l10n/l10n.dart';

/// One picture that could be a work's cover or poster, and where it came from.
class CoverOption {
  const CoverOption({required this.url, required this.source, this.thumb = ''});

  final String url;
  final String source;

  /// A smaller picture to show in the grid, when the supplier gave one.
  final String thumb;

  String get shown => thumb.isEmpty ? url : thumb;
}

/// What names a supplier in words.
String coverSourceName(String slug) =>
    {
      'google': tx('vocab.source.google.label'),
      'openlibrary': tx('vocab.source.openlibrary.label'),
      'amazon': 'Amazon',
      'tmdb': 'TMDB',
      'tvdb': 'TheTVDB',
      'igdb': 'IGDB',
      'wikidata': 'Wikidata',
      'google-images': tx('app.cover_search.web_images'),
      'images': tx('app.cover_search.web_images'),
    }[slug] ??
    (slug.isEmpty ? 'Web' : slug);

/// The largest picture the phone carries to the server as a cover (the server's own limit is 10 MB).
const maxCoverBytes = 10 * 1024 * 1024;

/// Finds pictures that could be a work's cover, by title, creator or ISBN, through the paired server (which asks
/// the catalogues and the picture suppliers), and brings a chosen one to the phone. An interface so a test can stand
/// in for the server and the internet.
abstract class CoverSearch {
  bool get available;

  Future<List<CoverOption>> find({
    required WorkKind kind,
    String title = '',
    String creator = '',
    String isbn = '',
    int? year,
  });

  /// The bytes of the picture at [url]; throws a [ServerException] (with words for the reader) when it cannot be had.
  Future<Uint8List> download(String url);
}

class PairedCoverSearch implements CoverSearch {
  PairedCoverSearch(this._controller, {http.Client? client})
    : _client = client ?? http.Client();

  final AppController _controller;
  final http.Client _client;

  @override
  bool get available => _controller.paired;

  @override
  Future<List<CoverOption>> find({
    required WorkKind kind,
    String title = '',
    String creator = '',
    String isbn = '',
    int? year,
  }) => serverCall(_controller, (c) async {
    final isBook = kind == WorkKind.book || kind == WorkKind.other;
    final out = <CoverOption>[];
    final seen = <String>{};
    void add(Object? url, String source, [Object? thumb]) {
      final u = url is String ? url.trim() : '';
      if (u.isEmpty || !seen.add(u)) return;
      out.add(
        CoverOption(
          url: u,
          source: coverSourceName(source),
          thumb: thumb is String ? thumb.trim() : '',
        ),
      );
    }

    // the catalogues' own art first
    final body = isBook
        ? {
            if (isbn.trim().isNotEmpty) 'isbn': isbn.trim(),
            if (title.trim().isNotEmpty) 'title': title.trim(),
            if (creator.trim().isNotEmpty) 'author': creator.trim(),
          }
        : {
            'title': title.trim(),
            'year': ?year,
            'media_type': switch (kind) {
              WorkKind.show => 'show',
              WorkKind.game => 'game',
              _ => 'movie',
            },
          };
    if (isBook ? body.isNotEmpty : title.trim().isNotEmpty) {
      final r = await c.postJson(
        isBook ? '/books/lookup' : '/movies/lookup',
        body,
      );
      final list = r is Map ? r['candidates'] : null;
      if (list is List) {
        for (final m in list) {
          if (m is! Map) continue;
          if (isBook) {
            final sources = m['sources'];
            final cover = sources is Map ? '${sources['cover'] ?? ''}' : '';
            final src = '${m['source'] ?? ''}';
            add(
              m['cover_url'],
              cover.isNotEmpty
                  ? cover
                  : (src == 'openlibrary' || src == 'amazon' ? src : 'google'),
            );
          } else {
            add(m['poster_url'], '${m['source'] ?? 'tmdb'}');
          }
        }
      }
    }

    // then the suppliers that search for pictures; a failure here is not worth an error over the covers above
    try {
      final p = await c.postJson('/images/search', {
        'kind': isBook ? 'cover' : 'poster',
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (creator.trim().isNotEmpty) 'author': creator.trim(),
        if (isbn.trim().isNotEmpty) 'isbn': isbn.trim(),
        'year': ?year,
        if (!isBook)
          'media_type': kind == WorkKind.show
              ? 'show'
              : (kind == WorkKind.game ? 'game' : 'movie'),
      });
      final images = p is Map ? p['images'] : null;
      if (images is List) {
        for (final im in images) {
          if (im is! Map) continue;
          final s = '${im['source'] ?? ''}';
          add(im['url'], s == 'google' ? 'google-images' : s, im['thumb']);
        }
      }
    } on Object {
      // the catalogues' answer stands
    }
    return out;
  });

  @override
  Future<Uint8List> download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const ServerException('That is not a picture address.');
    }
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw const ServerException('That picture could not be fetched.');
      }
      if (res.bodyBytes.length > maxCoverBytes) {
        throw const ServerException('That picture is over 10 MB.');
      }
      return res.bodyBytes;
    } on ServerException {
      rethrow;
    } on Object {
      throw const ServerException('That picture could not be fetched.');
    }
  }
}

/// Gives the screens below it the [CoverSearch].
class CoverSearchScope extends InheritedWidget {
  const CoverSearchScope({
    super.key,
    required this.search,
    required super.child,
  });

  final CoverSearch? search;

  static CoverSearch? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverSearchScope>()?.search;

  @override
  bool updateShouldNotify(CoverSearchScope old) => old.search != search;
}
