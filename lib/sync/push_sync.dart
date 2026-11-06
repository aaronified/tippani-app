import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'fingerprint.dart';

/// What one push did.
class PushResult {
  const PushResult({
    this.worksSent = 0,
    this.quotesSent = 0,
    this.alreadyThere = 0,
    this.refused = const [],
    this.waiting = 0,
    this.stoppedBy,
  });

  /// Works and quotes the server had never seen, now created there and remembered here.
  final int worksSent;
  final int quotesSent;

  /// Quotes the server already held (a 409 with the row it clashed with): adopted, not duplicated.
  final int alreadyThere;

  /// Items the server refused with a reason (a 400). Each is named by what it is, never by what it says.
  final List<PushRefusal> refused;

  /// Quotes not tried because their work was refused or the push stopped before it.
  final int waiting;

  /// Set when the push stopped early: nobody to talk to, or the server said stop.
  final ApiFailure? stoppedBy;

  bool get complete => stoppedBy == null && refused.isEmpty && waiting == 0;
  int get sent => worksSent + quotesSent;
}

class PushRefusal {
  const PushRefusal(this.what, this.reason);

  /// "work 3", "quote 12": the phone's own id, so the line says which without quoting the reader's words.
  final String what;

  /// The server's reason (`{"error": ...}`), which is about the field, not the content.
  final String reason;
}

/// Sends the library to the paired server, once. What is already there (a `server_id`) is never sent again,
/// so running it twice sends nothing the second time, and a push that stopped half way carries on from
/// where it stopped.
///
/// PUSH ONLY. It never changes or deletes anything on the server, and never reads the server's library.
/// An edit made to an item after it was pushed does not go up either: that is a conflict question (which
/// side wins, per work and per quote, the owner's choice) that the pull step answers, not this one.
class PushSync {
  PushSync(this._store, this._controller, {this._log});

  final LibraryStore _store;
  final AppController _controller;
  final AppLog? _log;

  bool _running = false;
  bool get running => _running;

  /// How much there is to send.
  Future<({int works, int quotes})> pending() async => (
    works: (await _store.unsyncedWorks()).length,
    quotes: (await _store.unsyncedQuotes()).length,
  );

  /// Pushes everything not yet on the server. [onProgress] gets (done, total) after each item.
  Future<PushResult> push({void Function(int done, int total)? onProgress}) {
    if (_running) throw StateError('a push is already running');
    _running = true;
    return _push(onProgress).whenComplete(() => _running = false);
  }

  Future<PushResult> _push(void Function(int, int)? onProgress) async {
    if (!_controller.paired) {
      return const PushResult(stoppedBy: ApiFailure.unauthorised);
    }
    final works = await _store.unsyncedWorks();
    final quotes = await _store.unsyncedQuotes();
    final byId = {for (final w in await _store.works()) w.id: w};
    final total = works.length + quotes.length;
    var done = 0;
    var worksSent = 0, quotesSent = 0, already = 0, handled = 0, waiting = 0;
    final refused = <PushRefusal>[];
    final refusedWorks = <int>{};
    ApiFailure? stopped;

    void tick() => onProgress?.call(++done, total);

    // A work first: its quotes need its id on the server.
    for (final w in works) {
      final outcome = await _send(
        _controller,
        _isScreen(w.kind) ? '/movies' : '/books',
        _workBody(w),
      );
      if (outcome.stopped != null) {
        stopped = outcome.stopped;
        break;
      }
      if (outcome.id != null) {
        await _store.setWorkServerId(w.id, outcome.id!);
        // What went up is what both sides now agree on.
        await _store.markWorkSynced(w.id, fingerprint(workFields(w)));
        worksSent++;
      } else {
        refused.add(PushRefusal('work ${w.id}', outcome.reason));
        refusedWorks.add(w.id);
      }
      tick();
    }

    if (stopped == null) {
      for (final q in quotes) {
        final work = q.workId == null ? null : byId[q.workId];
        final serverWork = work == null
            ? null
            : (await _store.work(work.id))?.serverId;
        if (q.workId != null && (work == null || serverWork == null)) {
          // Its work was refused (or is gone): there is nothing to hang the quote on.
          waiting++;
          handled++;
          tick();
          continue;
        }
        final outcome = await _send(
          _controller,
          _quotePath(work),
          _quoteBody(q, work, serverWork),
        );
        if (outcome.stopped != null) {
          stopped = outcome.stopped;
          break;
        }
        handled++;
        if (outcome.id != null) {
          await _store.setQuoteServerId(q.id, outcome.id!);
          if (outcome.duplicate) {
            // The server's copy may read differently: no agreement is recorded, so the first pull compares.
            already++;
          } else {
            await _store.markQuoteSynced(
              q.id,
              fingerprint(quoteFields(q, realmOfQuote(work))),
            );
            quotesSent++;
          }
        } else {
          refused.add(PushRefusal('quote ${q.id}', outcome.reason));
        }
        tick();
      }
    }
    // A stop leaves the rest of the quotes untried: they go up the next time.
    if (stopped != null) waiting += quotes.length - handled;

    final result = PushResult(
      worksSent: worksSent,
      quotesSent: quotesSent,
      alreadyThere: already,
      refused: refused,
      waiting: waiting,
      stoppedBy: stopped,
    );
    _log?.info(
      'push: ${result.worksSent} works and ${result.quotesSent} quotes sent, '
      '${result.alreadyThere} already there, ${refused.length} refused, '
      '${result.waiting} waiting${stopped == null ? '' : ', stopped by $stopped'}',
    );
    for (final r in refused) {
      _log?.warn('push: ${r.what} refused: ${r.reason}');
    }
    return result;
  }

