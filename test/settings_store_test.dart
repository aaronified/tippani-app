import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/settings/settings_store.dart';

Future<(SettingsStore, MemoryTokenVault)> open([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final vault = MemoryTokenVault();
  return (SettingsStore(await SharedPreferences.getInstance(), vault), vault);
}

void main() {
  test('starts with no server and no token', () async {
    final (store, _) = await open();
    expect(store.serverUrl, isNull);
    expect(await store.token(), isNull);
  });

  test('remembers the server address', () async {
    final (store, _) = await open();
    await store.setServerUrl('https://q.example.org');
    expect(store.serverUrl, 'https://q.example.org');
  });

  test(
    'the token goes in the vault and never in the plain preferences',
    () async {
      final (store, vault) = await open();
      await store.setToken('secret-token');
      expect(await vault.read(), 'secret-token');
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(
          prefs.get(key).toString().contains('secret-token'),
          isFalse,
          reason: 'found in $key',
        );
      }
    },
  );

  test('forgetting the server forgets its token with it', () async {
    final (store, vault) = await open({'server_url': 'https://q.example.org'});
    await store.setToken('t');
    await store.forgetServer();
    expect(store.serverUrl, isNull);
    expect(await vault.read(), isNull);
  });
}
