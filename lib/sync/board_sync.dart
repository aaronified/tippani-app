import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'fingerprint.dart';

/// What one board sync did.
class BoardResult {
  const BoardResult({
    this.added = 0,
    this.updated = 0,
    this.sent = 0,
    this.removedHere = 0,
    this.removedThere = 0,
    this.filed = 0,
    this.refused = const [],
    this.stoppedBy,
  });

  /// Boards brought down: new on the server, or changed there.
  final int added, updated;

  /// Boards sent up: new here, or changed here.
  final int sent;
  final int removedHere, removedThere;

  /// Quotes whose board changed, either way.
  final int filed;
  final List<String> refused;
  final ApiFailure? stoppedBy;

  int get changed =>
      added + updated + sent + removedHere + removedThere + filed;
}

/// What a board says that both sides hold: its name and its colour. (The server calls an unset colour yellow,
/// so the phone's "none" and the server's yellow are one thing.)
Fields boardFields(String name, String color) => {
  'name': name.trim(),
  'color': quoteColors.contains(color) ? color : 'yellow',
};

Fields serverBoardFields(Map row) {
  final name = row['name'];
  final color = row['color'];
  return boardFields(
    name is String ? name : '',
    color is String ? color.trim() : '',
  );
}

/// Keeps the phone's boards, and which board each standalone quote is on, the same as the server's.
///
/// - A board only on the server comes down; a board only here goes up; boards with the same name (any letter
///   case) that were never linked are linked, not duplicated.
/// - A linked board changed on one side is copied to the other. Changed on both: the server's wins, since a
///   board is a name and a colour and there is nothing to lose that a sentence of the reader's would be in.
/// - What the server holds that the phone does not (description, kind, languages, picture) is kept from the
///   server's own row and sent back with every edit, because the server's board edit replaces the whole board.
/// - A board deleted here is deleted there, its quotes moved to another board first, as the server requires. A
///   board deleted there is deleted here if it was not changed here since, and its quotes are left on none.
/// - A standalone quote's board is compared the same way, by the server's board id at the last agreement.
///
/// A server that has no boards (an older one) answers 404 and the whole step is skipped.
class BoardSync {
  BoardSync(this._store, this._controller, {this._log});

  final LibraryStore _store;
  final AppController _controller;
  final AppLog? _log;

