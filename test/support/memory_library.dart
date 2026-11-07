import 'dart:async';

import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/sync/fingerprint.dart';

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
  final _boards = <int, Board>{};
  var _nextBoard = 1;
  final _filed = <int, int?>{};
  final _deletions = <PendingDeletion>[];
  var _deletionId = 1;
  var _quiet = false;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_quiet) _changes.add(null);
  }

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
    _works[w.id] = w;
    _notify();
    return w;
  }

  @override
  Future<Work?> work(int id) async => _works[id];

  @override
  Future<Work> updateWork(int id, WorkDraft d) async {
    final old = _works[id];
    if (old == null) throw const LibraryException('no such work');
    final title = d.title.trim();
    if (title.isEmpty) throw const LibraryException('a work needs a title');
    final updated = Work(
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
      cover: old.cover,
      details: old.details,
    );
    _works[id] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> deleteWork(int id) async {
    final w = _works[id];
    if (w != null) {
      final realm = realmOfKind(w.kind);
      if (w.serverId != null) _remember(workRoute(realm), w.serverId!);
      for (final q in _quotes.values.where((q) => q.workId == id)) {
        if (q.serverId != null) _remember(quoteRoute(realm), q.serverId!);
      }
    }
    await dropWork(id);
    _notify();
  }

  void _remember(String route, int serverId) =>
      _deletions.add(PendingDeletion(_deletionId++, route, serverId));

  @override
  Future<void> dropWork(int id) async {
    _works.remove(id);
    _quotes.removeWhere((_, q) => q.workId == id);
  }

  @override
  Future<void> dropQuote(int id) async => _quotes.remove(id);

  @override
  Future<List<PendingDeletion>> pendingDeletions() async => List.of(_deletions);

  @override
  Future<void> clearDeletion(int id) async =>
      _deletions.removeWhere((d) => d.id == id);

  @override
  Future<void> unlinkWork(int id) async {
    final w = _works[id];
    if (w != null) _works[id] = w.withServerId(null).withSyncedHash(null);
  }

  @override
  Future<void> unlinkQuote(int id) async {
    final q = _quotes[id];
    if (q != null) _quotes[id] = q.withServerId(null).withSyncedHash(null);
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
      boardId: d.workId == null && _boards.containsKey(d.boardId)
          ? d.boardId
          : null,
    );
  }

  @override
  Future<Quote> addQuote(QuoteDraft d) async {
    final q = _make(_next++, d, _clock());
    _quotes[q.id] = q;
    _notify();
    return q;
  }

  @override
  Future<Quote?> quote(int id) async => _quotes[id];

  @override
  Future<Quote> updateQuote(int id, QuoteDraft d) async {
    final old = _quotes[id];
    if (old == null) throw const LibraryException('no such quote');
    final q = _quotes[id] = _make(id, d, old.createdAt, old);
    _notify();
    return q;
  }

  @override
  Future<void> deleteQuote(int id) async {
    final q = _quotes[id];
    if (q != null && q.serverId != null) {
      final w = q.workId == null ? null : _works[q.workId];
      _remember(quoteRoute(realmOfQuote(w)), q.serverId!);
    }
    _quotes.remove(id);
    _notify();
  }

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
        boardId: q.boardId,
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
    int? boardId,
    bool unfiled = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final needle = query.trim().toLowerCase();
    bool matches(Quote q) {
      if (workId != null && q.workId != workId) return false;
      if (favouritesOnly && !q.favorite) return false;
      if (boardId != null && q.boardId != boardId) return false;
      if (unfiled && q.boardId != null) return false;
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
  Future<List<Board>> boards() async => [
    for (final b in _boards.values)
      Board(
        id: b.id,
        name: b.name,
        color: b.color,
        quotes: _quotes.values.where((q) => q.boardId == b.id).length,
        serverId: b.serverId,
        syncedHash: b.syncedHash,
        serverRow: b.serverRow,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  void _checkBoardName(String name, {int? except}) {
    final n = name.trim();
    if (n.isEmpty) throw const LibraryException('a board needs a name');
    if (_boards.values.any(
      (b) => b.id != except && b.name.toLowerCase() == n.toLowerCase(),
    )) {
      throw const LibraryException('a board with that name already exists');
    }
  }

  @override
  Future<Board> addBoard(String name, {String color = ''}) async {
    _checkBoardName(name);
    final b = Board(
      id: _nextBoard++,
      name: name.trim(),
      color: quoteColors.contains(color) ? color : '',
    );
    _boards[b.id] = b;
    _notify();
    return b;
  }

  @override
  Future<void> renameBoard(int id, String name) async {
    final b = _boards[id];
    if (b == null) throw const LibraryException('no such board');
    _checkBoardName(name, except: id);
    _boards[id] = _board(b, name: name.trim());
    _notify();
  }

  @override
  Future<void> recolourBoard(int id, String color) async {
    final b = _boards[id];
    if (b == null) return;
    _boards[id] = _board(b, color: quoteColors.contains(color) ? color : '');
    _notify();
  }

  Board _board(
    Board b, {
    String? name,
    String? color,
    int? serverId,
    String? hash,
    Map? row,
  }) => Board(
    id: b.id,
    name: name ?? b.name,
    color: color ?? b.color,
    serverId: serverId ?? b.serverId,
    syncedHash: hash ?? b.syncedHash,
    serverRow: row == null ? b.serverRow : Map<String, Object?>.from(row),
  );

  @override
  Future<void> linkBoard(int id, int serverId, String hash, Map row) async {
    final b = _boards[id];
    if (b != null) {
      _boards[id] = _board(b, serverId: serverId, hash: hash, row: row);
    }
  }

  @override
  Future<Board> adoptBoard(
    String name,
    String color,
    int serverId,
    String hash,
    Map row,
  ) async {
    final b = Board(
      id: _nextBoard++,
      name: name,
      color: quoteColors.contains(color) ? color : '',
      serverId: serverId,
      syncedHash: hash,
      serverRow: Map<String, Object?>.from(row),
    );
    _boards[b.id] = b;
    return b;
  }

  @override
  Future<void> applyBoard(
    int id,
    String name,
    String color,
    String hash,
    Map row,
  ) async {
    final b = _boards[id];
    if (b != null) {
      _boards[id] = _board(
        b,
        name: name,
        color: quoteColors.contains(color) ? color : '',
        hash: hash,
        row: row,
      );
    }
  }

  @override
  Future<void> unlinkBoard(int id) async {
    final b = _boards[id];
    if (b != null) {
      _boards[id] = Board(id: b.id, name: b.name, color: b.color);
    }
  }

  @override
  Future<void> dropBoard(int id) async {
    _boards.remove(id);
    for (final q in _quotes.values.where((q) => q.boardId == id).toList()) {
      _quotes[q.id] = q.withBoard(null);
    }
  }

  @override
  Future<List<Filing>> filings() async => [
    for (final q in _quotes.values)
      if (q.workId == null && q.serverId != null)
        Filing(
          quoteId: q.id,
          quoteServerId: q.serverId!,
          boardId: q.boardId,
          boardServerId: q.boardId == null
              ? null
              : _boards[q.boardId]?.serverId,
          agreed: _filed[q.id],
        ),
  ];

  @override
  Future<void> setQuoteBoard(int quoteId, int? boardId) async {
    final q = _quotes[quoteId];
    if (q != null) _quotes[quoteId] = q.withBoard(boardId);
  }

  @override
  Future<void> markQuoteFiled(int quoteId, int? serverBoard) async {
    _filed[quoteId] = serverBoard;
  }

  @override
  Future<void> deleteBoard(int id) async {
    final sid = _boards[id]?.serverId;
    if (sid != null) _remember('/boards', sid);
    _boards.remove(id);
    for (final q in _quotes.values.where((q) => q.boardId == id).toList()) {
      _quotes[q.id] = Quote(
        id: q.id,
        workId: q.workId,
        text: q.text,
        translation: q.translation,
        language: q.language,
        speaker: q.speaker,
        chapter: q.chapter,
        location: q.location,
        note: q.note,
        color: q.color,
        favorite: q.favorite,
        notedAt: q.notedAt,
        source: q.source,
        createdAt: q.createdAt,
        updatedAt: q.updatedAt,
        tags: q.tags,
        serverId: q.serverId,
        syncedHash: q.syncedHash,
      );
    }
    _notify();
  }

  @override
  Future<void> setWorkDetails(int id, WorkDetails details) async {
    final w = _works[id];
    if (w != null) _works[id] = w.withDetails(details);
  }

  @override
  Future<void> setWorkCover(int id, String name) async {
    final w = _works[id];
    if (w != null) _works[id] = w.withCover(name);
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
    _quiet = true;
    final w = (await addWork(d)).withServerId(serverId).withSyncedHash(hash);
    _quiet = false;
    return _works[w.id] = w;
  }

  @override
  Future<Quote> adoptQuote(QuoteDraft d, int serverId, String hash) async {
    _quiet = true;
    final q = (await addQuote(d)).withServerId(serverId).withSyncedHash(hash);
    _quiet = false;
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
