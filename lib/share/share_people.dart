import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';

/// One picture of a person or a character, with the name it belongs to.
class ShareFace {
  const ShareFace(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// What the server holds that the picture of a quote can use, the way the web's share dialog gathers it:
/// the portraits of the people credited (first credited first), the pictures of the characters (for a film,
/// show or game), and the credited person's signature.
class SharePeople {
  const SharePeople({
    this.faces = const [],
    this.characterFaces = const [],
    this.signature,
  });

  static const none = SharePeople();

  final List<ShareFace> faces;
  final List<ShareFace> characterFaces;
  final ShareFace? signature;

  bool get isEmpty =>
      faces.isEmpty && characterFaces.isEmpty && signature == null;
}

/// Where the pictures of people come from. An interface so a test can stand in for the server.
abstract class SharePeopleSource {
  bool get available;

  /// What the server has for [quote] (from [work], or of no work). Never throws: a server that cannot be
  /// reached, or has nothing, gives [SharePeople.none].
  Future<SharePeople> forQuote(Quote quote, Work? work);
}

/// The credited names split the way the web splits them by default: on commas, semicolons, `&` and `and`.
List<String> splitCredits(String credit) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in credit.split(RegExp(r'\s*(?:,|;|&|\band\b)\s*'))) {
    final n = part.trim();
    if (n.isNotEmpty && seen.add(n.toLowerCase())) out.add(n);
  }
  return out;
}

/// Gives the screens below it the [SharePeopleSource].
class PeopleScope extends InheritedWidget {
  const PeopleScope({super.key, required this.source, required super.child});

  final SharePeopleSource? source;

  static SharePeopleSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeopleScope>()?.source;

  @override
  bool updateShouldNotify(PeopleScope old) => old.source != source;
}

/// Reads people's pictures from the paired server: `GET /people?kind=&name=` for a portrait and a signature,
/// `GET /dialogues?movie_id=` for the pictures of a film's characters, and `GET /covers/<file>` for the files.
class PairedSharePeople implements SharePeopleSource {
  PairedSharePeople(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  static final _file = RegExp(r'^[A-Za-z0-9._-]+$');

  @override
  Future<SharePeople> forQuote(Quote quote, Work? work) async {
    if (!available) return SharePeople.none;
    try {
      final got = await _controller.withClient((c) => _gather(c, quote, work));
      return got ?? SharePeople.none;
    } on Object {
      return SharePeople.none;
    }
  }

  Future<SharePeople> _gather(ApiClient c, Quote q, Work? w) async {
    final screen =
        w != null &&
        (w.kind == WorkKind.film ||
            w.kind == WorkKind.show ||
            w.kind == WorkKind.game);
    final String kind;
    final List<String> names;
    if (w == null) {
      kind = 'speaker';
      names = splitCredits(q.speaker);
    } else if (screen) {
      kind = 'actor';
      names = [
        for (final chip in chipsFor(q, w))
          if (chip.kind == ChipKind.character && chip.actor.isNotEmpty)
            ...splitCredits(chip.actor),
      ];
    } else {
      kind = 'author';
      names = splitCredits(w.creator);
    }

    final faces = <ShareFace>[];
    ShareFace? signature;
    for (final name in names) {
      final person = await _person(c, kind, name);
      if (person == null) continue;
      final image = await _bytes(c, person['image_path']);
      if (image != null) faces.add(ShareFace(name, image));
      if (signature == null) {
        final sig = await _bytes(c, person['signature_path']);
        if (sig != null) signature = ShareFace(name, sig);
      }
    }

    final characters = <ShareFace>[];
    if (screen && q.serverId != null && w.serverId != null) {
      final rows = await c.getJson('/dialogues?movie_id=${w.serverId}');
      final list = rows is Map ? rows['dialogues'] : null;
      if (list is List) {
        for (final r in list) {
          if (r is Map && r['id'] == q.serverId) {
            final imgs = r['character_images'];
            if (imgs is List) {
              for (final i in imgs) {
                if (i is! Map) continue;
                final bytes = await _bytes(c, i['path']);
                if (bytes != null) {
                  characters.add(ShareFace('${i['name'] ?? ''}', bytes));
                }
              }
            }
            break;
          }
        }
      }
    }
    return SharePeople(
      faces: faces,
      characterFaces: characters,
      signature: signature,
    );
  }

  Future<Map?> _person(ApiClient c, String kind, String name) async {
    final r = await c.getJson(
      '/people?kind=$kind&name=${Uri.encodeQueryComponent(name)}',
    );
    if (r is Map && r['exists'] == true && r['person'] is Map) {
      return r['person'] as Map;
    }
    return null;
  }

  Future<Uint8List?> _bytes(ApiClient c, Object? file) async {
    if (file is! String || !_file.hasMatch(file)) return null;
    try {
      final b = await c.getBytes('/covers/$file');
      return b.isEmpty ? null : b;
    } on Object {
      return null;
    }
  }
}
