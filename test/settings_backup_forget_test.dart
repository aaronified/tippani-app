import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/settings/settings_backup.dart';
import 'package:tippani/settings/settings_store.dart';

// Restoring a backup that points the app at a different server forgets the old one through the app, which also
// forgets what the old server last said (ADR-0022), not through the settings store alone.

void main() {
  Future<SettingsStore> store(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    return SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
  }

  test(
    'a restore that changes the server forgets the old one through the app',
    () async {
      final s = await store({'server_url': 'https://old.example.org'});
      var forgotten = 0;
      await SettingsBackup(
        s,
        forget: () async => forgotten++,
      ).restore({'server_url': 'https://new.example.org'});
      expect(forgotten, 1);
      expect(s.serverUrl, 'https://new.example.org');
    },
  );

  test('a restore of the same server forgets nothing', () async {
    final s = await store({'server_url': 'https://same.example.org'});
    var forgotten = 0;
    await SettingsBackup(
      s,
      forget: () async => forgotten++,
    ).restore({'server_url': 'https://same.example.org'});
    expect(forgotten, 0);
  });
}
