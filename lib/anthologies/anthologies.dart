import '../api/api_client.dart';
import '../app_controller.dart';
import '../sync/fingerprint.dart';

/// A collection of quotes the reader has gathered and ordered, kept on the server.
class Anthology {
  const Anthology({
    required this.id,
    required this.title,
    required this.intro,
    required this.entries,
    required this.raw,
  });

  final int id;
  final String title;
  final String intro;

  /// How many passages it holds.
  final int entries;

  /// The server's whole row. An edit sends it back with only the title and introduction changed, so the
  /// display switches this app does not show are not wiped.
  final Map<String, Object?> raw;

  factory Anthology.fromJson(Map<String, Object?> j) => Anthology(
    id: (j['id'] as num).toInt(),
    title: (j['title'] as String?) ?? '',
    intro: (j['intro'] as String?) ?? '',
    entries: (j['entries'] as num?)?.toInt() ?? 0,
    raw: j,
  );
}

/// One passage in an anthology, as the server draws it.
class AnthologyEntry {
  const AnthologyEntry({
    required this.kind,
    required this.itemId,
    required this.quote,
    required this.note,
    required this.source,
    required this.credit,
    required this.color,
    required this.language,
    required this.locator,
  });

  /// "book", "screen" or "utterance": which of the server's tables [itemId] is in.
  final String kind;
  final int itemId;
  final String quote;

  /// The reader's commentary for this passage in this anthology.
  final String note;
  final String source;
  final String credit;
  final String color;
  final String language;
  final String locator;

  factory AnthologyEntry.fromJson(Map<String, Object?> j) => AnthologyEntry(
    kind: (j['kind'] as String?) ?? '',
    itemId: (j['item_id'] as num?)?.toInt() ?? 0,
    quote: (j['quote'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    source: (j['source'] as String?) ?? '',
    credit: (j['credit'] as String?) ?? '',
    color: (j['color'] as String?) ?? 'yellow',
    language: (j['language'] as String?) ?? '',
    locator: (j['locator'] as String?) ?? '',
  );

  /// Who and where it is from, on one line.
  String get from => [
    credit,
    source,
    locator,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
}

class AnthologyDetail {
  const AnthologyDetail(this.anthology, this.entries);
  final Anthology anthology;
  final List<AnthologyEntry> entries;
}

/// The server's word for where a quote lives, from the phone's: books and films are different tables.
String entryKindOf(Realm realm) => switch (realm) {
  Realm.book => 'book',
  Realm.screen => 'screen',
  Realm.loose => 'utterance',
};

/// Anything that went wrong with an anthology, in words for the reader.
class AnthologyException implements Exception {
  const AnthologyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the screens need of the server's anthologies. An interface so a test can stand in for the server.
abstract class AnthologyService {
  /// Whether there is a paired server to ask.
  bool get available;

  Future<List<Anthology>> list();
  Future<AnthologyDetail> get(int id);
  Future<Anthology> create(String title, String intro);

  /// Changes the title and introduction of [a], keeping everything else the server holds for it.
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  });
  Future<void> delete(int id);

  /// Adds the quote [itemId] (in the server's [kind] table) to the end of anthology [id]. False when it was
  /// already in it.
  Future<bool> add(int id, String kind, int itemId);
  Future<void> removeEntry(int id, String kind, int itemId);
}

/// The paired server's anthologies, through the app's own API client.
class ServerAnthologies implements AnthologyService {
  ServerAnthologies(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  Future<T> _call<T>(Future<T> Function(ApiClient c) run) async {
    if (!available) {
      throw const AnthologyException('This phone is not paired with a server.');
    }
    try {
      // withClient answers null only when nothing is paired (checked above); a call that returns nothing
      // (a delete) is a null that is not a failure.
      return await _controller.withClient(run) as T;
    } on ApiException catch (e) {
      throw AnthologyException(switch (e.failure) {
        ApiFailure.network => 'The server could not be reached.',
        ApiFailure.timeout => 'The server took too long to answer.',
        ApiFailure.unauthorised =>
          'The server no longer accepts this phone. Pair it again.',
        ApiFailure.forbidden => 'The server does not allow that.',
        ApiFailure.rateLimited => 'The server asks you to wait a moment.',
        ApiFailure.server || ApiFailure.badResponse =>
          e.detail.isNotEmpty ? e.detail : 'The server could not do that.',
      });
    }
  }

  Map<String, Object?> _map(Object? v) => v is Map
      ? Map<String, Object?>.from(v)
      : throw const AnthologyException('The server sent something unexpected.');

  @override
  Future<List<Anthology>> list() => _call((c) async {
    final body = _map(await c.getJson('/anthologies'));
    final all = body['anthologies'];
    if (all is! List) return <Anthology>[];
    return [for (final a in all) Anthology.fromJson(_map(a))];
  });

  @override
  Future<AnthologyDetail> get(int id) => _call((c) async {
    final body = _map(await c.getJson('/anthologies/$id'));
    final entries = body['entries'];
    return AnthologyDetail(Anthology.fromJson(_map(body['anthology'])), [
      if (entries is List)
        for (final e in entries) AnthologyEntry.fromJson(_map(e)),
    ]);
  });

  @override
  Future<Anthology> create(String title, String intro) => _call((c) async {
    final made = await c.postJson('/anthologies', {
      'title': title,
      'intro': intro,
    });
    return Anthology.fromJson(_map(made));
  });

  @override
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  }) => _call((c) async {
    // The server's PUT is the whole record; send back what it holds with the two fields changed.
    final body = Map<String, Object?>.from(a.raw)
      ..['title'] = title
      ..['intro'] = intro;
    await c.putJson('/anthologies/${a.id}', body);
  });

  @override
  Future<void> delete(int id) => _call((c) async {
    await c.delete('/anthologies/$id');
  });

  @override
  Future<bool> add(int id, String kind, int itemId) => _call((c) async {
    final r = await c.postJson('/anthologies/$id/entries', {
      'items': [
        {'kind': kind, 'item_id': itemId},
      ],
    });
    return r is Map && (r['added'] as num? ?? 0) > 0;
  });

  @override
  Future<void> removeEntry(int id, String kind, int itemId) => _call((c) async {
    await c.delete('/anthologies/$id/entries/$kind/$itemId');
  });
}
