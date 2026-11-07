import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
String _s(Object? v) => v == null ? '' : '$v';

/// A work a person or character is in, as the console lists it.
class WorkRef {
  const WorkRef({required this.kind, required this.title, this.id = 0});
  final String kind, title;
  final int id;
}

List<WorkRef> _works(Object? v) => [
  if (v is List)
    for (final x in v)
      if (x is Map && _s(x['title']).isNotEmpty)
        WorkRef(kind: _s(x['kind']), title: _s(x['title']), id: _int(x['id'])),
];

/// One person in the metadata console: the record the server keeps, with how much of the library points at it.
class PersonRecord {
  const PersonRecord({
    required this.id,
    required this.name,
    this.kinds = const [],
    this.image = '',
    this.signature = '',
    this.sortName = '',
    this.spellings = const [],
    this.works = 0,
    this.quotes = 0,
    this.born = '',
    this.died = '',
    this.worksIn = const [],
    this.noPhoto = false,
    this.noLinks = false,
  });

  final int id;
  final String name, image, signature, sortName, born, died;
  final List<String> kinds, spellings;
  final int works, quotes;
  final List<WorkRef> worksIn;
  final bool noPhoto, noLinks;

  static PersonRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = _s(j['name']);
    if (name.isEmpty) return null;
    return PersonRecord(
      id: _int(j['id']),
      name: name,
      kinds: [
        if (j['kinds'] is List)
          for (final k in j['kinds'] as List) '$k',
      ],
      image: _s(j['image_path']),
      signature: _s(j['signature_path']),
      sortName: _s(j['sort_name']),
      spellings: [
        if (j['spellings'] is List)
          for (final k in j['spellings'] as List) '$k',
      ],
      works: _int(j['works']),
      quotes: _int(j['quotes']),
      born: _s(j['born']),
      died: _s(j['died']),
      worksIn: _works(j['works_in']),
      noPhoto: j['no_photo'] == true || _s(j['image_path']).isEmpty,
      noLinks: j['no_links'] == true,
    );
  }
}

/// One character in the console.
class CharacterRecord {
  const CharacterRecord({
    required this.id,
    required this.name,
    this.sortName = '',
    this.description = '',
    this.image = '',
    this.note = '',
    this.links = '',
    this.born = '',
    this.works = 0,
    this.quotes = 0,
    this.worksIn = const [],
  });

  final int id;
  final String name, sortName, description, image, note, links, born;
  final int works, quotes;
  final List<WorkRef> worksIn;

  static CharacterRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = _s(j['name']);
    if (name.isEmpty) return null;
    return CharacterRecord(
      id: _int(j['id']),
      name: name,
      sortName: _s(j['sort_name']),
      description: _s(j['description']),
      image: _s(j['image_path']),
      note: _s(j['note']),
      links: _s(j['links']),
      born: _s(j['born']),
      works: _int(j['works']),
      quotes: _int(j['quotes']),
      worksIn: _works(j['works_in']),
    );
  }
}

/// The fields of a character that can be changed; a null one is left as it is.
class CharacterEdit {
  const CharacterEdit({
    this.name,
    this.sortName,
    this.description,
    this.note,
    this.links,
    this.born,
  });

  final String? name, sortName, description, note, links, born;

  Map<String, Object?> toJson() => {
    'name': ?name,
    'sort_name': ?sortName,
    'description': ?description,
    'note': ?note,
    'links': ?links,
    'born': ?born,
  };
}

/// What is saved but belongs to nothing any more.
class Orphans {
  const Orphans({this.people = 0, this.characters = 0});
  final int people, characters;
  int get total => people + characters;
}

/// The whole of people and characters, for the metadata console: every record, merging, removing, spellings, and
/// characters made and changed here. An interface so a test can stand in for the server. Every call throws a
/// [ServerException] (with words for the reader) when it cannot be done.
abstract class PeopleConsole {
  bool get available;

  Future<List<PersonRecord>> people();
  Future<List<CharacterRecord>> characters();

  /// Folds [drop] into [keep]: everything that pointed at [drop] points at [keep], and [drop]'s name becomes a spelling.
  Future<void> mergePeople(int keep, int drop);
  Future<void> mergeCharacters(int keep, int drop);

  Future<void> deletePerson(int id);
  Future<void> deleteCharacter(int id);

  /// Makes a character and returns its id.
  Future<int> createCharacter(String name, {String description = ''});
  Future<void> saveCharacter(int id, CharacterEdit edit);
  Future<void> uploadCharacterImage(int id, Uint8List bytes, String fileName);
  Future<void> clearCharacterImage(int id);

