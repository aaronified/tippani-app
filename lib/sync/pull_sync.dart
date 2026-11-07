import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'board_sync.dart';
import 'fingerprint.dart';
import 'push_sync.dart' show PushRefusal;

/// Whose version of a quote or work the reader keeps when both sides changed it.
enum ConflictSide { phone, server }

/// One field that reads differently on the phone and on the server.
class FieldDiff {
  const FieldDiff(this.label, this.phone, this.server);
  final String label;
  final String phone;
  final String server;
}

/// A work or quote changed on the phone AND on the server since they last agreed (or that the app cannot tell
/// the history of). Nothing is changed on either side until the reader chooses
/// ([ADR-0016](docs/wiki/ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md)). It is not stored: an
/// unresolved one is found again by the next sync.
class SyncConflict {
  const SyncConflict({
    required this.isWork,
    required this.localId,
    required this.realm,
    required this.serverId,
    required this.title,
    required this.diffs,
    required this.serverFields,
    required this.serverRow,
  });

  final bool isWork;
  final int localId;
  final Realm realm;
  final int serverId;

  /// A name for the screen to show (the work's title, the start of the quote). Never logged.
  final String title;
  final List<FieldDiff> diffs;
  final Fields serverFields;
  final Map<String, Object?> serverRow;
}

/// What one sync did.
class PullResult {
  const PullResult({
    this.worksAdded = 0,
    this.quotesAdded = 0,
    this.worksUpdated = 0,
    this.quotesUpdated = 0,
    this.worksSent = 0,
    this.quotesSent = 0,
    this.conflicts = const [],
    this.refused = const [],
    this.goneOnServer = 0,
    this.skipped = 0,
    this.deletedThere = 0,
    this.deletedHere = 0,
    this.relinked = 0,
    this.heldBack = 0,
    this.linked = 0,
    this.boards = 0,
    this.stoppedBy,
  });

  /// Boards and board filings that changed, either way.
  final int boards;

  /// Brought down: new on the server, or changed only there.
  final int worksAdded, quotesAdded, worksUpdated, quotesUpdated;

  /// Sent up: changed only on the phone.
  final int worksSent, quotesSent;
  final List<SyncConflict> conflicts;
  final List<PushRefusal> refused;

  /// Items a write found already gone from the server (it deleted them between the read and the write).
  final int goneOnServer;

  /// Deleted on the server because the reader deleted them here (they sit in the server's bin).
  final int deletedThere;

  /// Removed here because they were deleted on the server and had not been changed here since.
  final int deletedHere;

  /// Gone from the server but changed here since (or holding quotes that are only here): kept, and sent up
  /// again as new.
  final int relinked;

  /// Items the server no longer lists that were NOT removed here, because that is so many of them that the
  /// server itself looks wiped or restored from an old copy.
  final int heldBack;

  /// Unlinked phone works and quotes matched to the server's copy instead of being copied down a second time.
  final int linked;

  /// Server items that could not come down (a quote with no words, a quote whose work is not here).
  final int skipped;
  final ApiFailure? stoppedBy;

  int get brought =>
      worksAdded + quotesAdded + worksUpdated + quotesUpdated + boards;
  int get sent => worksSent + quotesSent;
}

enum _Verdict { same, pull, push, conflict }

/// Which side moved since they last agreed. [base] is the fingerprint stored then (null: never agreed).
_Verdict _decide(String? base, String phone, String server) {
  if (phone == server) return _Verdict.same;
  if (base == null) return _Verdict.conflict;
  if (phone == base) return _Verdict.pull;
  if (server == base) return _Verdict.push;
  return _Verdict.conflict;
}

class _Fetched {
  _Fetched(this.works, this.quotes);
  final Map<Realm, List<Map<String, Object?>>> works;
  final Map<Realm, List<Map<String, Object?>>> quotes;
}