  static String _quotePath(Work? w) => w == null
      ? '/quotes'
      : (_isScreen(w.kind) ? '/dialogues' : '/annotations');

  static bool _isScreen(WorkKind k) =>
      k == WorkKind.film || k == WorkKind.show || k == WorkKind.game;

  static Map<String, Object?> _workBody(Work w) => _isScreen(w.kind)
      ? {
          'title': w.title,
          'director': w.creator,
          'media_type': w.kind == WorkKind.film ? 'movie' : w.kind.name,
          if (w.year != null) 'release_year': w.year,
        }
      : {
          'title': w.title,
          'author': w.creator,
          'language': w.language,
          if (w.year != null) 'published_year': w.year,
        };

  /// What a quote carries on every route, in the server's names. The server accepts only `manual` and `ocr`
  /// as where a quote came from; the app's `capture` is the camera, which is `ocr`.
  static Map<String, Object?> _common(Quote q) => {
    'quote': q.text,
    'note': q.note,
    'translation': q.translation,
    'language': q.language,
    'color': q.color,
    'favorite': q.favorite,
    'tags': q.tags,
    'source': q.source == 'capture' ? 'ocr' : 'manual',
    'noted_at': q.notedAt.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _quoteBody(Quote q, Work? w, int? serverWork) {
    if (w == null) {
      // A quote with no work: the server's standalone quote. The occasion is what the app calls its chapter,
      // and the place its location, the same pairing the Markdown export uses.
      return {
        ..._common(q),
        'speaker': q.speaker,
        'occasion': q.chapter,
        'place': q.location,
      };
    }
    if (_isScreen(w.kind)) {
      return {
        ..._common(q),
        'movie_id': serverWork,
        'character': q.speaker,
        'timestamp': q.location,
      };
    }
    return {
      ..._common(q),
      'book_id': serverWork,
      'character': q.speaker,
      'chapter': q.chapter,
      'location': q.location,
    };
  }

  /// One POST. A 201 gives the new id; a 409 gives the row that is already there; a 400 is this item's
  /// problem and the push carries on; anything that means "stop" (no network, the token refused, rate
  /// limited, forbidden, the server failing) ends the push and is reported.
  Future<_Outcome> _send(
    AppController c,
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final answer = await c.withClient(
        (client) => client.postJson(path, body),
      );
      if (answer == null) {
        return const _Outcome(stopped: ApiFailure.badResponse);
      }
      final id = answer is Map ? answer['id'] : null;
      if (id is! int) return const _Outcome(stopped: ApiFailure.badResponse);
      return _Outcome(id: id);
    } on ApiException catch (e) {
      if (e.status == 409) {
        final existing = e.body is Map ? (e.body as Map)['existing'] : null;
        final id = existing is Map ? existing['id'] : null;
        if (id is int) return _Outcome(id: id, duplicate: true);
        return _Outcome(reason: e.detail.isEmpty ? 'a duplicate' : e.detail);
      }
      if (e.status == 400) {
        return _Outcome(reason: e.detail.isEmpty ? 'refused' : e.detail);
      }
      return _Outcome(stopped: e.failure);
    }
  }
}

class _Outcome {
  const _Outcome({
    this.id,
    this.duplicate = false,
    this.reason = '',
    this.stopped,
  });
  final int? id;
  final bool duplicate;
  final String reason;
  final ApiFailure? stopped;
}