  /// Replaces every spelling of a record: the first line is the name it prints under, the rest are what else it is
  /// called. [character] says which table.
  Future<void> setNames({
    required bool character,
    required int id,
    required List<String> names,
  });

  /// Turns one spelling of a record into a record of its own.
  Future<void> splitSpelling({
    required bool character,
    required int id,
    required String alias,
  });

  Future<Orphans> orphans();

  /// Removes the people and characters nothing points at.
  Future<void> prune();

  /// Asks the server to fetch a portrait and details for everyone who has none (a job).
  Future<void> fetchMissing();
}

/// The paired server's people and characters.
class PairedPeopleConsole implements PeopleConsole {
  PairedPeopleConsole(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  @override
  Future<List<PersonRecord>> people() => serverCall(_controller, (c) async {
    final r = await c.getJson('/people/records');
    final list = r is Map ? r['people'] : null;
    return [
      if (list is List)
        for (final x in list)
          if (PersonRecord.fromJson(x) != null) PersonRecord.fromJson(x)!,
    ];
  });

  @override
  Future<List<CharacterRecord>> characters() => serverCall(_controller, (
    c,
  ) async {
    final r = await c.getJson('/characters');
    final list = r is Map ? r['characters'] : null;
    return [
      if (list is List)
        for (final x in list)
          if (CharacterRecord.fromJson(x) != null) CharacterRecord.fromJson(x)!,
    ];
  });

  @override
  Future<void> mergePeople(int keep, int drop) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/people/merge', {'keep_id': keep, 'drop_id': drop});
      });

  @override
  Future<void> mergeCharacters(int keep, int drop) => serverCall<void>(
    _controller,
    (c) async {
      await c.postJson('/characters/merge', {'keep_id': keep, 'drop_id': drop});
    },
  );

  @override
  Future<void> deletePerson(int id) => serverCall<void>(_controller, (c) async {
    await c.delete('/people/$id');
  });

  @override
  Future<void> deleteCharacter(int id) =>
      serverCall<void>(_controller, (c) async {
        await c.delete('/characters/$id');
      });

  @override
  Future<int> createCharacter(String name, {String description = ''}) =>
      serverCall(_controller, (c) async {
        final r = await c.postJson('/characters', {
          'name': name,
          if (description.isNotEmpty) 'description': description,
        });
        return r is Map ? _int(r['id']) : 0;
      });

  @override
  Future<void> saveCharacter(int id, CharacterEdit edit) =>
      serverCall<void>(_controller, (c) async {
        await c.putJson('/characters/$id', edit.toJson());
      });

  @override
  Future<void> uploadCharacterImage(int id, Uint8List bytes, String fileName) =>
      serverCall<void>(_controller, (c) async {
        await c.postFile(
          '/characters/$id/image/upload',
          'file',
          bytes,
          fileName,
        );
      });

  @override
  Future<void> clearCharacterImage(int id) =>
      serverCall<void>(_controller, (c) async {
        await c.putJson('/characters/$id/image', {'path': ''});
      });

  @override
  Future<void> setNames({
    required bool character,
    required int id,
    required List<String> names,
  }) => serverCall<void>(_controller, (c) async {
    final table = character ? 'characters' : 'people/id';
    await c.putJson('/$table/$id/names', {'text': names.join('\n')});
  });

  @override
  Future<void> splitSpelling({
    required bool character,
    required int id,
    required String alias,
  }) => serverCall<void>(_controller, (c) async {
    final table = character ? 'characters' : 'people/id';
    await c.postJson('/$table/$id/split', {'alias': alias});
  });

  @override
  Future<Orphans> orphans() => serverCall(_controller, (c) async {
    final r = await c.getJson('/people/orphans');
    int n(Object? v) => v is List ? v.length : 0;
    return r is Map
        ? Orphans(people: n(r['people']), characters: n(r['characters']))
        : const Orphans();
  });

  @override
  Future<void> prune() => serverCall<void>(_controller, (c) async {
    await c.postJson('/people/prune', const {});
  });

  @override
  Future<void> fetchMissing() => serverCall<void>(_controller, (c) async {
    await c.postJson('/jobs', {
      'kind': 'people',
      'params': {'missing': true},
    });
  });
}

/// Gives the screens below it the [PeopleConsole].
class PeopleConsoleScope extends InheritedWidget {
  const PeopleConsoleScope({
    super.key,
    required this.console,
    required super.child,
  });

  final PeopleConsole? console;

  static PeopleConsole? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeopleConsoleScope>()?.console;

  @override
  bool updateShouldNotify(PeopleConsoleScope old) => old.console != console;
}
