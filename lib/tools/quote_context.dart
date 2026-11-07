import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';
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
  PairedQuoteContext(this._controller);
  final AppController _controller;

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
    return serverCall<QuoteContext?>(_controller, (c) async {
      try {
        return QuoteContext.fromJson(
          await c.getJson('/quotes/$kind/$id/context${q.isEmpty ? '' : '?$q'}'),
        );
      } on ApiException catch (e) {
        // "this quote has no context": nothing stored, which is an answer and not a failure
        if (e.status == 404) return null;
        rethrow;
      }
    });
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
