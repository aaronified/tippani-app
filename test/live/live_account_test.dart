// Runs the account code against a real Tippani server: preferences, language files, password, avatar,
// notifications, widget key and context rules. Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
// TIPPANI_LIVE_PASSWORD is the account's current password (default livepass123); it is changed and changed back.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/account_service.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/l10n/l10n.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];
final _password =
    Platform.environment['TIPPANI_LIVE_PASSWORD'] ?? 'livepass123';

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test('the account against a real server', () async {
    SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
    final settings = SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
    final controller = AppController(settings, log: AppLog());
    await controller.load();
    expect((await controller.pair(_code ?? '', 'live account')).ok, isTrue);

    // preferences: read, write, refuse, reset
    final prefs = PairedPreferences(controller, settings);
    await prefs.save({
      'sizeUi': 125,
      'catName2': 'Doubt',
      'catColor3': '#D98CA6',
      'creditSeparators': 'comma,and',
      'locale': 'bn',
    });
    final fresh = PairedPreferences(
      controller,
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    );
    await SharedPreferences.getInstance().then((p) => p.remove('server_prefs'));
    final reader = PairedPreferences(
      controller,
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    );
    await reader.refresh();
    expect(fresh, isNotNull);
    expect(reader.prefs.sizeUi, 125);
    expect(reader.prefs.colourName('blue'), 'Doubt');
    expect(reader.prefs.colourHex('pink'), '#D98CA6');
    expect(reader.prefs.creditSeparators, ['comma', 'and']);
    expect(reader.prefs.locale, 'bn');

    final refusal = await prefs.save({'srDaily': 99});
    expect(refusal, contains('between 5 and 20'));
    expect(prefs.prefs.srDaily, 8);
    final hidden = await prefs.save({
      'hideLibrary': true,
      'hideCatalogue': true,
      'hideQuotes': true,
    });
    expect(hidden, contains('at least one'));
    expect(await prefs.reset(), isNull);
    expect(prefs.prefs.sizeUi, 100);

    // the language files
    final l10n = L10n(deviceLanguage: 'en');
    final locales = await controller.withClient<Object?>(
      (c) => c.getJson('/locales'),
    );
    l10n.useServerFiles(locales);
    expect(l10n.choices.map((c) => c.code), containsAll(['en', 'bn']));

    // the account
    final account = PairedAccount(controller);
    final me = (await account.me()).value!;
    expect(me.username, isNotEmpty);
    final wrong = await account.changePassword('not-it', 'whatever123');
    expect(wrong.error, contains('current password'));
    expect(
      controller.paired,
      isTrue,
      reason: 'a wrong password does not unpair',
    );
    expect(
      (await account.changePassword(_password, 'temporary-pass-1')).ok,
      isTrue,
    );
    expect(
      (await account.changePassword('temporary-pass-1', _password)).ok,
      isTrue,
    );

    final png = await File('assets/share/cotton.png').readAsBytes();
    final avatar = await account.setAvatar(png, 'me.png');
    expect(avatar.ok, isTrue, reason: '${avatar.error}');
    expect((await account.me()).value!.avatar, avatar.value);
    expect((await account.clearAvatar()).ok, isTrue);

    expect(
      (await account.saveNotifications({
        'pushover_user': 'u1234567890',
        'on_daily': true,
      })).ok,
      isTrue,
    );
    final n = (await account.notifications()).value!;
    expect(n.pushoverUser, 'u1234567890');
    expect(n.onDaily, isTrue);
    await account.saveNotifications({'pushover_user': '', 'on_daily': false});

    final key = await account.makeWidgetKey();
    expect(key.value, isNotEmpty);
    expect((await account.widgetKey()).value, isNotNull);
    expect((await account.removeWidgetKey()).ok, isTrue);
    expect((await account.widgetKey()).value, isNull);

    // context rules
    final rules = PairedContextRules(controller);
    expect(
      (await rules.setGlobal(const ContextRule(before: 2, after: 3))).ok,
      isTrue,
    );
    final g = (await rules.global()).value!;
    expect((g.before, g.after), (2, 3));
    expect((await rules.setGlobal(const ContextRule())).ok, isTrue);
    expect(
      (await rules.setGlobal(const ContextRule(before: 99))).error,
      isNotNull,
    );
  }, skip: skip);
}