class _Put {
  const _Put({this.stopped, this.gone = false, this.reason});
  final ApiFailure? stopped;
  final bool gone;
  final String? reason;
  bool get ok => stopped == null && !gone && reason == null;
}

class _Tally {
  int worksAdded = 0, quotesAdded = 0, worksUpdated = 0, quotesUpdated = 0;
  int worksSent = 0, quotesSent = 0, gone = 0, skipped = 0;
  int deletedThere = 0, deletedHere = 0, relinked = 0, heldBack = 0, linked = 0;
  int boards = 0;
  final conflicts = <SyncConflict>[];
  final refused = <PushRefusal>[];
  ApiFailure? stopped;
}

/// Brings the server's library down and sends the phone's edits up, per work and per quote:
///
/// - only on the server: added here;
/// - changed only on the server: applied here;
/// - changed only on the phone: sent up (the server's own row, with the phone's fields written over it, so
///   what the phone does not hold is not wiped);
/// - changed on both, or never agreed and different: left alone and offered to the reader as a conflict.
///
/// WHO MOVED is read from a fingerprint of the fields that sync, stored at the last agreement
/// (`synced_hash`), not from timestamps: the server does not give a work's `updated_at` at all.
/// Deletes travel both ways ([ADR-0017](docs/wiki/ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md)).
class PullSync {
  PullSync(this._store, this._controller, {this._log});

  final LibraryStore _store;
  final AppController _controller;
  final AppLog? _log;

  Future<PullResult>? _current;
  bool get running => _current != null;

  /// Runs a sync. A second call while one is running joins it rather than starting another, so the reader's tap
  /// and the automatic sync never run two at once.
  Future<PullResult> sync() =>
      _current ??= _sync().whenComplete(() => _current = null);

  Future<_Fetched?> _fetch() => _controller.withClient((c) async {
    Future<List<Map<String, Object?>>> list(String path, String key) async {
      final a = await c.getJson(path);
      final l = a is Map ? a[key] : null;
      if (l is! List) {
        throw const ApiException(
          ApiFailure.badResponse,
          'not a list from the server',
        );
      }
      return [
        for (final x in l)
          if (x is Map && x['id'] is int) Map<String, Object?>.from(x),
      ];
    }

    return _Fetched(
      {
        Realm.book: await list('/books', 'books'),
        Realm.screen: await list('/movies', 'movies'),
      },
      {
        Realm.book: await list('/annotations', 'annotations'),
        Realm.screen: await list('/dialogues', 'dialogues'),
        Realm.loose: await list('/quotes', 'utterances'),
      },
    );
  });

  Future<PullResult> _sync() async {
    if (!_controller.paired) {
      return const PullResult(stoppedBy: ApiFailure.unauthorised);
    }
    final t = _Tally();
    // What the reader deleted goes first, so the lists read next cannot bring it back.
    await _sendDeletions(t);
    if (t.stopped != null) return _finish(t);
    // Everything else is read before anything is changed, so a connection that fails half way changes nothing.
    final _Fetched? got;
    try {
      got = await _fetch();
    } on ApiException catch (e) {
      t.stopped = e.failure;
      return _finish(t);
    }
    if (got == null) {
      t.stopped = ApiFailure.unauthorised;
      return _finish(t);
    }
    await _syncWorks(got, t);
    if (t.stopped == null) await _syncQuotes(got, t);
    if (t.stopped == null) await _syncBoards(got, t);
    if (t.stopped == null) await _syncGone(got, t);
    return _finish(t);
  }

