import 'dart:typed_data';

import 'package:tippani/api/server_call.dart';
import 'package:tippani/people/people_console.dart';

/// People and characters kept in memory, so the console and the editing on a page can be tested without a server.
class FakeConsole implements PeopleConsole {
  @override
  bool available = true;

  final calls = <String>[];

  List<PersonRecord> peopleRows = [
    const PersonRecord(
      id: 1,
      name: 'Ursula Le Guin',
      kinds: ['author'],
      works: 2,
      quotes: 5,
      spellings: ['U. K. Le Guin'],
      noPhoto: true,
    ),
    const PersonRecord(
      id: 2,
      name: 'Ursula K. Le Guin',
      kinds: ['author'],
      works: 1,
      quotes: 1,
      image: '0123456789abcdef.png',
      noPhoto: false,
    ),
    const PersonRecord(
      id: 3,
      name: 'Humphrey Bogart',
      kinds: ['actor'],
      works: 1,
      quotes: 3,
      noLinks: true,
      noPhoto: true,
    ),
  ];
  List<CharacterRecord> characterRows = [
    const CharacterRecord(
      id: 7,
      name: 'Rick Blaine',
      works: 1,
      quotes: 2,
      worksIn: [WorkRef(kind: 'movie', title: 'Casablanca')],
    ),
  ];
  Orphans orphanCount = const Orphans(people: 1, characters: 2);
  String? refuse;

  void _maybe() {
    if (refuse != null) throw ServerException(refuse!);
  }

  @override
  Future<List<PersonRecord>> people() async => List.of(peopleRows);

  @override
  Future<List<CharacterRecord>> characters() async => List.of(characterRows);

  @override
  Future<void> mergePeople(int keep, int drop) async {
    calls.add('mergePeople $keep $drop');
    _maybe();
    peopleRows = [
      for (final p in peopleRows)
        if (p.id != drop) p,
    ];
  }

  @override
  Future<void> mergeCharacters(int keep, int drop) async {
    calls.add('mergeCharacters $keep $drop');
    _maybe();
    characterRows = [
      for (final c in characterRows)
        if (c.id != drop) c,
    ];
  }

  @override
  Future<void> deletePerson(int id) async {
    calls.add('deletePerson $id');
    _maybe();
    peopleRows = [
      for (final p in peopleRows)
        if (p.id != id) p,
    ];
  }

  @override
  Future<void> deleteCharacter(int id) async {
    calls.add('deleteCharacter $id');
    _maybe();
    characterRows = [
      for (final c in characterRows)
        if (c.id != id) c,
    ];
  }

  @override
  Future<int> createCharacter(String name, {String description = ''}) async {
    calls.add('createCharacter $name');
    _maybe();
    final id = 100 + characterRows.length;
    characterRows = [
      ...characterRows,
      CharacterRecord(id: id, name: name, description: description),
    ];
    return id;
  }

  @override
  Future<void> saveCharacter(int id, CharacterEdit edit) async {
    calls.add('saveCharacter $id ${edit.toJson()}');
    _maybe();
  }

  @override
  Future<void> uploadCharacterImage(
    int id,
    Uint8List bytes,
    String fileName,
  ) async {
    calls.add('uploadCharacterImage $id $fileName');
    _maybe();
  }

  @override
  Future<void> clearCharacterImage(int id) async {
    calls.add('clearCharacterImage $id');
    _maybe();
  }

  @override
  Future<void> setNames({
    required bool character,
    required int id,
    required List<String> names,
  }) async {
    calls.add('setNames ${character ? 'c' : 'p'}$id ${names.join('|')}');
    _maybe();
  }

  @override
  Future<void> splitSpelling({
    required bool character,
    required int id,
    required String alias,
  }) async {
    calls.add('split ${character ? 'c' : 'p'}$id $alias');
    _maybe();
  }

  @override
  Future<Orphans> orphans() async => orphanCount;

  @override
  Future<void> prune() async {
    calls.add('prune');
    orphanCount = const Orphans();
  }

  @override
  Future<void> fetchMissing() async => calls.add('fetchMissing');
}
