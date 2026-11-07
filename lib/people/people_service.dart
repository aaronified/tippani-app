import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';
import '../l10n/l10n.dart';

/// One work a person is credited on (a book they wrote, a film they directed).
class PersonCredit {
  const PersonCredit({
    required this.kind,
    required this.workId,
    required this.title,
    this.role = '',
    this.cover = '',
    this.year = 0,
    this.mediaType = '',
  });

  /// 'book' or 'movie'.
  final String kind;
  final int workId;
  final String title;
  final String role;
  final String cover;
  final int year;
  final String mediaType;

  static PersonCredit? fromJson(Object? j) {
    if (j is! Map) return null;
    final title = '${j['title'] ?? ''}';
    if (title.isEmpty) return null;
    return PersonCredit(
      kind: '${j['kind'] ?? ''}',
      workId: _int(j['work_id']),
      title: title,
      role: '${j['role'] ?? ''}',
      cover: '${j['cover'] ?? ''}',
      year: _int(j['year']),
      mediaType: '${j['media_type'] ?? ''}',
    );
  }
}

/// One cast row: a character in a work and who played them.
class CastAppearance {
  const CastAppearance({
    required this.kind,
    required this.workId,
    required this.workTitle,
    this.character = '',
    this.actor = '',
    this.actorImage = '',
    this.characterImage = '',
  });

  final String kind;
  final int workId;
  final String workTitle;
  final String character;
  final String actor;
  final String actorImage;
  final String characterImage;

  static CastAppearance? fromJson(Object? j) {
    if (j is! Map) return null;
    return CastAppearance(
      kind: '${j['kind'] ?? ''}',
      workId: _int(j['work_id']),
      workTitle: '${j['work_title'] ?? ''}',
      character: '${j['character'] ?? ''}',
      actor: '${j['actor'] ?? ''}',
      actorImage: '${j['actor_image'] ?? ''}',
      characterImage:
          '${j['character_image'] ?? j['character_image_path'] ?? ''}',
    );
  }
}

/// One quote a person or character is linked to.
class LineOf {
  const LineOf({
    required this.id,
    required this.text,
    this.name = '',
    this.workId = 0,
    this.workTitle = '',
    this.favourite = false,
  });

  final int id;
  final String text;

  /// How the quote spells the person or character.
  final String name;
  final int workId;
  final String workTitle;
  final bool favourite;

  static LineOf? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}';
    if (text.isEmpty) return null;
    return LineOf(
      id: _int(j['id']),
      text: text,
      name: '${j['name'] ?? ''}',
      workId: _int(j['work_id']),
      workTitle: '${j['work_title'] ?? ''}',
      favourite: j['favorite'] == true,
    );
  }
}

/// A link on a person or character: its address and where it points (a provider's name, or the host).
class PageLink {
  const PageLink(this.url, this.label);

  final String url;
  final String label;
}

/// The providers a link is recognised by, in the order the web lists them: a name for the chip.
final _providers = <(String, String)>[
  (r'(^|\.)imdb\.com$', 'IMDb'),
  (r'(^|\.)themoviedb\.org$', 'TMDB'),
  (r'(^|\.)thetvdb\.com$', 'TheTVDB'),
  (r'(^|\.)letterboxd\.com$', 'Letterboxd'),
  (r'(^|\.)igdb\.com$', 'IGDB'),
  (r'(^|\.)wikipedia\.org$', 'Wikipedia'),
  (r'(^|\.)(fandom|wikia)\.com$', 'Fandom'),
  (r'(^|\.)wikidata\.org$', 'Wikidata'),
  (r'(^|\.)wikimedia\.org$', 'Wikimedia'),
  (r'(^|\.)openlibrary\.org$', tx('vocab.source.openlibrary.label')),
  (r'^books\.google\.[a-z.]+$', tx('vocab.source.google.label')),
  (r'(^|\.)amazon\.[a-z.]+$', 'Amazon'),
];

