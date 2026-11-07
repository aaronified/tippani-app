import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';
import '../people/people_directory.dart';
import '../people/svg_raster.dart';

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
  PairedSharePeople(this._controller, [this._directory]);

  final AppController _controller;

  /// The phone's own copy of everyone's pictures; used first, so a picture can be made with no server in reach.
  final PeopleDirectory? _directory;

  @override
  bool get available => _controller.paired || _directory != null;

  static final _file = RegExp(r'^[A-Za-z0-9._-]+$');

  @override
  Future<SharePeople> forQuote(Quote quote, Work? work) async {
    if (!available) return SharePeople.none;
    try {
      await _directory?.ready();
      if (!_controller.paired) return await _gather(null, quote, work);
      final got = await _controller.withClient((c) => _gather(c, quote, work));
      return got ?? await _gather(null, quote, work);
    } on Object {
      return SharePeople.none;
    }
  }

  /// A picture the phone already holds (read from its own copy), or null.
  Future<Uint8List?> _held(String name) async {
    if (name.isEmpty) return null;
    try {
      final f = await _directory?.file(name);
      if (f == null) return null;
      final b = await f.readAsBytes();
      if (b.isEmpty) return null;
      return looksLikeSvg(b) ? await svgToPng(b) : b;
    } on Object {
      return null;
    }
  }

  Future<SharePeople> _gather(ApiClient? c, Quote q, Work? w) async {
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
      final held = _directory?.person(kind, name);
      Uint8List? image, sig;
      if (held != null) {
        image = await _held(held.image);
        if (signature == null) sig = await _held(held.signature);
      }
      if (c != null && (image == null || (signature == null && sig == null))) {
        final person = await _person(c, kind, name);
        if (person != null) {
          image ??= await _bytes(c, person['image_path']);
          if (signature == null) {
            sig ??= await _bytes(c, person['signature_path']);
          }
        }
      }
      if (image != null) faces.add(ShareFace(name, image));
      if (signature == null && sig != null) signature = ShareFace(name, sig);
    }

    final characters = <ShareFace>[];
    // the pictures of the characters named as speaking, from the phone's copy (a book has them too)
    for (final name in speakerNames(q.speaker)) {
      final bytes = await _held(_directory?.characterImage(name) ?? '');
      if (bytes != null) characters.add(ShareFace(name, bytes));
    }
    if (c != null &&
        characters.isEmpty &&
        screen &&
        q.serverId != null &&
        w.serverId != null) {
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
      if (b.isEmpty) return null;
      // a signature is often a vector picture; the share picture draws bitmaps, so draw it into one here
      return looksLikeSvg(b) ? await svgToPng(b) : b;
    } on Object {
      return null;
    }
  }
}
