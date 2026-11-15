import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

/// Whether the app counts a start as the first on the phone is what decides if the tour is offered of itself, so it
/// is asked the way the app asks it: the real opening of the harness, over a phone's stored preferences.
Future<bool> firstRun(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store, clientFactory: FakeServer().factory);
  await c.load();
  return Harness.open(store, c, library: MemoryLibrary()).freshInstall;
}

void main() {
  test('a phone that has never run the app is a first run', () async {
    expect(await firstRun({}), isTrue);
  });

  test('a phone that has run an earlier version is not', () async {
    // the key SettingsStore keeps the last version it showed What's new for
    final probe = await (() async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      await s.setLastSeenVersion('0.9.0');
      return (await SharedPreferences.getInstance()).getKeys().single;
    })();
    expect(await firstRun({probe: '0.9.0'}), isFalse);
  });
}
