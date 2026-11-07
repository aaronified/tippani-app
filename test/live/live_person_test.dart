// Runs the people pages' code against a real Tippani server that has an author "Ursula Le Guin" (with a portrait and
// a signature) credited on a book, and a character "Shevek". Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE
// are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/people/people_directory.dart';
import 'package:tippani/people/people_service.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'a real server gives a person page, a character page and takes an edit',
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
      expect((await controller.pair(_code ?? '', 'live person')).ok, isTrue);

      final tmp = await Directory.systemTemp.createTemp('person');
      final directory = PairedPeopleDirectory(
        controller,
        CoverCache(controller, folder: Directory('${tmp.path}/covers')),
        folder: Directory('${tmp.path}/people'),
      );
      await directory.ready();
      final service = PairedPeopleService(controller);

      final info = directory.anyPerson('ursula le guin');
      expect(info, isNotNull);
      expect(info!.id, greaterThan(0));
      final person = await service.person(info.id);
      expect(person!.name, 'Ursula Le Guin');
      expect(person.credits.single.title, 'The Dispossessed');
      expect(person.signature, endsWith('.svg'));

      final saved = await service.save(
        info.id,
        const PersonEdit(bio: 'Wrote it.'),
      );
      expect(saved!.bio, 'Wrote it.');
      expect(
        saved.image,
        person.image,
        reason: 'an edit of one field leaves the rest',
      );

      final ch = directory.character('shevek');
      expect(ch, isNotNull);
      final character = await service.character(ch!.id);
      expect(character!.name, 'Shevek');
    },
    skip: skip,
  );
}
