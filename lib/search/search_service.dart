import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/quote_chips.dart' show creditNames;
import 'search_models.dart';

/// Search on the paired server: it forgives typos, reads the credit and tag columns, and knows the whole library.
/// An interface so a test can stand in for it.
abstract class ServerSearch {
  /// Whether there is a paired server to ask.
  bool get available;

  Future<SearchResults> search(
    String words, {
    SearchScope scope = SearchScope.all,
    List<SearchFacet> facets = const [],
  });

  /// What each facet can be, from the reader's own library.
  Future<SearchVocabulary> vocabulary();
}

class PairedSearch implements ServerSearch {
  PairedSearch(this._controller);
  final AppController _controller;

  @override
  bool get available => _controller.paired;

  @override
  Future<SearchResults> search(
    String words, {
    SearchScope scope = SearchScope.all,
    List<SearchFacet> facets = const [],
  }) => serverCall(_controller, (c) async {
    final params = <String>[
      'q=${Uri.encodeQueryComponent(words)}',
      'scope=${scope.param}',
      'limit=40',
      for (final f in facets) '${f.field}=${Uri.encodeQueryComponent(f.value)}',
    ];
    final body = asMap(await c.getJson('/search?${params.join('&')}'));
    return parseServerSearch(body);
  });

  @override
  Future<SearchVocabulary> vocabulary() => serverCall(_controller, (c) async {
    final body = asMap(await c.getJson('/search/vocabulary'));
    List<String> list(String key) => [
      if (body[key] is List)
        for (final v in body[key] as List)
          if (v is String && v.isNotEmpty) v,
    ];
    return SearchVocabulary({
      'tag': list('tags'),
      'genre': list('genres'),
      'series': list('series'),
      'author': list('authors'),
      'director': list('directors'),
      'actor': list('actors'),
      'character': list('characters'),
      'speaker': list('speakers'),
      'language': list('languages'),
      'colour': const ['yellow', 'green', 'blue', 'pink', 'orange', 'purple'],
    });
  });
}

String _s(Object? v) => v is String ? v : '';
int? _i(Object? v) => v is num && v != 0 ? v.toInt() : null;
List<Map<String, Object?>> _rows(Object? v) => [
  if (v is List)
    for (final r in v)
      if (r is Map) Map<String, Object?>.from(r),
];
List<String> _strs(Object? v) => [
  if (v is List)
    for (final g in v)
      if (g is String) g,
];

WorkHit _book(Map<String, Object?> b) => WorkHit(
  serverId: _i(b['id']),
  title: _s(b['title']),
  creator: _s(b['author']),
  year: _i(b['published_year']),
  cover: _s(b['cover_path']),
  genres: _strs(b['genres']),
);

WorkHit _movie(Map<String, Object?> m) => WorkHit(
  serverId: _i(m['id']),
  title: _s(m['title']),
  creator: _s(m['director']),
  year: _i(m['release_year']),
  cover: _s(m['poster_path']),
  screen: true,
  mediaType: _s(m['media_type']),
  genres: _strs(m['genres']),
);

QuoteHit _highlight(Map<String, Object?> a) => QuoteHit(
  serverId: _i(a['id']),
  text: _s(a['quote']),
  translation: _s(a['translation']),
  note: _s(a['note']),
  color: _s(a['color']),
  speaker: _s(a['character']),
  workTitle: _s(a['book_title']),
  credit: _s(a['book_author']),
);

QuoteHit _line(Map<String, Object?> d) => QuoteHit(
  serverId: _i(d['id']),
  text: _s(d['quote']),
  translation: _s(d['translation']),
  note: _s(d['note']),
  color: _s(d['color']),
  speaker: _s(d['character']),
  workTitle: _s(d['movie_title']),
  credit: _s(d['actor']).isNotEmpty ? _s(d['actor']) : _s(d['movie_director']),
  place: _s(d['timestamp']),
  kind: QuoteHitKind.line,
);

QuoteHit _standalone(Map<String, Object?> u) => QuoteHit(
  serverId: _i(u['id']),
  text: _s(u['quote']),
  translation: _s(u['translation']),
  note: _s(u['note']),
  color: _s(u['color']),
  speaker: _s(u['speaker']),
  workTitle: _s(u['work_title']),
  place: _s(u['occasion']),
  kind: QuoteHitKind.standalone,
);