/// The stored links field (free text, an address per line, an optional ` | name` after it) as chips: a recognised
/// provider gets its name, anything else the host, a name the reader gave wins.
List<PageLink> parseLinks(String text) {
  final out = <PageLink>[];
  final seen = <String>{};
  for (final line in text.split('\n')) {
    final cut = line.indexOf('|');
    final head = cut < 0 ? line : line.substring(0, cut);
    final label = cut < 0 ? '' : line.substring(cut + 1).trim();
    final tokens = head
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      final uri = Uri.tryParse(tok);
      if (uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          uri.host.isEmpty ||
          !seen.add(tok)) {
        continue;
      }
      var name = '';
      if (i == tokens.length - 1) name = label;
      if (name.isEmpty) {
        for (final (re, n) in _providers) {
          if (RegExp(re, caseSensitive: false).hasMatch(uri.host)) {
            name = n;
            break;
          }
        }
      }
      out.add(
        PageLink(
          tok,
          name.isEmpty ? uri.host.replaceFirst(RegExp(r'^www\.'), '') : name,
        ),
      );
    }
  }
  return out;
}

/// Everything the server holds about one person.
class PersonDetail {
  const PersonDetail({
    required this.id,
    required this.name,
    this.kinds = const [],
    this.bio = '',
    this.born = '',
    this.died = '',
    this.links = '',
    this.note = '',
    this.image = '',
    this.imageSource = '',
    this.signature = '',
    this.signatureSource = '',
    this.aliases = const [],
    this.credits = const [],
    this.roles = const [],
    this.lines = const [],
    this.sharedLines = 0,
    this.quotes = 0,
    this.favourites = 0,
  });

  final int id;
  final String name;
  final List<String> kinds;
  final String bio, born, died, links, note;
  final String image, imageSource, signature, signatureSource;
  final List<String> aliases;
  final List<PersonCredit> credits;
  final List<CastAppearance> roles;
  final List<LineOf> lines;
  final int sharedLines, quotes, favourites;

  static PersonDetail? fromJson(Object? j) {
    if (j is! Map) return null;
    return PersonDetail(
      id: _int(j['id']),
      name: '${j['name'] ?? ''}',
      kinds: _strings(j['kinds']),
      bio: '${j['bio'] ?? ''}',
      born: '${j['born'] ?? ''}',
      died: '${j['died'] ?? ''}',
      links: '${j['links'] ?? ''}',
      note: '${j['note'] ?? ''}',
      image: '${j['image_path'] ?? ''}',
      imageSource: '${j['image_source'] ?? ''}',
      signature: '${j['signature_path'] ?? ''}',
      signatureSource: '${j['signature_source'] ?? ''}',
      aliases: _strings(j['aliases']),
      credits: _list(j['credits'], PersonCredit.fromJson),
      roles: _list(j['roles'], CastAppearance.fromJson),
      lines: _list(j['lines'], LineOf.fromJson),
      sharedLines: _int(j['shared_lines']),
      quotes: _int(j['quotes']),
      favourites: _int(j['favourites']),
    );
  }
}

/// Everything the server holds about one character.
class CharacterDetail {
  const CharacterDetail({
    required this.id,
    required this.name,
    this.description = '',
    this.born = '',
    this.links = '',
    this.note = '',
    this.image = '',
    this.aliases = const [],
    this.appearances = const [],
    this.lines = const [],
    this.sharedLines = 0,
    this.quotes = 0,
    this.favourites = 0,
  });

  final int id;
  final String name;
  final String description, born, links, note, image;
  final List<String> aliases;
  final List<CastAppearance> appearances;
  final List<LineOf> lines;
  final int sharedLines, quotes, favourites;

  static CharacterDetail? fromJson(Object? j) {
    if (j is! Map) return null;
    return CharacterDetail(
      id: _int(j['id']),
      name: '${j['name'] ?? ''}',
      description: '${j['description'] ?? ''}',
      born: '${j['born'] ?? ''}',
      links: '${j['links'] ?? ''}',
      note: '${j['note'] ?? ''}',
      image: '${j['image_path'] ?? ''}',
      aliases: _strings(j['aliases']),
      appearances: _list(j['appearances'], CastAppearance.fromJson),
      lines: _list(j['lines'], LineOf.fromJson),
      sharedLines: _int(j['shared_lines']),
      quotes: _int(j['quotes']),
      favourites: _int(j['favourites']),
    );
  }
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

List<String> _strings(Object? v) => v is List
    ? [
        for (final x in v)
          if ('$x'.isNotEmpty) '$x',
      ]
    : const [];

List<T> _list<T>(Object? v, T? Function(Object?) from) => v is List
    ? [
        for (final x in v)
          if (from(x) != null) from(x) as T,
      ]
    : const [];

/// The fields of a person that can be changed from the phone; a null one is left as it is.
class PersonEdit {
  const PersonEdit({
    this.name,
    this.bio,
    this.born,
    this.died,
    this.links,
    this.note,
  });