  PullResult _finish(_Tally t) {
    final result = PullResult(
      worksAdded: t.worksAdded,
      quotesAdded: t.quotesAdded,
      worksUpdated: t.worksUpdated,
      quotesUpdated: t.quotesUpdated,
      worksSent: t.worksSent,
      quotesSent: t.quotesSent,
      conflicts: t.conflicts,
      refused: t.refused,
      goneOnServer: t.gone,
      skipped: t.skipped,
      deletedThere: t.deletedThere,
      deletedHere: t.deletedHere,
      relinked: t.relinked,
      heldBack: t.heldBack,
      linked: t.linked,
      boards: t.boards,
      stoppedBy: t.stopped,
    );
    _log?.info(
      'sync: brought down ${result.worksAdded} new and ${result.worksUpdated} changed works, '
      '${result.quotesAdded} new and ${result.quotesUpdated} changed quotes; sent '
      '${result.worksSent} works and ${result.quotesSent} quotes; ${t.conflicts.length} conflicts, '
      '${t.refused.length} refused, ${t.gone} gone on the server, ${t.skipped} skipped, '
      '${t.deletedThere} deleted there, ${t.deletedHere} deleted here, ${t.relinked} relinked, '
      '${t.heldBack} held back, ${t.linked} linked to a twin'
      '${t.stopped == null ? '' : ', stopped by ${t.stopped}'}',
    );
    for (final r in t.refused) {
      _log?.warn('sync: ${r.what} refused: ${r.reason}');
    }
    return result;
  }

  // ---- boards -------------------------------------------------------------------------------------

  Future<void> _syncBoards(_Fetched got, _Tally t) async {
    final sync = BoardSync(_store, _controller, log: _log);
    final b = await sync.boards();
    t.boards += b.changed;
    for (final r in b.refused) {
      t.refused.add(PushRefusal('a board', r));
    }
    if (b.stoppedBy != null) {
      t.stopped = b.stoppedBy;
      return;
    }
    final f = await sync.filing(
      got.quotes[Realm.loose]!,
      stale: b.removedThere > 0,
    );
    t.boards += f.changed;
    for (final r in f.refused) {
      t.refused.add(PushRefusal('a quote\'s board', r));
    }
    if (f.stoppedBy != null) t.stopped = f.stoppedBy;
  }

  // ---- works --------------------------------------------------------------------------------------

  Future<void> _syncWorks(_Fetched got, _Tally t) async {
    final all = await _store.works();
    final local = {
      for (final w in all)
        if (w.serverId != null) (realmOfKind(w.kind), w.serverId!): w,
    };
    final unlinked = [
      for (final w in all)
        if (w.serverId == null) w,
    ];
    for (final realm in [Realm.book, Realm.screen]) {
      for (final row in got.works[realm]!) {
        final id = row['id']! as int;
        final sf = serverWorkFields(row, realm);
        final sfp = fingerprint(sf);
        var w = local[(realm, id)];
        if (w == null) {
          // A phone work never sent, that the server already has: the same work, not a second one.
          final twin = unlinked
              .where(
                (u) =>
                    realmOfKind(u.kind) == realm &&
                    sameWork(
                      u.title,
                      u.creator,
                      sf['title']! as String,
                      sf['creator']! as String,
                    ),
              )
              .firstOrNull;
          if (twin != null) {
            unlinked.remove(twin);
            await _store.setWorkServerId(twin.id, id);
            w = twin.withServerId(id);
            t.linked++;
          }
        }
        final cover = _coverOf(row, realm);
        if (w == null) {
          final adopted = await _store.adoptWork(_workDraft(sf, null), id, sfp);
          if (cover.isNotEmpty) await _store.setWorkCover(adopted.id, cover);
          await _keepShelf(adopted, row);
          t.worksAdded++;
          continue;
        }
        if (w.cover != cover) await _store.setWorkCover(w.id, cover);
        await _keepShelf(w, row);
        final lf = workFields(w);
        final lfp = fingerprint(lf);
        switch (_decide(w.syncedHash, lfp, sfp)) {
          case _Verdict.same:
            if (w.syncedHash != lfp) await _store.markWorkSynced(w.id, lfp);
          case _Verdict.pull:
            await _applyWork(w, sf, sfp);
            t.worksUpdated++;
          case _Verdict.push:
            final p = await _putWork(w, realm, id);
            if (p.ok) {
              await _store.markWorkSynced(w.id, lfp);
              t.worksSent++;
            } else if (!_note(t, 'work ${w.id}', p)) {
              return;
            }
          case _Verdict.conflict:
            t.conflicts.add(
              SyncConflict(
                isWork: true,
                localId: w.id,
                realm: realm,
                serverId: id,
                title: w.title,
                diffs: _diffs(lf, sf),
                serverFields: sf,
                serverRow: row,
              ),
            );
        }
      }
    }
  }

