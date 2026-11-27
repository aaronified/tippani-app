import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/preference_scope.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/speech/speech_settings.dart';
import 'package:tippani/tour/tour_store.dart';

import '../support/fake_server.dart';

/// What a reader sees: the app's own choices belong to the account the phone is paired as, so pairing as someone
/// else shows that person's, and the phone's own choices made before pairing are where a new account starts.
void main() {
  late FakeServer server;
  late SettingsStore store;
  late PreferenceScope scope;
  late AppController controller;
  late SpeechSettings speech;
  late TourStore tour;

  Future<void> boot([Map<String, Object> saved = const {}]) async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
      ...saved,
    });
    server = FakeServer();
    store = SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
    scope = PreferenceScope();
    controller = AppController(
      store,
      clientFactory: server.factory,
      preferences: scope,
    );
    speech = SpeechSettings(scope: scope);
    tour = TourStore(scope: scope);
  }

  Future<void> pairAs(String name) async {
    server
      ..username = name
      ..code = 'ABCD2345';
    await controller.pair('ABCD2345', 'Phone');
    await Future<void>.delayed(Duration.zero);
  }

  test('a second account does not read the first one\'s choices', () async {
    await boot();
    await pairAs('alice');
    await speech.save(const SpeechPrefs(rate: 0.8));
    await tour.remember(TourOutcome.finished);

    await controller.unpair();
    await pairAs('bob');
    await speech.load();

    expect(speech.prefs.rate, 0.5, reason: 'bob never changed the speed');
    expect(await tour.outcome(), isNull, reason: 'bob has not had the tour');

    await controller.unpair();
    await pairAs('alice');
    await speech.load();
    expect(speech.prefs.rate, 0.8, reason: 'alice finds her own again');
    expect(await tour.outcome(), TourOutcome.finished);
  });

  test('the first account starts from what the phone chose unpaired', () async {
    await boot({
      'speech_rate': 0.7,
      'tour_outcome': 'dismissed',
      'tour_version': 1,
    });
    await pairAs('alice');
    await speech.load();

    expect(speech.prefs.rate, 0.7);
    expect(await tour.outcome(), TourOutcome.dismissed);
  });

  test('a change made while paired is not the phone\'s own', () async {
    await boot();
    await pairAs('alice');
    await speech.save(const SpeechPrefs(rate: 0.9));
    await controller.unpair();
    await speech.load();

    expect(
      speech.prefs.rate,
      0.5,
      reason: 'the unpaired phone keeps its own set',
    );
  });

  test('what is about the phone, not the reader, stays on the phone', () async {
    await boot({'last_seen_version': '0.10.3'});
    await pairAs('alice');
    await controller.unpair();
    await pairAs('bob');

    expect(store.lastSeenVersion, '0.10.3');
    expect(store.serverUrl, 'https://q.example.org');
  });
}
