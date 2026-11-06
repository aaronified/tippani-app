import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import '../library/library_store.dart';
import '../library/models.dart';
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
    this.stoppedBy,
  });

  /// Brought down: new on the server, or changed only there.
  final int worksAdded, quotesAdded, worksUpdated, quotesUpdated;

  /// Sent up: changed only on the phone.
  final int worksSent, quotesSent;
  final List<SyncConflict> conflicts;
  final List<PushRefusal> refused;

  /// Items the phone links to that the server no longer has. They are left alone, never deleted.
  final int goneOnServer;

  /// Server items that could not come down (a quote with no words, a quote whose work is not here).
  final int skipped;
  final ApiFailure? stoppedBy;

  int get brought => worksAdded + quotesAdded + worksUpdated + quotesUpdated;
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
/// It never deletes anything on either side.
class PullSync {
  PullSync(this._store, this._controller, {this._log});

  final LibraryStore _store;
  final AppController _controller;
  final AppLog? _log;

  bool _running = false;
  bool get running => _running;

  Future<PullResult> sync() {
    if (_running) throw StateError('a sync is already running');
    _running = true;
    return _sync().whenComplete(() => _running = false);
  }

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
    // Everything is read before anything is changed, so a connection that fails half way changes nothing.
    final _Fetched? got;
    try {
      got = await _fetch();
    } on ApiException catch (e) {
      return PullResult(stoppedBy: e.failure);
    }
    if (got == null) {
      return const PullResult(stoppedBy: ApiFailure.unauthorised);
    }
    final t = _Tally();
    await _syncWorks(got, t);
    if (t.stopped == null) await _syncQuotes(got, t);

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
      stoppedBy: t.stopped,
    );
    _log?.info(
      'sync: brought down ${result.worksAdded} new and ${result.worksUpdated} changed works, '
      '${result.quotesAdded} new and ${result.quotesUpdated} changed quotes; sent '
      '${result.worksSent} works and ${result.quotesSent} quotes; ${t.conflicts.length} conflicts, '
      '${t.refused.length} refused, ${t.gone} gone on the server, ${t.skipped} skipped'
      '${t.stopped == null ? '' : ', stopped by ${t.stopped}'}',
    );
    for (final r in t.refused) {
      _log?.warn('sync: ${r.what} refused: ${r.reason}');
    }
    return result;
  }

  // ---- works --------------------------------------------------------------------------------------

  Future<void> _syncWorks(_Fetched got, _Tally t) async {
    final local = {
      for (final w in await _store.works())
        if (w.serverId != null) (realmOfKind(w.kind), w.serverId!): w,
    };
    for (final realm in [Realm.book, Realm.screen]) {
      final seen = <int>{};
      for (final row in got.works[realm]!) {
        final id = row['id']! as int;
        seen.add(id);
        final sf = serverWorkFields(row, realm);
        final sfp = fingerprint(sf);
        final w = local[(realm, id)];
        if (w == null) {
          await _store.adoptWork(_workDraft(sf, null), id, sfp);
          t.worksAdded++;
          continue;
        }
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
      t.gone += local.entries
          .where((e) => e.key.$1 == realm && !seen.contains(e.key.$2))
          .length;
    }
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
    final local = {
      for (final q in await _store.quotes(limit: 1 << 30))
        if (q.serverId != null)
          (
            realmOfQuote(q.workId == null ? null : works[q.workId]),
            q.serverId!,
          ): q,
    };
    for (final realm in Realm.values) {
      final seen = <int>{};
      for (final row in got.quotes[realm]!) {
        final id = row['id']! as int;
        seen.add(id);
        final sf = serverQuoteFields(row, realm);
        final sfp = fingerprint(sf);
        final q = local[(realm, id)];
        if (q == null) {
          final parent = _parent(row, realm);
          final work = parent == null ? null : localWork[(realm, parent)];
          if ((sf['text']! as String).isEmpty ||
              (realm != Realm.loose && work == null)) {
            t.skipped++;
            continue;
          }
          await _store.adoptQuote(
            _quoteDraft(sf, row, work?.id, null),
            id,
            sfp,
          );
          t.quotesAdded++;
          continue;
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
      t.gone += local.entries
          .where((e) => e.key.$1 == realm && !seen.contains(e.key.$2))
          .length;
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
