// Runs the people console against a real Tippani server. Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are
// set. It makes its own people and characters (with a time-stamped name) and removes what it makes; it never prunes.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/people/people_console.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

// a real picture (the server turns away one too small to be a still)
final _png = File('assets/share/matte.png').readAsBytesSync();

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'people and characters: merge, spellings, split, pictures, removal',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        log: AppLog(),
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live console')).ok, isTrue);
      final console = PairedPeopleConsole(controller);
      final stamp = DateTime.now().millisecondsSinceEpoch;

      // people: two spellings of one person are made, listed with their counts, and merged
      Future<int> person(String name) async {
        final r = await controller.withClient(
          (c) => c.putJson('/people', {'kind': 'author', 'name': name}),
        );
        return (r as Map)['id'] as int;
      }

      final a = await person('Console Tester $stamp');
      final b = await person('C. Tester $stamp');
      var people = await console.people();
      expect(people.map((p) => p.id), containsAll([a, b]));

      await console.setNames(
        character: false,
        id: a,
        names: ['Console Tester $stamp', 'Tester, Console $stamp'],
      );
      people = await console.people();
      expect(people.firstWhere((p) => p.id == a).spellings, [
        'Tester, Console $stamp',
      ]);
      await console.splitSpelling(
        character: false,
        id: a,
        alias: 'Tester, Console $stamp',
      );
      people = await console.people();
      final split = people.firstWhere(
        (p) => p.name == 'Tester, Console $stamp',
      );
      expect(people.firstWhere((p) => p.id == a).spellings, isEmpty);

      await console.mergePeople(a, b);
      people = await console.people();
      expect(people.any((p) => p.id == b), isFalse, reason: 'folded into a');
      expect(
        people.firstWhere((p) => p.id == a).spellings,
        contains('C. Tester $stamp'),
      );
      await console.deletePerson(a);
      await console.deletePerson(split.id);
      people = await console.people();
      expect(people.any((p) => p.id == a || p.id == split.id), isFalse);

      // characters: made, changed, given a picture, merged, removed
      final c1 = await console.createCharacter(
        'Console Hero $stamp',
        description: 'First.',
      );
      final c2 = await console.createCharacter('Console Hero ($stamp)');
      await console.saveCharacter(
        c1,
        const CharacterEdit(description: 'Changed.', born: '1900'),
      );
      await console.uploadCharacterImage(c1, _png, 'still.png');
      var chars = await console.characters();
      final one = chars.firstWhere((c) => c.id == c1);
      expect(one.description, 'Changed.');
      expect(one.born, '1900');
      expect(one.image, isNotEmpty);
      await console.clearCharacterImage(c1);
      chars = await console.characters();
      expect(chars.firstWhere((c) => c.id == c1).image, isEmpty);

      await console.setNames(
        character: true,
        id: c1,
        names: ['Console Hero $stamp', 'The Hero $stamp'],
      );
      await console.mergeCharacters(c1, c2);
      chars = await console.characters();
      expect(chars.any((c) => c.id == c2), isFalse);
      await console.deleteCharacter(c1);
      chars = await console.characters();
      expect(chars.any((c) => c.id == c1), isFalse);

      // what nothing uses is counted (and left alone)
      final orphans = await console.orphans();
      expect(orphans.total, greaterThanOrEqualTo(0));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
