import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';
import '../l10n/l10n.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
String _s(Object? v) => v == null ? '' : '$v';
bool _b(Object? v) => v == true;

/// A work in the library with what the server could still find out about it.
class GapWork {
  const GapWork({
    required this.kind,
    required this.id,
    required this.title,
    this.creator = '',
    this.cover = '',
    this.lowRes = false,
    this.gaps = const [],
    this.quotes = 0,
    this.mediaType = '',
  });

  /// 'book' or 'movie' (a film, show or game).
  final String kind;
  final int id;
  final String title, creator, cover, mediaType;
  final bool lowRes;

  /// What is missing, as words: Cover, Author, Series, Year, Genre, Synopsis, Source, Cast, Director.
  final List<String> gaps;
  final int quotes;

  bool get isBook => kind == 'book';
}

/// Works that look like the same work saved twice.
class DuplicateWork {
  const DuplicateWork({
    required this.kind,
    required this.id,
    required this.title,
    this.creator = '',
    this.year = 0,
    this.hasCover = false,
    this.quotes = 0,
  });

  final String kind;
  final int id, year, quotes;
  final String title, creator;
  final bool hasCover;
}

/// One supplier's answer for a field.
class FieldAlt {
  const FieldAlt(this.source, this.value);
  final String source;
  final Object? value;
}

/// One field a check found different from what is stored.
class FieldDiff {
  const FieldDiff({
    required this.field,
    this.stored,
    this.fresh,
    this.source = '',
    this.alts = const [],
  });

  final String field;
  final Object? stored, fresh;
  final String source;
  final List<FieldAlt> alts;

  static FieldDiff? fromJson(Object? j) {
    if (j is! Map) return null;
    final field = _s(j['field']);
    if (field.isEmpty) return null;
    return FieldDiff(
      field: field,
      stored: j['stored'],
      fresh: j['fresh'],
      source: _s(j['source']),
      alts: [
        if (j['alts'] is List)
          for (final a in j['alts'] as List)
            if (a is Map) FieldAlt(_s(a['source']), a['value']),
      ],
    );
  }
}

/// What a check found about one work.
class ReverifyItem {
  const ReverifyItem({
    required this.type,
    required this.id,
    required this.title,
    required this.status,
    this.source = '',
    this.error = '',
    this.diffs = const [],
  });

  final String type, title, status, source, error;
  final int id;
  final List<FieldDiff> diffs;

  bool get checked => status == 'ok';

  static ReverifyItem? fromJson(Object? j) {
    if (j is! Map) return null;
    return ReverifyItem(
      type: _s(j['type']),
      id: _int(j['id']),
      title: _s(j['title']),
      status: _s(j['status']),
      source: _s(j['source']),
      error: _s(j['error']),
      diffs: [
        if (j['diffs'] is List)
          for (final d in j['diffs'] as List)
            if (FieldDiff.fromJson(d) != null) FieldDiff.fromJson(d)!,
      ],
    );
  }
}

/// The fields a reader accepted for one work.
class ApplyItem {
  const ApplyItem({
    required this.type,
    required this.id,
    required this.set,
    this.sources = const {},
    this.expect = const {},
  });

  final String type;
  final int id;

  /// field -> the value to write.
  final Map<String, Object?> set;

  /// field -> the supplier that gave the value.
  final Map<String, String> sources;

  /// field -> the stored value the reader was shown; a field that no longer holds it is left alone.
  final Map<String, Object?> expect;

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    'set': set,
    if (sources.isNotEmpty) 'sources': sources,
    if (expect.isNotEmpty) 'expect': expect,
  };
}

/// What applying one work said.
class ApplyResult {
  const ApplyResult({
    required this.type,
    required this.id,
    required this.ok,
    this.error = '',
    this.note = '',
  });

  final String type, error, note;
  final int id;
  final bool ok;
}

/// How much one check or apply call takes (the server's limit).
const reverifyBatch = 15;

/// What the server could still tell about the library's works: the ones with gaps, re-checking them against the
/// web with the changes shown for approval, merging the ones saved twice, and asking the server to fill gaps or
/// fetch covers as a job. An interface so a test can stand in for the server.
abstract class MetadataService {
  bool get available;

  Future<List<GapWork>> works();
  Future<List<List<DuplicateWork>>> duplicates();

  /// Folds the works [from] into [into]: quotes, tags and credits move, and the others go to the Bin.
  Future<void> merge({
    required bool book,
    required int into,
    required List<int> from,
  });

  /// Looks the works up again on the web and says what is different from what is stored. Nothing is written.
  Future<List<ReverifyItem>> check(List<GapWork> works);

  /// Writes what the reader accepted (at most [reverifyBatch] works).
  Future<List<ApplyResult>> apply(List<ApplyItem> items);

  /// Asks the server to fill every work's gaps from the web (a job).
  Future<void> fillAll();

  /// Asks the server to fetch covers and posters (a job). Only an admin may.
  Future<void> fetchCovers({bool missingOnly = true});
}

