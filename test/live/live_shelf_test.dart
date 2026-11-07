// Moves a book on a real Tippani server's shelf. Needs a server whose book 1 is not yet finished. Skipped unless
// TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_details_source.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  HttpOverrides.global = null;
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;

  test(
    'the shelf: start, move on, finish, and be refused a bad move',
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
      expect((await controller.pair(_code ?? '', 'live shelf')).ok, isTrue);
      final source = PairedWorkDetails(controller);
      final work = Work(
        id: 1,
        kind: WorkKind.book,
        title: 'The Dispossessed',
        creator: 'Ursula Le Guin',
        year: null,
        language: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        serverId: 1,
      );
      var d = await source.setStatus(work, 'reading', progress: 25);
      expect(d!.status, 'reading');
      expect(d.progress, 25);
      d = await source.setStatus(work, 'completed', progress: 100);
      expect(d!.status, 'completed');
      expect(d.timesFinished, greaterThanOrEqualTo(1));
      await expectLater(source.setStatus(work, 'paused'), throwsA(anything));
      d = await source.setStatus(work, '');
      expect(d!.status, '');
    },
    skip: skip,
  );
}