  /// Syncs the boards. Returns the server's board ids that exist, for the filing step to use.
  Future<BoardResult> boards() async {
    var added = 0, updated = 0, sent = 0, here = 0, there = 0;
    final refused = <String>[];
    final List<Map<String, Object?>> rows;
    try {
      final got = await _controller.withClient((c) => c.getJson('/boards'));
      if (got == null) {
        return const BoardResult(stoppedBy: ApiFailure.unauthorised);
      }
      final l = got is Map ? got['boards'] : null;
      if (l is! List) {
        return const BoardResult(stoppedBy: ApiFailure.badResponse);
      }
      rows = [
        for (final x in l)
          if (x is Map && x['id'] is int) Map<String, Object?>.from(x),
      ];
    } on ApiException catch (e) {
      if (e.status == 404) return const BoardResult();
      return BoardResult(stoppedBy: e.failure);
    }

    // What the reader deleted here goes first, so the list read above cannot bring it back.
    final gone = <int>{};
    for (final d in await _store.pendingDeletions()) {
      if (d.route != '/boards') continue;
      final moveTo = rows
          .map((r) => r['id']! as int)
          .where((id) => id != d.serverId && !gone.contains(id))
          .firstOrNull;
      try {
        await _controller.withClient(
          (c) => c.delete(
            '/boards/${d.serverId}',
            body: moveTo == null ? null : {'move_to': moveTo},
          ),
        );
        there++;
      } on ApiException catch (e) {
        if (e.status == 400 || e.status == 409) {
          refused.add('deleting board ${d.serverId}: ${e.detail}');
        } else if (e.status != 404) {
          return BoardResult(stoppedBy: e.failure, refused: refused);
        }
      }
      gone.add(d.serverId);
      await _store.clearDeletion(d.id);
    }
    rows.removeWhere((r) => gone.contains(r['id']));

    final mine = await _store.boards();
    final byServer = {for (final r in rows) r['id']! as int: r};
    final taken = <int>{
      for (final b in mine)
        if (b.serverId != null) b.serverId!,
    };

    // A board the server no longer lists: removed here only if unchanged since they agreed, and not when so many
    // are missing that the server looks wiped or restored.
    final missing = [
      for (final b in mine)
        if (b.serverId != null && !byServer.containsKey(b.serverId)) b,
    ];
    final linked = mine.where((b) => b.serverId != null).length;
    final wiped = missing.length >= 3 && missing.length * 2 > linked;

    for (final b in mine) {
      final lf = boardFields(b.name, b.color);
      final lfp = fingerprint(lf);
      if (b.serverId == null) {
        final twin = rows
            .where(
              (r) =>
                  !taken.contains(r['id']) &&
                  (r['name'] as String? ?? '').trim().toLowerCase() ==
                      b.name.trim().toLowerCase(),
            )
            .firstOrNull;
        if (twin != null) {
          // The same board on both sides: linked, and the server's colour is the one kept.
          final sf = serverBoardFields(twin);
          taken.add(twin['id']! as int);
          await _store.applyBoard(
            b.id,
            b.name,
            sf['color']! as String,
            fingerprint(sf),
            twin,
          );
          await _store.linkBoard(
            b.id,
            twin['id']! as int,
            fingerprint(sf),
            twin,
          );
          updated++;
          continue;
        }
        final made = await _create(b, lf);
        if (made.stopped != null) {
          return BoardResult(
            added: added,
            updated: updated,
            sent: sent,
            removedHere: here,
            removedThere: there,
            refused: refused,
            stoppedBy: made.stopped,
          );
        }
        if (made.row != null) {
          await _store.linkBoard(b.id, made.row!['id']! as int, lfp, made.row!);
          taken.add(made.row!['id']! as int);
          sent++;
        } else {
          refused.add('board ${b.id}: ${made.reason}');
        }
        continue;
      }
      final row = byServer[b.serverId];
      if (row == null) {
        if (wiped) continue;
        if (b.syncedHash == lfp) {
          await _store.dropBoard(b.id);
          here++;
        } else {
          // Changed here since: kept, and sent again as new next time.
          await _store.unlinkBoard(b.id);
        }
        continue;
      }
      final sf = serverBoardFields(row);
      final sfp = fingerprint(sf);
      if (lfp == sfp) {
        if (b.syncedHash != lfp || b.serverRow.isEmpty) {
          await _store.linkBoard(b.id, b.serverId!, lfp, row);
        }
      } else if (b.syncedHash == sfp) {
        // only the phone moved
        final put = await _put(b, row, lf);
        if (put.stopped != null) {
          return BoardResult(
            added: added,
            updated: updated,
            sent: sent,
            removedHere: here,
            removedThere: there,
            refused: refused,
            stoppedBy: put.stopped,
          );
        }
        if (put.reason == null) {
          await _store.linkBoard(b.id, b.serverId!, lfp, put.row ?? row);
          sent++;
        } else {
          refused.add('board ${b.id}: ${put.reason}');
        }
      } else {
        // only the server moved, or both did (the server's wins)
        await _store.applyBoard(
          b.id,
          sf['name']! as String,
          sf['color']! as String,
          sfp,
          row,
        );
        updated++;
      }
    }

    final known = {for (final b in await _store.boards()) ?b.serverId: b};
    for (final r in rows) {
      final id = r['id']! as int;
      if (known.containsKey(id) || taken.contains(id)) continue;
      final sf = serverBoardFields(r);
      final name = sf['name']! as String;
      if (name.isEmpty) continue;
      // A name the phone already holds (for another server board) cannot be added a second time.
      if ((await _store.boards()).any(
        (b) => b.name.toLowerCase() == name.toLowerCase(),
      )) {
        continue;
      }
      await _store.adoptBoard(
        name,
        sf['color']! as String,
        id,
        fingerprint(sf),
        r,
      );
      added++;
    }
    final result = BoardResult(
      added: added,
      updated: updated,
      sent: sent,
      removedHere: here,
      removedThere: there,
      refused: refused,
    );
    _log?.info(
      'boards: $added added, $updated changed here, $sent sent, $here removed here, $there removed there, '
      '${refused.length} refused',
    );
    return result;
  }

