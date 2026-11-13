import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'context_store.dart';
import '../sync/fingerprint.dart';

/// The lines around a quote in the file it came from, as the server stored them when the quote was found there: the
/// paragraphs (or, for a film, the subtitle lines) before and after, and how much more is stored.
class QuoteContext {
  const QuoteContext({
    required this.before,
    required this.body,
    required this.after,
    required this.unit,
    required this.shownBefore,
    required this.shownAfter,
    required this.storedBefore,
    required this.storedAfter,
    required this.boundBefore,
    required this.boundAfter,
  });

  final String before;

  /// The quote as the file has it (which may read a little differently from the quote the reader saved).
  final String body;
  final String after;

  /// "paragraph" for a book, "cue" for a film's subtitles.
  final String unit;

  /// How many units are shown before and after, and the most the server stored on each side.
  final int shownBefore, shownAfter, storedBefore, storedAfter;

  /// The window stops at a chapter edge, a long silence or the end of the work, not because of the setting.
  final bool boundBefore, boundAfter;

  bool get canShowMoreBefore => shownBefore < storedBefore;
  bool get canShowMoreAfter => shownAfter < storedAfter;

  String get unitWord => unit == 'cue' ? 'line' : 'paragraph';

  /// Reads the server's answer. Null when it is not in the shape of one.
  static QuoteContext? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    int n(Object? m, String k) =>
        m is Map && m[k] is num ? (m[k] as num).toInt() : 0;
    if (j['body'] is! String) return null;
    return QuoteContext(
      before: s('before').trim(),
      body: s('body').trim(),
      after: s('after').trim(),
      unit: s('unit'),
      shownBefore: n(j['span'], 'before'),
      shownAfter: n(j['span'], 'after'),
      storedBefore: n(j['stored'], 'before'),
      storedAfter: n(j['stored'], 'after'),
      boundBefore: j['bound_before'] == true,
      boundAfter: j['bound_after'] == true,
    );
  }
}

/// The server's word for where a quote lives, for its context route.
String contextKindOf(Realm realm) => switch (realm) {
  Realm.book => 'annotation',
  Realm.screen => 'dialogue',
  Realm.loose => 'utterance',
};

/// Where a quote's stored context comes from. An interface so a test can stand in for the server.
abstract class QuoteContextSource {
  /// The context stored for [quote] (from [work], or null for a standalone quote), widened to [before] and [after]
  /// units where given. Null when the server has none for it (the quote was not found in a file) or it is not on the
  /// server yet. Throws [ServerException] when the server could not be asked.
  Future<QuoteContext?> fetch(
    Quote quote,
    Work? work, {
    int? before,
    int? after,
  });
}

class PairedQuoteContext implements QuoteContextSource {
  PairedQuoteContext(this._controller, {this._store});
  final AppController _controller;
  final ContextStore? _store;

  /// The key a quote's context is kept under.
  static String keyOf(String kind, int serverId) => '$kind-$serverId';

  /// How long a note that a quote has no context is believed before the server is asked again.
  static const _noneFor = Duration(days: 7);

  /// How long a kept context is believed before the server is asked again.
  static const _keptFor = Duration(days: 30);

  @override
  Future<QuoteContext?> fetch(
    Quote quote,
    Work? work, {
    int? before,
    int? after,
  }) async {
    final id = quote.serverId;
    if (id == null) return null;
    final kind = contextKindOf(realmOfQuote(work));
    final q = [
      if (before != null) 'before=$before',
      if (after != null) 'after=$after',
    ].join('&');
    final path = '/quotes/$kind/$id/context${q.isEmpty ? '' : '?$q'}';
    final key = keyOf(kind, id);
    return serverCall<QuoteContext?>(_controller, (c) async {
      try {
        final answer = await c.getJson(path);
        final context = QuoteContext.fromJson(answer);
        if (context != null) await _keep(key, jsonEncode(answer));
        return context;
      } on ApiException catch (e) {
        // "this quote has no context": nothing stored, which is an answer and not a failure
        if (e.status == 404) {
          await _store?.write(key, StoredContext.none(DateTime.now()));
          return null;
        }
        // With no server, whatever window was asked for is answered with the widest one kept for the quote: more
        // than was asked is better than nothing, and the answer says how much it shows.
        if (e.failure == ApiFailure.network ||
            e.failure == ApiFailure.timeout) {
          final kept = await _store?.read(key);
          if (kept != null) {
            return kept.none
                ? null
                : QuoteContext.fromJson(jsonDecode(kept.body!));
          }
        }
        rethrow;
      }
    });
  }