  /// Keeps the shelf status and progress the server holds for a work (read-only here: the server owns the shelf),
  /// so the library can show them without opening each work. Changes nothing that syncs.
  Future<void> _keepShelf(Work w, Map row) async {
    final status = row['status'] is String ? (row['status'] as String) : '';
    final progress = row['progress'] is int
        ? (row['progress'] as int).clamp(0, 100)
        : 0;
    if (w.details.status == status && w.details.progress == progress) return;
    await _store.setWorkDetails(
      w.id,
      w.details.copyWith(status: status, progress: progress),
    );
  }

  /// The name of the cover (or poster) file the server holds for a work row, or '' for none.
  static String _coverOf(Map row, Realm realm) {
    final v = realm == Realm.screen ? row['poster_path'] : row['cover_path'];
    return v is String ? v : '';
  }

  WorkDraft _workDraft(Fields sf, Work? old) {
    final kind = sf['kind']! as String;
    return WorkDraft(
      title: sf['title']! as String,
      kind: kind == 'book'
          ? (old != null && realmOfKind(old.kind) == Realm.book
                ? old.kind
                : WorkKind.book)
          : workKindOf(kind),
      creator: sf['creator']! as String,
      year: sf['year'] as int?,
      language: old?.language ?? '',
    );
  }

  Future<void> _applyWork(Work w, Fields sf, String sfp) async {
    await _store.updateWork(w.id, _workDraft(sf, w));
    await _store.markWorkSynced(w.id, sfp);
  }

  Future<_Put> _putWork(Work w, Realm realm, int serverId) => _write((c) async {
    final path = '${workRoute(realm)}/$serverId';
    // The whole record, because the server's update replaces everything and the phone holds only a few
    // of its fields: read it, write the phone's over it, send it back.
    final cur = await c.getJson(path);
    final body = <String, Object?>{
      if (cur is Map) ...Map<String, Object?>.from(cur),
      'title': w.title,
      if (realm == Realm.screen) ...{
        'director': w.creator,
        'release_year': w.year ?? 0,
        'media_type': w.kind == WorkKind.film ? 'movie' : w.kind.name,
      } else ...{
        'author': w.creator,
        'published_year': w.year ?? 0,
      },
    };
    await c.putJson(path, body);
  });

  // ---- quotes -------------------------------------------------------------------------------------