  Future<_Wrote> _create(Board b, Fields lf) async {
    try {
      final answer = await _controller.withClient(
        (c) =>
            c.postJson('/boards', {'name': lf['name'], 'color': lf['color']}),
      );
      if (answer is Map && answer['id'] is int) {
        return _Wrote(row: Map<String, Object?>.from(answer));
      }
      return const _Wrote(stopped: ApiFailure.badResponse);
    } on ApiException catch (e) {
      if (e.status == 400 || e.status == 409) {
        return _Wrote(reason: e.detail.isEmpty ? 'refused' : e.detail);
      }
      return _Wrote(stopped: e.failure);
    }
  }

  /// The server's own row with the phone's name and colour written over it.
  Future<_Wrote> _put(Board b, Map<String, Object?> row, Fields lf) async {
    final body = <String, Object?>{
      for (final k in const [
        'description',
        'image_path',
        'hidden',
        'pos',
        'kind',
        'languages',
        'text_order',
      ])
        if (row.containsKey(k)) k: row[k],
      'name': lf['name'],
      'color': lf['color'],
    };
    try {
      await _controller.withClient(
        (c) => c.putJson('/boards/${b.serverId}', body),
      );
      return _Wrote(row: {...row, ...body});
    } on ApiException catch (e) {
      if (e.status == 400 || e.status == 409 || e.status == 404) {
        return _Wrote(reason: e.detail.isEmpty ? 'refused' : e.detail);
      }
      return _Wrote(stopped: e.failure);
    }
  }

  /// Compares where each standalone quote is filed here and there, and moves whichever side is behind. [rows] is
  /// the server's `/quotes` list as read for this sync; with [stale] it is read again, because deleting a board
  /// on the server moved the quotes that were on it.
  Future<BoardResult> filing(
    List<Map<String, Object?>> read, {
    bool stale = false,
  }) async {
    var rows = read;
    if (stale) {
      try {
        final got = await _controller.withClient((c) => c.getJson('/quotes'));
        final l = got is Map ? got['utterances'] : null;
        if (l is List) {
          rows = [
            for (final x in l)
              if (x is Map && x['id'] is int) Map<String, Object?>.from(x),
          ];
        }
      } on ApiException catch (e) {
        return BoardResult(stoppedBy: e.failure);
      }
    }
    final bySid = {for (final r in rows) r['id']! as int: r};
    final byBoardServer = {
      for (final b in await _store.boards()) ?b.serverId: b.id,
    };
    var filed = 0;
    final refused = <String>[];
    for (final f in await _store.filings()) {
      final row = bySid[f.quoteServerId];
      if (row == null) continue;
      final raw = row['board_id'];
      final there = raw is int && raw > 0 ? raw : null;
      final here = f.boardServerId;
      if (here == there) {
        if (f.agreed != there) await _store.markQuoteFiled(f.quoteId, there);
        continue;
      }
      if (here == f.agreed || there != f.agreed) {
        // only the server moved it, or both did (the server's wins)
        final local = there == null ? null : byBoardServer[there];
        if (there != null && local == null) continue;
        await _store.setQuoteBoard(f.quoteId, local);
        await _store.markQuoteFiled(f.quoteId, there);
        filed++;
        continue;
      }
      // only the phone moved it: the server's current row with the board changed
      try {
        final ok = await _controller.withClient((c) async {
          final fresh = await c.getJson('/quotes/${f.quoteServerId}');
          if (fresh is! Map) return false;
          final body = Map<String, Object?>.from(fresh)..remove('board_id');
          if (here != null) body['board_id'] = here;
          await c.putJson('/quotes/${f.quoteServerId}', body);
          return true;
        });
        if (ok == true) {
          await _store.markQuoteFiled(f.quoteId, here);
          filed++;
        }
      } on ApiException catch (e) {
        if (e.status == 400 || e.status == 409 || e.status == 404) {
          refused.add('quote ${f.quoteId}: ${e.detail}');
        } else {
          return BoardResult(
            filed: filed,
            refused: refused,
            stoppedBy: e.failure,
          );
        }
      }
    }
    return BoardResult(filed: filed, refused: refused);
  }
}

class _Wrote {
  const _Wrote({this.row, this.reason, this.stopped});
  final Map<String, Object?>? row;
  final String? reason;
  final ApiFailure? stopped;
}
