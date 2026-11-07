// Runs the board extras against a real Tippani server. Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/boards/board_service.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/pull_sync.dart';

import '../support/memory_library.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'a real server takes the board extras, and the sync keeps them',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final log = AppLog();
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        log: log,
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live boards')).ok, isTrue);
      final lib = MemoryLibrary();
      final board = await lib.addBoard('Live proverbs', color: 'green');
      await PullSync(lib, controller, log: log).sync();
      var b = (await lib.boards()).firstWhere((x) => x.id == board.id);
      expect(b.serverId, isNotNull, reason: 'the board went up');

      final svc = ServerBoards(controller, lib);
      await svc.update(b, {
        'kind': 'proverb',
        'languages': ['Bengali'],
        'description': 'sayings',
        'hidden': true,
      });
      b = (await lib.boards()).firstWhere((x) => x.id == board.id);
      expect(b.kind, 'proverb');
      expect(b.languages, ['Bengali']);
      expect(b.description, 'sayings');
      expect(b.hidden, isTrue);

      final png = await File('assets/share/cotton.png').readAsBytes();
      await svc.setImage(b, png, 'cotton.png');
      b = (await lib.boards()).firstWhere((x) => x.id == board.id);
      expect(b.imagePath, matches(RegExp(r'^[0-9a-f]{16}\.png$')));

      final offers = await svc.starters();
      expect(offers, isNotEmpty);
      final added = await svc.addStarters(b, offers.first.language);
      expect(added, greaterThan(0));

      // a sync changes nothing the extras set, and brings the new proverbs down
      await PullSync(lib, controller, log: log).sync();
      b = (await lib.boards()).firstWhere((x) => x.id == board.id);
      expect(b.hidden, isTrue);
      expect(b.kind, 'proverb');
      expect(b.imagePath, isNotEmpty);
      expect(
        (await lib.quotes(boardId: b.id, limit: 1000)).length,
        greaterThanOrEqualTo(added),
      );

      await svc.removeImage(b);
      expect(
        (await lib.boards()).firstWhere((x) => x.id == board.id).imagePath,
        '',
      );
    },
    skip: skip,
  );
}