  Future<void> _syncQuotes(_Fetched got, _Tally t) async {
    final works = {for (final w in await _store.works()) w.id: w};
    final localWork = {
      for (final w in works.values)
        if (w.serverId != null) (realmOfKind(w.kind), w.serverId!): w,
    };
    final allQuotes = await _store.quotes(limit: 1 << 30);
    final local = {
      for (final q in allQuotes)
        if (q.serverId != null)
          (
            realmOfQuote(q.workId == null ? null : works[q.workId]),
            q.serverId!,
          ): q,
    };
    final unlinked = [
      for (final q in allQuotes)
        if (q.serverId == null) q,
    ];
    for (final realm in Realm.values) {
      for (final row in got.quotes[realm]!) {
        final id = row['id']! as int;
        final sf = serverQuoteFields(row, realm);
        final sfp = fingerprint(sf);
        var q = local[(realm, id)];
        if (q == null) {
          final parent = _parent(row, realm);
          final work = parent == null ? null : localWork[(realm, parent)];
          if ((sf['text']! as String).isEmpty ||
              (realm != Realm.loose && work == null)) {
            t.skipped++;
            continue;
          }
          // A phone quote never sent, that the server already has (same words, same work): the same quote.
          final twin = unlinked
              .where(
                (u) =>
                    u.workId == work?.id &&
                    sameWords(u.text, sf['text']! as String),
              )
              .firstOrNull;
          if (twin != null) {
            unlinked.remove(twin);
            await _store.setQuoteServerId(twin.id, id);
            q = twin.withServerId(id);
            t.linked++;
          } else {
            await _store.adoptQuote(
              _quoteDraft(sf, row, work?.id, null),
              id,
              sfp,
            );
            t.quotesAdded++;
            continue;
          }
        }
        final lf = quoteFields(q, realm);
        final lfp = fingerprint(lf);
        switch (_decide(q.syncedHash, lfp, sfp)) {
          case _Verdict.same:
            if (q.syncedHash != lfp) await _store.markQuoteSynced(q.id, lfp);
          case _Verdict.pull:
            await _applyQuote(q, realm, sf, row, sfp);
            t.quotesUpdated++;
          case _Verdict.push:
            final p = await _putQuote(q, realm, row);
            if (p.ok) {
              await _store.markQuoteSynced(q.id, lfp);
              t.quotesSent++;
            } else if (!_note(t, 'quote ${q.id}', p)) {
              return;
            }
          case _Verdict.conflict:
            final text = q.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            t.conflicts.add(
              SyncConflict(
                isWork: false,
                localId: q.id,
                realm: realm,
                serverId: id,
                title: text.length > 60 ? '${text.substring(0, 60)}…' : text,
                diffs: _diffs(lf, sf),
                serverFields: sf,
                serverRow: row,
              ),
            );
        }
      }
    }
  }

  /// Tells the server about what the reader deleted here. A 404 means it is gone already; a refusal is
  /// reported and the item may come back down on the pull that follows; anything else stops the sync.
  Future<void> _sendDeletions(_Tally t) async {
    for (final d in await _store.pendingDeletions()) {
      // A board is deleted with the quotes moved first, which needs the server's board list (see BoardSync).
      if (d.route == '/boards') continue;
      final p = await _write((c) async {
        await c.delete('${d.route}/${d.serverId}');
      });
      if (p.stopped != null) {
        t.stopped = p.stopped;
        return;
      }
      if (p.reason != null) {
        t.refused.add(
          PushRefusal('deleting ${d.route}/${d.serverId}', p.reason!),
        );
      } else if (!p.gone) {
        t.deletedThere++;
      }
      await _store.clearDeletion(d.id);
    }
  }

  /// Applies what was deleted on the server. A quote or work the server no longer lists is removed here only
  /// if it has not been changed here since they last agreed; otherwise it is kept and unlinked, so it goes up
  /// again as new. A work is removed only when no quote is left under it. And if so many are missing that the
  /// server looks wiped (ten or more, and over half of everything linked), nothing is removed: that is a
  /// restore or a mistake, not the reader deleting things.
  Future<void> _syncGone(_Fetched got, _Tally t) async {
    final workIds = {
      for (final r in [Realm.book, Realm.screen])
        r: {for (final w in got.works[r]!) w['id']! as int},
    };
    final quoteIds = {
      for (final r in Realm.values)
        r: {for (final q in got.quotes[r]!) q['id']! as int},
    };
    final works = {for (final w in await _store.works()) w.id: w};
    final quotes = await _store.quotes(limit: 1 << 30);
    final goneQuotes = <(Quote, Realm)>[];
    var linked = 0;
    for (final q in quotes) {
      if (q.serverId == null) continue;
      linked++;
      final realm = realmOfQuote(q.workId == null ? null : works[q.workId]);
      if (!quoteIds[realm]!.contains(q.serverId)) goneQuotes.add((q, realm));
    }
    final goneWorks = <Work>[];
    for (final w in works.values) {
      if (w.serverId == null) continue;
      linked++;
      if (!workIds[realmOfKind(w.kind)]!.contains(w.serverId)) {
        goneWorks.add(w);
      }
    }
    final gone = goneQuotes.length + goneWorks.length;
    if (gone == 0) return;
    if (gone >= 10 && gone * 2 > linked) {
      t.heldBack += gone;
      return;
    }
    for (final (q, realm) in goneQuotes) {
      if (q.syncedHash != null &&
          q.syncedHash == fingerprint(quoteFields(q, realm))) {
        await _store.dropQuote(q.id);
        t.deletedHere++;
      } else {
        await _store.unlinkQuote(q.id);
        t.relinked++;
      }
    }
    for (final w in goneWorks) {
      final left = await _store.quotes(workId: w.id, limit: 1);
      if (left.isEmpty &&
          w.syncedHash != null &&
          w.syncedHash == fingerprint(workFields(w))) {
        await _store.dropWork(w.id);
        t.deletedHere++;
      } else {
        await _store.unlinkWork(w.id);
        t.relinked++;
      }
    }
  }