  /// Keeps [body] unless a wider answer is already kept.
  Future<void> _keep(String key, String body) async {
    final store = _store;
    if (store == null) return;
    final have = await store.read(key);
    // The widest window stays while what is kept is fresh. Once it is old the new answer replaces it, even a
    // narrower one: the server's context may have been edited, and what was widened by hand is read again the
    // next time the reader widens it.
    final stale =
        have != null && DateTime.now().difference(have.at) >= _keptFor;
    final wider =
        !stale && have != null && !have.none && have.body!.length > body.length;
    await store.write(
      key,
      StoredContext(at: DateTime.now(), body: wider ? have.body! : body),
    );
  }

  /// Whether the context of the quote is already on the phone (or the server was lately told to have none).
  Future<bool> kept(String kind, int serverId) async {
    final have = await _store?.read(keyOf(kind, serverId));
    if (have == null) return false;
    final age = DateTime.now().difference(have.at);
    // a kept context is read again after a month, so one edited on the server reaches the phone
    return age < (have.none ? _noneFor : _keptFor);
  }

  /// The server ids of the quotes of one work that have a stored context (`/sources/context-ids`), or of all the
  /// standalone quotes when [workId] is null. Null when the server could not be asked.
  Future<Set<int>?> idsWithContext(String subject, int? workId) async {
    try {
      final r = await _controller.withClient(
        (c) => c.getJson(
          '/sources/context-ids?subject=$subject'
          '${workId == null ? '' : '&subject_id=$workId'}',
        ),
      );
      final ids = r is Map ? r['ids'] : null;
      if (ids is! List) return null;
      return {
        for (final x in ids)
          if (x is num) x.toInt(),
      };
    } on ApiException {
      return null;
    }
  }
}

/// Gives the quote screen the [QuoteContextSource] without every screen taking one.
class ContextScope extends InheritedWidget {
  const ContextScope({super.key, required this.source, required super.child});

  final QuoteContextSource? source;

  static QuoteContextSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContextScope>()?.source;

  @override
  bool updateShouldNotify(ContextScope old) => old.source != source;
}

/// Keeps the context of every synced quote on the phone, so they read with no server (ADR-0022). The server says
/// which quotes of each work have one, so a quote with none is not asked about; only what is not kept yet is
/// fetched, up to [limit] a run, and the rest follows at the next sync. Returns how many contexts were fetched.
Future<int> keepContexts(
  LibraryStore library,
  PairedQuoteContext source, {
  int limit = 150,
}) async {
  var fetched = 0;
  Future<bool> keepOf(Work? work, int? workServerId) async {
    final subject = work == null
        ? 'utterance'
        : (realmOfQuote(work) == Realm.screen ? 'screen' : 'book');
    if (work != null && workServerId == null) {
      // not on the server yet: nothing to ask
      return true;
    }
    final ids = await source.idsWithContext(subject, workServerId);
    if (ids == null) {
      // the server cannot be asked: try again at the next sync
      return false;
    }
    final kind = contextKindOf(realmOfQuote(work));
    for (var offset = 0; ; offset += 200) {
      final page = await library.quotes(
        workId: work?.id,
        standalone: work == null,
        limit: 200,
        offset: offset,
      );
      for (final q in page) {
        final id = q.serverId;
        if (id == null || !ids.contains(id)) continue;
        if (await source.kept(kind, id)) continue;
        if (fetched >= limit) return true;
        try {
          await source.fetch(q, work);
          fetched++;
        } on ServerException {
          return false;
        }
      }
      if (page.length < 200) return true;
    }
  }

  for (final w in await library.works()) {
    if (fetched >= limit) break;
    if (!await keepOf(w, w.serverId)) return fetched;
  }
  if (fetched < limit) await keepOf(null, null);
  return fetched;
}