/// The paired server's metadata.
class PairedMetadataService implements MetadataService {
  PairedMetadataService(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  static final _gapNames = <String, String>{
    'has_cover': tx('common.field.cover.label'),
    'has_poster': tx('common.field.poster.label'),
    'has_author': tx('common.field.author.label'),
    'has_director': tx('common.field.director.label'),
    'has_series': tx('common.field.series.label'),
    'has_year': tx('common.field.year.label'),
    'has_genre': tx('movies.group.genre.label'),
    'has_description': 'Synopsis',
    'has_ids': 'Source',
    'has_source': 'Source',
    'has_cast': tx('common.field.cast.label'),
  };

  @override
  Future<List<GapWork>> works() => serverCall(_controller, (c) async {
    final r = await c.getJson('/metadata/library');
    final m = r is Map ? r : const {};
    List<String> gapsOf(Map j) => [
      for (final e in _gapNames.entries)
        if (j.containsKey(e.key) && !_b(j[e.key])) e.value,
    ];
    return [
      if (m['books'] is List)
        for (final b in m['books'] as List)
          if (b is Map)
            GapWork(
              kind: 'book',
              id: _int(b['id']),
              title: _s(b['title']),
              creator: _s(b['author']),
              cover: _s(b['cover_path']),
              lowRes: _b(b['low_res_cover']),
              gaps: gapsOf(b),
              quotes: _int(b['annotation_count']),
            ),
      if (m['movies'] is List)
        for (final b in m['movies'] as List)
          if (b is Map)
            GapWork(
              kind: 'movie',
              id: _int(b['id']),
              title: _s(b['title']),
              cover: _s(b['poster_path']),
              lowRes: _b(b['low_res_poster']),
              gaps: gapsOf(b),
              quotes: _int(b['dialogue_count']),
              mediaType: _s(b['media_type']),
            ),
    ];
  });

  @override
  Future<List<List<DuplicateWork>>> duplicates() =>
      serverCall(_controller, (c) async {
        final r = await c.getJson('/metadata/duplicates');
        final groups = r is Map ? r['groups'] : null;
        return [
          if (groups is List)
            for (final g in groups)
              if (g is List)
                [
                  for (final w in g)
                    if (w is Map)
                      DuplicateWork(
                        kind: _s(w['kind']),
                        id: _int(w['id']),
                        title: _s(w['title']),
                        creator: _s(w['author']),
                        year: _int(w['year']),
                        hasCover: _b(w['has_cover']),
                        quotes: _int(w['annotation_count']),
                      ),
                ],
        ];
      });

  @override
  Future<void> merge({
    required bool book,
    required int into,
    required List<int> from,
  }) => serverCall<void>(_controller, (c) async {
    await c.postJson(book ? '/books/merge' : '/movies/merge', {
      'into': into,
      'from': from,
    });
  });

  @override
  Future<List<ReverifyItem>> check(List<GapWork> works) =>
      serverCall(_controller, (c) async {
        final out = <ReverifyItem>[];
        for (var i = 0; i < works.length; i += reverifyBatch) {
          final part = works.skip(i).take(reverifyBatch).toList();
          final r = await c.postJson('/metadata/reverify', {
            'book_ids': [
              for (final w in part)
                if (w.isBook) w.id,
            ],
            'movie_ids': [
              for (final w in part)
                if (!w.isBook) w.id,
            ],
          });
          final items = r is Map ? r['items'] : null;
          if (items is List) {
            for (final x in items) {
              final it = ReverifyItem.fromJson(x);
              if (it != null) out.add(it);
            }
          }
        }
        return out;
      });

  @override
  Future<List<ApplyResult>> apply(List<ApplyItem> items) =>
      serverCall(_controller, (c) async {
        final out = <ApplyResult>[];
        for (var i = 0; i < items.length; i += reverifyBatch) {
          final part = items.skip(i).take(reverifyBatch).toList();
          final r = await c.postJson('/metadata/reverify/apply', {
            'items': [for (final it in part) it.toJson()],
          });
          final results = r is Map ? r['results'] : null;
          if (results is List) {
            for (final x in results) {
              if (x is Map) {
                out.add(
                  ApplyResult(
                    type: _s(x['type']),
                    id: _int(x['id']),
                    ok: _b(x['ok']),
                    error: _s(x['error']),
                    note: _s(x['note']),
                  ),
                );
              }
            }
          }
        }
        return out;
      });

  @override
  Future<void> fillAll() => serverCall<void>(_controller, (c) async {
    await c.postJson('/jobs', {
      'kind': 'fill',
      'params': {'all': true},
    });
  });

  @override
  Future<void> fetchCovers({bool missingOnly = true}) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/jobs', {
          'kind': 'covers',
          'params': {'missing_only': missingOnly},
        });
      });
}

/// Gives the screens below it the [MetadataService].
class MetadataScope extends InheritedWidget {
  const MetadataScope({super.key, required this.service, required super.child});

  final MetadataService? service;

  static MetadataService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MetadataScope>()?.service;

  @override
  bool updateShouldNotify(MetadataScope old) => old.service != service;
}