  int? _parent(Map row, Realm realm) {
    final v = realm == Realm.book
        ? row['book_id']
        : realm == Realm.screen
        ? row['movie_id']
        : null;
    return v is int ? v : null;
  }

  static DateTime? _time(Object? v) {
    if (v is! String || v.trim().isEmpty) return null;
    var s = v.trim().replaceFirst(' ', 'T');
    if (!s.endsWith('Z') && !RegExp(r'[+-]\d\d:\d\d$').hasMatch(s)) s += 'Z';
    return DateTime.tryParse(s);
  }

  /// A local quote from the server's fields. [old], when given, keeps what the server does not hold: the
  /// source, when it was noted, and a film quote's chapter.
  QuoteDraft _quoteDraft(Fields sf, Map row, int? workId, Quote? old) {
    final rawTags = row['tags'];
    return QuoteDraft(
      text: sf['text']! as String,
      workId: old?.workId ?? workId,
      translation: sf['translation']! as String,
      language: sf['language']! as String,
      speaker: sf['speaker']! as String,
      chapter: old != null && (sf['chapter']! as String).isEmpty
          ? old.chapter
          : sf['chapter']! as String,
      location: sf['location']! as String,
      note: sf['note']! as String,
      color: sf['color']! as String,
      favorite: sf['favorite']! as bool,
      notedAt:
          old?.notedAt ?? _time(row['noted_at']) ?? _time(row['created_at']),
      source: old?.source ?? 'import',
      tags: [
        if (rawTags is List)
          for (final t in rawTags)
            if (t is String) t,
      ],
    );
  }

  Future<void> _applyQuote(
    Quote q,
    Realm realm,
    Fields sf,
    Map row,
    String sfp,
  ) async {
    await _store.updateQuote(q.id, _quoteDraft(sf, row, q.workId, q));
    await _store.markQuoteSynced(q.id, sfp);
  }

  /// The server's own row with the phone's fields written over it, so a sticker or a chapter number the
  /// phone never held survives the edit.
  Future<_Put> _putQuote(Quote q, Realm realm, Map<String, Object?> row) =>
      _write((c) async {
        final body = <String, Object?>{
          ...row,
          'quote': q.text,
          'note': q.note,
          'translation': q.translation,
          'language': q.language,
          'color': q.color,
          'favorite': q.favorite,
          'tags': q.tags,
          'source': row['source'] ?? (q.source == 'capture' ? 'ocr' : 'manual'),
          ...switch (realm) {
            Realm.book => {
              'character': q.speaker,
              'chapter': q.chapter,
              'location': q.location,
            },
            Realm.screen => {'character': q.speaker, 'timestamp': q.location},
            Realm.loose => {
              'speaker': q.speaker,
              'occasion': q.chapter,
              'place': q.location,
            },
          },
        };
        await c.putJson('${quoteRoute(realm)}/${row['id']}', body);
      });