/// Reads the server's sectioned search answer (`GET /search`) into the page's sections.
SearchResults parseServerSearch(Map<String, Object?> j) {
  final works = <WorkHit>[
    for (final b in _rows(j['books'])) _book(b),
    for (final m in _rows(j['movies'])) _movie(m),
  ];
  final people = <PersonGroup>[
    for (final a in _rows(j['authors']))
      PersonGroup(
        name: _s(a['name']),
        role: 'author',
        works: [for (final b in _rows(a['books'])) _book(b)],
      ),
    for (final a in _rows(j['directors']))
      PersonGroup(
        name: _s(a['name']),
        role: 'director',
        works: [for (final m in _rows(a['movies'])) _movie(m)],
      ),
    for (final a in _rows(j['actors']))
      PersonGroup(
        name: _s(a['name']),
        role: 'actor',
        quotes: [for (final d in _rows(a['dialogues'])) _line(d)],
      ),
    for (final a in _rows(j['speakers']))
      PersonGroup(
        name: _s(a['name']),
        role: 'speaker',
        quotes: [for (final u in _rows(a['quotes'])) _standalone(u)],
      ),
  ];
  final characters = [
    for (final c in _rows(j['characters']))
      PersonGroup(
        name: _s(c['name']),
        role: 'character',
        quotes: [for (final d in _rows(c['dialogues'])) _line(d)],
      ),
  ];
  final tags = [
    for (final t in _rows(j['tags']))
      TagGroup(
        name: _s(t['name']),
        count: _i(t['count']) ?? 0,
        quotes: [
          for (final a in _rows(t['annotations'])) _highlight(a),
          for (final d in _rows(t['dialogues'])) _line(d),
          for (final u in _rows(t['quotes'])) _standalone(u),
        ],
      ),
  ];
  final genres = [
    for (final g in _rows(j['genres']))
      GenreGroup(
        name: _s(g['name']),
        works: [
          for (final b in _rows(g['books'])) _book(b),
          for (final m in _rows(g['movies'])) _movie(m),
        ],
      ),
  ];
  final notes = j['notes'] is Map
      ? Map<String, Object?>.from(j['notes'] as Map)
      : const <String, Object?>{};
  return SearchResults(
    works: works,
    people: people,
    characters: characters,
    tags: tags,
    genres: genres,
    notes: [
      for (final a in _rows(notes['annotations'])) _highlight(a),
      for (final d in _rows(notes['dialogues'])) _line(d),
      for (final u in _rows(notes['quotes'])) _standalone(u),
    ],
    quotes: [
      for (final a in _rows(j['annotations'])) _highlight(a),
      for (final d in _rows(j['dialogues'])) _line(d),
      for (final u in _rows(j['quotes'])) _standalone(u),
    ],
    corrected: _s(j['corrected']),
    fromServer: true,
  );
}

/// Search on the phone's own library: no typo forgiveness, but it works with no server. It reads titles, creators,
/// the words, translation, note, speaker and tags of what is on the phone.
class LocalSearch {
  LocalSearch(this.store);
  final LibraryStore store;

  bool _hasFacet(List<SearchFacet> fs, String f) => fs.any((x) => x.field == f);

  bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  bool _credited(String credit, String name) =>
      creditNames(credit).any((n) => _same(n, name)) || _same(credit, name);

