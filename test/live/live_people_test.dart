// Runs the people code against a real Tippani server that has an author called "Ursula Le Guin" with a portrait
// and a signature (the signature as an SVG). Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/quote_chips.dart';
import 'package:tippani/people/people_directory.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/share/share_people.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'a real server gives the portrait, the vector signature and the pill face',
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
      final paired = await controller.pair(_code ?? '', 'live people');
      expect(paired.ok, isTrue);

      final work = Work(
        id: 1,
        kind: WorkKind.book,
        title: 'The Dispossessed',
        creator: 'Ursula Le Guin',
        year: 1974,
        language: 'en',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final quote = Quote(
        id: 1,
        workId: 1,
        text: 'x',
        translation: '',
        language: '',
        speaker: '',
        chapter: '',
        location: '',
        note: '',
        color: '',
        favorite: false,
        notedAt: DateTime.utc(2026),
        source: 'manual',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        tags: const [],
      );

      final people = await PairedSharePeople(controller).forQuote(quote, work);
      expect(people.faces, hasLength(1), reason: 'the portrait');
      expect(people.signature, isNotNull, reason: 'the signature (an SVG)');
      expect(people.signature!.bytes.sublist(1, 4), [
        0x50,
        0x4e,
        0x47,
      ], reason: 'drawn into a PNG');

      final tmp = await Directory.systemTemp.createTemp('people');
      final directory = PairedPeopleDirectory(
        controller,
        CoverCache(controller, folder: Directory('${tmp.path}/covers')),
        folder: Directory('${tmp.path}/people'),
      );
      await directory.refresh();
      final face = directory.faceOf(
        const QuoteChip(ChipKind.author, 'ursula le guin'),
      );
      expect(face, isNotEmpty);
      expect(await directory.file(face), isNotNull);
    },
    skip: skip,
  );
}