  // ---- shared -------------------------------------------------------------------------------------

  Future<_Put> _write(Future<void> Function(ApiClient c) run) async {
    try {
      final done = await _controller.withClient((c) async {
        await run(c);
        return true;
      });
      return done == null
          ? const _Put(stopped: ApiFailure.unauthorised)
          : const _Put();
    } on ApiException catch (e) {
      if (e.status == 404) return const _Put(gone: true);
      if (e.status == 400 || e.status == 409) {
        return _Put(reason: e.detail.isEmpty ? 'refused' : e.detail);
      }
      return _Put(stopped: e.failure);
    }
  }

  /// Files a failed write in [t]. Returns false when the sync must stop.
  bool _note(_Tally t, String what, _Put p) {
    if (p.stopped != null) {
      t.stopped = p.stopped;
      return false;
    }
    if (p.gone) {
      t.gone++;
    } else {
      t.refused.add(PushRefusal(what, p.reason ?? 'refused'));
    }
    return true;
  }

  static const _labels = {
    'text': 'Words',
    'translation': 'Translation',
    'language': 'Language',
    'speaker': 'Speaker',
    'chapter': 'Chapter',
    'location': 'Place',
    'note': 'Note',
    'color': 'Colour',
    'favorite': 'Favourite',
    'tags': 'Tags',
    'kind': 'Kind',
    'title': 'Title',
    'creator': 'By',
    'year': 'Year',
  };

  static String _show(Object? v) {
    if (v is bool) return v ? 'yes' : 'no';
    if (v is List) return v.isEmpty ? '(none)' : v.join(', ');
    if (v == null || (v is String && v.isEmpty)) return '(none)';
    return '$v';
  }

  List<FieldDiff> _diffs(Fields phone, Fields server) => [
    for (final k in phone.keys)
      if (_show(phone[k]) != _show(server[k]))
        FieldDiff(_labels[k] ?? k, _show(phone[k]), _show(server[k])),
  ];

  // ---- resolving a conflict ---------------------------------------------------------------------

  /// Applies the reader's choice for one conflict. Returns null when it worked, or a plain sentence saying
  /// why it did not (the conflict then stays, and the next sync finds it again).
  Future<String?> resolve(SyncConflict c, ConflictSide side) async {
    try {
      if (c.isWork) {
        final w = await _store.work(c.localId);
        if (w == null) return 'That work is no longer on this phone.';
        if (side == ConflictSide.server) {
          await _applyWork(w, c.serverFields, fingerprint(c.serverFields));
          return null;
        }
        final p = await _putWork(w, c.realm, c.serverId);
        if (!p.ok) return _why(p);
        await _store.markWorkSynced(w.id, fingerprint(workFields(w)));
        return null;
      }
      final q = await _store.quote(c.localId);
      if (q == null) return 'That quote is no longer on this phone.';
      if (side == ConflictSide.server) {
        await _applyQuote(
          q,
          c.realm,
          c.serverFields,
          c.serverRow,
          fingerprint(c.serverFields),
        );
        return null;
      }
      final p = await _putQuote(q, c.realm, c.serverRow);
      if (!p.ok) return _why(p);
      await _store.markQuoteSynced(q.id, fingerprint(quoteFields(q, c.realm)));
      return null;
    } on LibraryException catch (e) {
      return e.message;
    }
  }

  static String _why(_Put p) {
    if (p.gone) return 'The server no longer has it.';
    if (p.reason != null) return 'The server refused it: ${p.reason}.';
    return switch (p.stopped) {
      ApiFailure.network ||
      ApiFailure.timeout => 'The server could not be reached.',
      ApiFailure.unauthorised =>
        'The server does not accept this phone. Pair it again in Settings.',
      ApiFailure.rateLimited => 'The server asked the app to slow down.',
      ApiFailure.forbidden => 'This account is not allowed to change it.',
      _ => 'The server answered with an error.',
    };
  }
}
