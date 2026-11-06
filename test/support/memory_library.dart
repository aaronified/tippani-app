import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';

/// A [LibraryStore] with no I/O, for widget tests: real SQLite work cannot be driven by a widget test's fake
/// clock (its futures never complete), so the screens are tested against this and the store itself against
/// real SQLite in `library_store_test.dart`. It mirrors the real store's rules that a screen shows (a title or
/// words are required, a quote's tags are trimmed and de-duplicated, a deleted work takes its quotes) but
/// searches with a plain contains.
class MemoryLibrary implements LibraryStore {
  MemoryLibrary({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.utc(2026, 11, 6, 8));

  final DateTime Function() _clock;
  final _works = <int, Work>{};
  final _quotes = <int, Quote>{};
  var _next = 1;

  @override
  Future<Work> addWork(WorkDraft d) async {
    final title = d.title.trim();
    if (title.isEmpty) throw const LibraryException('a work needs a title');
    final now = _clock();
    final w = Work(
      id: _next++,
      kind: d.kind,
      title: title,
      creator: d.creator.trim(),
      year: d.year,
      language: d.language.trim(),
      createdAt: now,
      updatedAt: now,
    );
    return _works[w.id] = w;
  }

  @override
  Future<Work?> work(int id) async => _works[id];

  @override
  Future<Work> updateWork(int id, WorkDraft d) async {
    final old = _works[id];
    if (old == null) throw const LibraryException('no such work');
    final title = d.title.trim();
    if (title.isEmpty) throw const LibraryException('a work needs a title');
    return _works[id] = Work(
      id: id,
      kind: d.kind,
      title: title,
      creator: d.creator.trim(),
      year: d.year,
      language: d.language.trim(),
      createdAt: old.createdAt,
      updatedAt: _clock(),
      serverId: old.serverId,
      syncedHash: old.syncedHash,
    );
  }

  @override
  Future<void> deleteWork(int id) async {
    _works.remove(id);
    _quotes.removeWhere((_, q) => q.workId == id);
  }

  @override
  Future<List<Work>> works({WorkKind? kind, String query = ''}) async {
    final q = query.trim().toLowerCase();
    return [
      for (final w in _works.values)
        if ((kind == null || w.kind == kind) &&
            (q.isEmpty ||
                w.title.toLowerCase().contains(q) ||
                w.creator.toLowerCase().contains(q)))
          w,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  List<String> _cleanTags(List<String> raw) {
    final seen = <String>{};
    return [
      for (final t in raw)
        if (t.trim().isNotEmpty && seen.add(t.trim().toLowerCase())) t.trim(),
    ];
  }

  Quote _make(int id, QuoteDraft d, DateTime created, [Quote? old]) {
    final text = d.text.trim();
    if (text.isEmpty) throw const LibraryException('a quote needs its words');
    if (d.workId != null && !_works.containsKey(d.workId)) {
      throw const LibraryException('no such work');
    }
    return Quote(
      id: id,
      workId: d.workId,
      text: text,
      translation: d.translation.trim(),
      language: d.language.trim(),
      speaker: d.speaker.trim(),
      chapter: d.chapter.trim(),
      location: d.location.trim(),
      note: d.note.trim(),
      color: quoteColors.contains(d.color) ? d.color : 'yellow',
      favorite: d.favorite,
      notedAt: d.notedAt ?? _clock(),
      source: d.source,
      createdAt: created,
      updatedAt: _clock(),
      tags: _cleanTags(d.tags)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      serverId: old?.serverId,
      syncedHash: old?.syncedHash,
    );
  }

  @override
  Future<Quote> addQuote(QuoteDraft d) async {
    final q = _make(_next++, d, _clock());
    return _quotes[q.id] = q;
  }

  @override
  Future<Quote?> quote(int id) async => _quotes[id];

  @override
  Future<Quote> updateQuote(int id, QuoteDraft d) async {
    final old = _quotes[id];
    if (old == null) throw const LibraryException('no such quote');
    return _quotes[id] = _make(id, d, old.createdAt, old);
  }

  @override
  Future<void> deleteQuote(int id) async => _quotes.remove(id);

  @override
  Future<void> setFavorite(int id, bool favorite) async {
    final q = _quotes[id];
    if (q == null) return;
    _quotes[id] = _make(
      id,
      QuoteDraft(
        text: q.text,
        workId: q.workId,
        translation: q.translation,
        language: q.language,
        speaker: q.speaker,
        chapter: q.chapter,
        location: q.location,
        note: q.note,
        color: q.color,
        favorite: favorite,
        notedAt: q.notedAt,
        source: q.source,
        tags: q.tags,
      ),
      q.createdAt,
      q,
    );
  }

  @override
  Future<List<Quote>> quotes({
    int? workId,
    String query = '',
    bool favouritesOnly = false,
    String? tag,
    int limit = 200,
    int offset = 0,
  }) async {
    final needle = query.trim().toLowerCase();
    bool matches(Quote q) {
      if (workId != null && q.workId != workId) return false;
      if (favouritesOnly && !q.favorite) return false;
      if (tag != null &&
          !q.tags.any((t) => t.toLowerCase() == tag.trim().toLowerCase())) {
        return false;
      }
      if (needle.isEmpty) return true;
      final w = q.workId == null ? null : _works[q.workId];
      return [
        q.text,
        q.translation,
        q.note,
        q.speaker,
        w?.title ?? '',
        w?.creator ?? '',
        ...q.tags,
      ].any((s) => s.toLowerCase().contains(needle));
    }

    final all = _quotes.values.where(matches).toList()
      ..sort((a, b) {
        final c = b.notedAt.compareTo(a.notedAt);
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    return all.skip(offset).take(limit).toList();
  }

  @override
  Future<List<String>> tags() async {
    final all = {for (final q in _quotes.values) ...q.tags}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return all;
  }

  @override
  Future<LibraryCounts> counts() async => LibraryCounts(
    works: _works.length,
    quotes: _quotes.length,
    favourites: _quotes.values.where((q) => q.favorite).length,
    tags: (await tags()).length,
  );

  @override
  Future<List<Work>> unsyncedWorks() async => [
    for (final w in _works.values)
      if (w.serverId == null) w,
  ]..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<List<Quote>> unsyncedQuotes() async => [
    for (final q in _quotes.values)
      if (q.serverId == null) q,
  ]..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<void> setWorkServerId(int id, int serverId) async {
    final w = _works[id];
    if (w != null) _works[id] = w.withServerId(serverId);
  }

  @override
  Future<void> setQuoteServerId(int id, int serverId) async {
    final q = _quotes[id];
    if (q != null) _quotes[id] = q.withServerId(serverId);
  }

  @override
  Future<void> markWorkSynced(int id, String hash) async {
    final w = _works[id];
    if (w != null) _works[id] = w.withSyncedHash(hash);
  }

  @override
  Future<void> markQuoteSynced(int id, String hash) async {
    final q = _quotes[id];
    if (q != null) _quotes[id] = q.withSyncedHash(hash);
  }

  @override
  Future<Work> adoptWork(WorkDraft d, int serverId, String hash) async {
    final w = (await addWork(d)).withServerId(serverId).withSyncedHash(hash);
    return _works[w.id] = w;
  }

  @override
  Future<Quote> adoptQuote(QuoteDraft d, int serverId, String hash) async {
    final q = (await addQuote(d)).withServerId(serverId).withSyncedHash(hash);
    return _quotes[q.id] = q;
  }

  @override
  Future<Map<String, Object?>> exportAll() async => {
    'version': SqliteLibraryStore.schemaVersion,
    'works': [for (final w in _works.values) w.toJson()],
    'quotes': [for (final q in _quotes.values) q.toJson()],
  };

  @override
  Future<void> replaceAll(Map<String, Object?> data) async =>
      throw UnimplementedError('replaceAll');
}