  final String? name, bio, born, died, links, note;

  Map<String, Object?> toJson() => {
    'name': ?name,
    'bio': ?bio,
    'born': ?born,
    'died': ?died,
    'links': ?links,
    'note': ?note,
  };
}

/// Where the pages of people and characters come from, and where edits to a person go. An interface so a test can
/// stand in for the server. Every call throws a [ServerException] (with words for the reader) when it cannot be done.
abstract class PeopleService {
  /// Whether the server can be asked right now.
  bool get available;

  Future<PersonDetail?> person(int id);
  Future<CharacterDetail?> character(int id);

  /// Changes some fields of a person and returns the person as the server now has them.
  Future<PersonDetail?> save(int id, PersonEdit edit);

  /// Sets the portrait from a picture the reader chose.
  Future<void> uploadPortrait(int id, Uint8List bytes, String fileName);

  /// Takes the portrait away.
  Future<void> clearPortrait(int id);

  /// Asks the server's sources for a portrait, bio and dates; returns what it says it found.
  Future<String> fetch(int id);

  /// Sets the signature from a picture the reader chose.
  Future<void> uploadSignature(int id, Uint8List bytes, String fileName);

  /// Takes the signature away.
  Future<void> clearSignature(int id);
}

/// The paired server's people.
class PairedPeopleService implements PeopleService {
  PairedPeopleService(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  @override
  Future<PersonDetail?> person(int id) => serverCall<PersonDetail?>(
    _controller,
    (c) async => PersonDetail.fromJson(await c.getJson('/people/id/$id')),
  );

  @override
  Future<CharacterDetail?> character(int id) => serverCall<CharacterDetail?>(
    _controller,
    (c) async => CharacterDetail.fromJson(await c.getJson('/characters/$id')),
  );

  @override
  Future<PersonDetail?> save(int id, PersonEdit edit) =>
      serverCall<PersonDetail?>(_controller, (c) async {
        await c.putJson('/people/id/$id', edit.toJson());
        return PersonDetail.fromJson(await c.getJson('/people/id/$id'));
      });

  @override
  Future<void> uploadPortrait(int id, Uint8List bytes, String fileName) =>
      serverCall<void>(_controller, (c) async {
        await c.postFile('/people/id/$id/portrait', 'file', bytes, fileName);
      });

  @override
  Future<void> clearPortrait(int id) =>
      serverCall<void>(_controller, (c) async {
        await c.putJson('/people/id/$id', {'clear_image': true});
      });

  @override
  Future<String> fetch(int id) => serverCall<String>(_controller, (c) async {
    final r = await c.postJson('/people/id/$id/fetch', const {});
    final p = r is Map ? r['person'] : null;
    return p is Map
        ? tx('app.people_service.fetched_what_the_server_could_find')
        : 'Done.';
  });

  @override
  Future<void> uploadSignature(int id, Uint8List bytes, String fileName) =>
      serverCall<void>(_controller, (c) async {
        await c.postFile('/people/id/$id/signature', 'file', bytes, fileName);
      });

  @override
  Future<void> clearSignature(int id) =>
      serverCall<void>(_controller, (c) async {
        await c.putJson('/people/id/$id', {'clear_signature': true});
      });
}

/// Gives the screens below it the [PeopleService].
class PeopleServiceScope extends InheritedWidget {
  const PeopleServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final PeopleService? service;

  static PeopleService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeopleServiceScope>()?.service;

  @override
  bool updateShouldNotify(PeopleServiceScope old) => old.service != service;
}