  Future<SearchResults> search(
    String words, {
    SearchScope scope = SearchScope.all,
    List<SearchFacet> facets = const [],
  }) async {
    final all = await store.works();
    final byId = {for (final w in all) w.id: w};
    final q = words.trim();

    bool workOk(Work w) {
      for (final f in facets) {
        switch (f.field) {
          case 'author' || 'director':
            if (!_credited(w.creator, f.value)) return false;
          case 'language':
            if (!_same(w.language, f.value)) return false;
          // the phone keeps no genres or series of its own
          case 'genre' || 'series':
            return false;
        }
      }
      return true;
    }

    bool quoteOk(Quote qu) {
      final w = byId[qu.workId];
      for (final f in facets) {
        switch (f.field) {
          case 'author' || 'director':
            if (w == null || !_credited(w.creator, f.value)) return false;
          case 'tag':
            if (!qu.tags.any((t) => _same(t, f.value))) return false;
          case 'colour':
            if (!_same(qu.color, f.value)) return false;
          case 'speaker' || 'character' || 'actor':
            if (!creditNames(qu.speaker).any((n) => _same(n, f.value))) {
              return false;
            }
          case 'language':
            if (!_same(qu.language, f.value)) return false;
          case 'genre' || 'series':
            return false;
        }
      }
      return true;
    }

    final worksOut = <WorkHit>[];
    if ((scope.inBooks || scope.inMovies) && !_hasFacet(facets, 'tag')) {
      for (final w in await store.works(query: q)) {
        final screen =
            w.kind == WorkKind.film ||
            w.kind == WorkKind.show ||
            w.kind == WorkKind.game;
        if (screen ? !scope.inMovies : !scope.inBooks) continue;
        if (!workOk(w)) continue;
        worksOut.add(
          WorkHit(
            localId: w.id,
            title: w.title,
            creator: w.creator,
            year: w.year,
            cover: w.cover,
            screen: screen,
            mediaType: w.kind.name,
          ),
        );
      }
    }

    final quotesOut = <QuoteHit>[];
    final notesOut = <QuoteHit>[];
    final lower = q.toLowerCase();
    if (scope.inHighlights || scope.inLines || scope.inStandalone) {
      for (final qu in await store.quotes(query: q, limit: 1 << 30)) {
        final w = byId[qu.workId];
        final screen =
            w != null &&
            (w.kind == WorkKind.film ||
                w.kind == WorkKind.show ||
                w.kind == WorkKind.game);
        final kind = w == null
            ? QuoteHitKind.standalone
            : screen
            ? QuoteHitKind.line
            : QuoteHitKind.highlight;
        final inScope = switch (kind) {
          QuoteHitKind.highlight => scope.inHighlights,
          QuoteHitKind.line => scope.inLines,
          QuoteHitKind.standalone => scope.inStandalone,
        };
        if (!inScope || !quoteOk(qu)) continue;
        final hit = QuoteHit(
          localId: qu.id,
          text: qu.text,
          translation: qu.translation,
          note: qu.note,
          color: qu.color,
          speaker: qu.speaker,
          workTitle: w?.title ?? '',
          credit: w?.creator ?? '',
          place: qu.chapter.isNotEmpty ? qu.chapter : qu.location,
          kind: kind,
        );
        // a note match is shown under Notes when that is all that matched
        final inWords =
            lower.isEmpty ||
            qu.text.toLowerCase().contains(lower) ||
            qu.translation.toLowerCase().contains(lower);
        if (inWords) {
          quotesOut.add(hit);
        } else if (qu.note.toLowerCase().contains(lower)) {
          notesOut.add(hit);
        } else {
          quotesOut.add(hit);
        }
      }
    }

    final people = <PersonGroup>[];
    final tags = <TagGroup>[];
    if (lower.length >= 2 && facets.isEmpty) {
      // authors and directors whose name matches
      final seen = <String>{};
      for (final w in all) {
        for (final n in creditNames(w.creator)) {
          if (!n.toLowerCase().contains(lower) || !seen.add(n.toLowerCase())) {
            continue;
          }
          final screen =
              w.kind == WorkKind.film ||
              w.kind == WorkKind.show ||
              w.kind == WorkKind.game;
          people.add(
            PersonGroup(
              name: n,
              role: screen ? 'director' : 'author',
              works: [
                for (final x in all)
                  if (creditNames(x.creator).any((c) => _same(c, n)))
                    WorkHit(
                      localId: x.id,
                      title: x.title,
                      creator: x.creator,
                      year: x.year,
                      cover: x.cover,
                      screen:
                          x.kind == WorkKind.film ||
                          x.kind == WorkKind.show ||
                          x.kind == WorkKind.game,
                    ),
              ],
            ),
          );
        }
      }
      for (final t in await store.tags()) {
        if (!t.toLowerCase().contains(lower)) continue;
        final withTag = await store.quotes(tag: t, limit: 1 << 30);
        tags.add(
          TagGroup(
            name: t,
            count: withTag.length,
            quotes: [
              for (final qu in withTag.take(5))
                QuoteHit(
                  localId: qu.id,
                  text: qu.text,
                  color: qu.color,
                  speaker: qu.speaker,
                  workTitle: byId[qu.workId]?.title ?? '',
                  kind: qu.workId == null
                      ? QuoteHitKind.standalone
                      : QuoteHitKind.highlight,
                ),
            ],
          ),
        );
      }
    }
    return SearchResults(
      works: worksOut,
      people: people,
      tags: tags,
      notes: notesOut,
      quotes: quotesOut,
    );
  }

  /// What the facets can be, from what is on the phone.
  Future<SearchVocabulary> vocabulary() async {
    final works = await store.works();
    final quotes = await store.quotes(limit: 1 << 30);
    List<String> sorted(Iterable<String> v) {
      final seen = <String>{};
      final out = [
        for (final s in v)
          if (s.trim().isNotEmpty && seen.add(s.toLowerCase())) s.trim(),
      ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return out;
    }

    bool screen(Work w) =>
        w.kind == WorkKind.film ||
        w.kind == WorkKind.show ||
        w.kind == WorkKind.game;
    return SearchVocabulary({
      'tag': await store.tags(),
      'author': sorted([
        for (final w in works)
          if (!screen(w)) ...creditNames(w.creator),
      ]),
      'director': sorted([
        for (final w in works)
          if (screen(w)) ...creditNames(w.creator),
      ]),
      'speaker': sorted([for (final q in quotes) ...creditNames(q.speaker)]),
      'language': sorted([
        for (final q in quotes) q.language,
        for (final w in works) w.language,
      ]),
      'colour': const ['yellow', 'green', 'blue', 'pink', 'orange', 'purple'],
    });
  }
}

/// Gives the screens below it the [ServerSearch], so the search page can ask the server without taking one.
class ServerSearchScope extends InheritedWidget {
  const ServerSearchScope({
    super.key,
    required this.service,
    required super.child,
  });

  final ServerSearch? service;

  static ServerSearch? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServerSearchScope>()?.service;

  @override
  bool updateShouldNotify(ServerSearchScope old) => old.service != service;
}
