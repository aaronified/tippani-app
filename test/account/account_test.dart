import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/account_service.dart';
import 'package:tippani/account/prefs_effects.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/l10n/l10n.dart';
import 'package:tippani/library/quote_chips.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/account_screen.dart';
import 'package:tippani/screens/prefs_screens.dart';
import 'package:tippani/screens/prefs_widgets.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

class Rig {
  Rig(this.server, this.controller, this.settings, this.prefs);

  final FakeServer server;
  final AppController controller;
  final SettingsStore settings;
  final PairedPreferences prefs;
}

Future<Rig> rig({bool paired = true}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final settings = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final controller = AppController(settings, clientFactory: server.factory);
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My phone');
  return Rig(
    server,
    controller,
    settings,
    PairedPreferences(controller, settings),
  );
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final s = files[key];
    if (s == null) throw FlutterError('no $key');
    return ByteData.sublistView(Uint8List.fromList(s.codeUnits));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      files[key] ?? (throw FlutterError('no $key'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => PrefsEffects.apply(ServerPrefs.empty));

  group('the preferences', () {
    test('are read from the server and kept for the next start', () async {
      final r = await rig();
      r.server.prefs.addAll({
        'sizeUi': 125,
        'catName2': 'Doubt',
        'hideCatalogue': true,
      });
      await r.prefs.refresh();
      expect(r.prefs.prefs.sizeUi, 125);
      expect(r.prefs.prefs.colourName('blue'), 'Doubt');
      expect(r.prefs.prefs.hideCatalogue, isTrue);

      // a new run of the app, with no server to ask, still has them
      final again = PairedPreferences(r.controller, r.settings);
      expect(again.prefs.sizeUi, 125);
      expect(PrefsEffects.current.colourName('blue'), 'Doubt');
    });

    test('a change goes to the server and the phone at once', () async {
      final r = await rig();
      final refusal = await r.prefs.save({'sizeDisplay': 150});
      expect(refusal, isNull);
      expect(r.prefs.prefs.sizeDisplay, 150);
      expect(r.server.prefWrites.single, {'sizeDisplay': 150});
    });

    test('a change the server refuses is put back, with its words', () async {
      final r = await rig();
      await r.prefs.save({'srDaily': 10});
      final refusal = await r.prefs.save({'srDaily': 99});
      expect(refusal, contains('between 5 and 20'));
      expect(r.prefs.prefs.srDaily, 10);
    });

    test(
      'hiding every section is refused by the server and undone here',
      () async {
        final r = await rig();
        await r.prefs.save({'hideLibrary': true, 'hideCatalogue': true});
        final refusal = await r.prefs.save({'hideQuotes': true});
        expect(refusal, contains('at least one'));
        expect(r.prefs.prefs.hideQuotes, isFalse);
      },
    );

    test(
      'a phone that is not paired keeps its own, and asks no server',
      () async {
        final r = await rig(paired: false);
        await r.prefs.save({'sizeUi': 150});
        expect(r.prefs.prefs.sizeUi, 150);
        expect(r.server.prefWrites, isEmpty);
      },
    );

    test('are put back to the defaults on the server and here', () async {
      final r = await rig();
      await r.prefs.save({'sizeUi': 150});
      expect(await r.prefs.reset(), isNull);
      expect(r.server.prefResets, 1);
      expect(r.prefs.prefs.sizeUi, 100);
    });

    test('are read the way the server writes them', () {
      final p = ServerPrefs({
        'creditSeparators': 'none',
        'catColor3': '#D98CA6',
        'catHidden4': true,
        'catHidden1': true,
        'fontsByLanguage': '{"Bengali":"noto-serif-bengali"}',
        'srSeen': 1.25,
      });
      expect(p.creditSeparators, isEmpty);
      expect(p.colourHex('pink'), '#D98CA6');
      expect(p.colourHidden('orange'), isTrue);
      expect(
        p.colourHidden('yellow'),
        isFalse,
        reason: 'the first is never hidden',
      );
      expect(p.fontsByLanguage, {'bengali': 'noto-serif-bengali'});
      expect(p.srSeen, 1.25);
      expect(ServerPrefs.empty.sizeUi, 100);
      expect(ServerPrefs.empty.srDaily, 8);
    });
  });

  group('credit separators', () {
    test('decide what splits a credit into people', () {
      PrefsEffects.apply(
        ServerPrefs({'creditSeparators': 'comma,semicolon,amp,and'}),
      );
      expect(creditNames('Pratchett & Gaiman'), ['Pratchett', 'Gaiman']);
      PrefsEffects.apply(ServerPrefs({'creditSeparators': 'comma'}));
      expect(creditNames('Pratchett & Gaiman'), ['Pratchett & Gaiman']);
      expect(creditNames('Pratchett, Gaiman'), ['Pratchett', 'Gaiman']);
      PrefsEffects.apply(ServerPrefs({'creditSeparators': 'none'}));
      expect(creditNames('A, B'), ['A, B']);
    });

    test('give a book with two authors a chip for each', () {
      Work work(String creator) => Work(
        id: 1,
        kind: WorkKind.book,
        title: 'Good Omens',
        creator: creator,
        year: null,
        language: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final q = Quote(
        id: 1,
        workId: 1,
        text: 't',
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
      expect(
        chipsFor(q, work('Terry Pratchett & Neil Gaiman')).map((c) => c.name),
        ['Terry Pratchett', 'Neil Gaiman'],
      );
    });
  });

  group('the account', () {
    test(
      'a wrong current password is told so and does not unpair the phone',
      () async {
        final r = await rig();
        final account = PairedAccount(r.controller);
        final wrong = await account.changePassword('nope', 'newpassword1');
        expect(wrong.ok, isFalse);
        expect(wrong.error, contains('current password'));
        expect(
          r.controller.paired,
          isTrue,
          reason: 'a 401 here is a wrong password',
        );
        final ok = await account.changePassword('oldpassword', 'newpassword1');
        expect(ok.ok, isTrue);
        expect(r.server.password, 'newpassword1');
      },
    );

    test(
      'the server\'s reason for refusing a password comes through',
      () async {
        final r = await rig();
        final short = await PairedAccount(r.controller)
            .changePassword('oldpassword', 'abc');
        expect(short.error, contains('at least 8'));
      },
    );

    test('name, picture and widget key', () async {
      final r = await rig();
      final account = PairedAccount(r.controller);
      expect((await account.rename('bob')).ok, isTrue);
      expect((await account.me()).value!.username, 'bob');
      final set = await account.setAvatar(
        Uint8List.fromList([1, 2, 3]),
        'me.png',
      );
      expect(set.value, isNotEmpty);
      expect((await account.me()).value!.avatar, set.value);
      expect((await account.clearAvatar()).ok, isTrue);
      expect((await account.me()).value!.avatar, isEmpty);

      expect((await account.widgetKey()).value, isNull);
      final key = await account.makeWidgetKey();
      expect(key.value, startsWith('wk_'));
      expect((await account.widgetKey()).value, isNotNull);
      await account.removeWidgetKey();
      expect((await account.widgetKey()).value, isNull);
    });

    test('notifications are read and saved', () async {
      final r = await rig();
      final account = PairedAccount(r.controller);
      await account.saveNotifications({
        'pushover_user': 'u123',
        'app_token': 'tok',
        'on_daily': true,
      });
      final n = (await account.notifications()).value!;
      expect(n.pushoverUser, 'u123');
      expect(n.hasAppToken, isTrue);
      expect(n.onDaily, isTrue);
      expect((await account.testNotification()).ok, isTrue);
      expect(r.server.notifyTests, 1);
    });

    test('an unpaired phone has no account to show', () async {
      final r = await rig(paired: false);
      final out = await PairedAccount(r.controller).me();
      expect(out.ok, isFalse);
      expect(PairedAccount(r.controller).available, isFalse);
    });
  });

  group('context rules', () {
    test('the global pair and a work\'s own are read and written', () async {
      final r = await rig();
      final rules = PairedContextRules(r.controller);
      expect((await rules.global()).value!.before, isNull);
      await rules.setGlobal(const ContextRule(before: 2, after: 4));
      final g = (await rules.global()).value!;
      expect((g.before, g.after), (2, 4));

      final changed = await rules.setForWork(
        'book',
        3,
        const ContextRule(before: 1),
        enforce: 'clamp',
      );
      expect(changed.value, 2);
      expect(r.server.contextWrites.last, contains('"enforce":"clamp"'));
      expect((await rules.forWork('book', 3)).value!.before, 1);
    });
  });

  group('the language', () {
    // the bundled Bengali: two tokens of the web's, one of the app's
    final bundle = _Bundle({
      'assets/l10n/bn.txt':
          'nav.tab.settings.label = সেটিংস\nnav.tab.library.label = লাইব্রেরি',
      'assets/l10n/app.bn.txt': 'app.test.only_here = শুধু এখানে',
    });

    test('shows English from the start, with nothing loaded', () {
      final l = L10n(bundle: bundle, deviceLanguage: 'en');
      expect(l.tr('nav.tab.settings.label'), 'Settings');
      expect(l.tr('nav.tab.library.label'), 'Library');
    });

    test(
      'shows the web app\'s Bengali for a token it has, and the app\'s own',
      () async {
        final l = L10n(bundle: bundle, deviceLanguage: 'en')..use('bn');
        await l.loaded;
        expect(l.tr('nav.tab.settings.label'), 'সেটিংস');
        expect(l.tr('nav.tab.library.label'), 'লাইব্রেরি');
        expect(l.tr('app.test.only_here'), 'শুধু এখানে');
      },
    );

    test('shows English, never blank, for a token nobody translated', () async {
      final l = L10n(bundle: bundle, deviceLanguage: 'en')..use('bn');
      await l.loaded;
      // a real web token the fake Bengali file does not carry
      expect(l.tr('common.action.copy.label'), 'Copy');
    });

    test('shows the token itself for one that exists nowhere', () {
      final l = L10n(bundle: bundle, deviceLanguage: 'en');
      expect(l.tr('nope.not.a.token'), 'nope.not.a.token');
    });

    test('puts values into {places}', () {
      final l = L10n(bundle: bundle, deviceLanguage: 'en');
      expect(l.tr('settings.changed.count', {'n': 7}), '7 changed');
    });

    test('the server\'s own text wins over the bundled one', () async {
      final l = L10n(bundle: bundle, deviceLanguage: 'en')..use('bn');
      await l.loaded;
      l.useServerFiles({
        'files': {
          'bn': {
            'keys': {'nav.tab.settings.label': 'বিন্যাস'},
            'reserved': {'_name': 'বাংলা'},
          },
        },
      });
      expect(l.tr('nav.tab.settings.label'), 'বিন্যাস');
      expect(l.tr('nav.tab.library.label'), 'লাইব্রেরি');
    });

    test(
      'a language the server holds is offered, and falls back as it says',
      () async {
        final l = L10n(bundle: bundle, deviceLanguage: 'en');
        l.useServerFiles({
          'files': {
            'fr': {
              'keys': {'nav.tab.settings.label': 'Réglages'},
              'reserved': {'_name': 'Français', '_fallback': 'bn'},
            },
          },
        });
        expect(l.choices.map((c) => c.code), ['en', 'bn', 'fr']);
        l.use('fr');
        await l.loaded;
        expect(l.tr('nav.tab.settings.label'), 'Réglages');
        expect(
          l.tr('nav.tab.library.label'),
          'লাইব্রেরি',
          reason: 'its fallback',
        );
      },
    );

    test('follows the phone when none is chosen', () {
      expect((L10n(deviceLanguage: 'bn')..use('')).code, 'bn');
      expect((L10n(deviceLanguage: 'fr')..use('')).code, 'en');
    });

    test('parses a locale file the way the server does', () {
      final f = parseLocale(
        '﻿# comment\r\n_name = বাংলা\r\na.b = x = y\r\nempty =\r\nbad line\r\n',
      );
      expect(f.keys, {'a.b': 'x = y'});
      expect(f.reserved, {'_name': 'বাংলা'});
    });
  });

  group('the screens', () {
    Future<(Rig, Widget)> app(WidgetTester tester, Widget screen) async {
      final r = (await tester.runAsync(rig))!;
      final widget = PrefsScope(
        source: r.prefs,
        child: MaterialApp(home: screen),
      );
      return (r, widget);
    }

    testWidgets('the last visible section cannot be switched off', (
      tester,
    ) async {
      final (r, widget) = await app(tester, const SectionsScreen());
      await tester.runAsync(
        () => r.prefs.save({'hideCatalogue': true, 'hideQuotes': true}),
      );
      await tester.pumpWidget(widget);
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('section-hideLibrary')),
      );
      expect(tile.onChanged, isNull);
    });

    testWidgets('switching a section off is saved to the server', (
      tester,
    ) async {
      final (r, widget) = await app(tester, const SectionsScreen());
      await tester.pumpWidget(widget);
      await tester.tap(find.byKey(const ValueKey('section-hideCatalogue')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(r.server.prefWrites.last, {'hideCatalogue': true});
    });

    testWidgets('a credit separator is switched off and saved', (tester) async {
      final (r, widget) = await app(tester, const ReadingScreen());
      await tester.pumpWidget(widget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sep-amp')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('sep-amp')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        r.server.prefWrites.last['creditSeparators'],
        'comma,semicolon,and',
      );
    });

    testWidgets('a colour is named and the new name is saved', (tester) async {
      final (r, widget) = await app(tester, const ColoursScreen());
      await tester.pumpWidget(widget);
      await tester.tap(find.byKey(const ValueKey('slot-blue')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Doubt');
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(r.server.prefWrites.last, {'catName2': 'Doubt'});
      expect(find.text('Doubt'), findsOneWidget);
    });

    testWidgets('the account page shows who you are and changes the password', (
      tester,
    ) async {
      final r = (await tester.runAsync(rig))!;
      await tester.pumpWidget(
        PrefsScope(
          source: r.prefs,
          child: MaterialApp(
            home: AccountScreen(account: PairedAccount(r.controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsWidgets);

      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('password-current')),
        'wrong',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-new')),
        'brandnewpass',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-again')),
        'brandnewpass',
      );
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      // the dialog stays, says why, and the phone is still paired
      expect(find.textContaining('current password'), findsOneWidget);
      expect(r.controller.paired, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('password-current')),
        'oldpassword',
      );
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(r.server.password, 'brandnewpass');
      expect(find.text('Password changed.'), findsOneWidget);
    });

    testWidgets(
      'the account page with the server out of reach says so and can try again, instead of staying blank',
      (tester) async {
        final r = (await tester.runAsync(rig))!;
        r.server.unreachable = true;
        await tester.pumpWidget(
          PrefsScope(
            source: r.prefs,
            child: MaterialApp(
              home: AccountScreen(account: PairedAccount(r.controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be reached'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        r.server.unreachable = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('alice'), findsWidgets);
        expect(find.text('Try again'), findsNothing);
      },
    );

    testWidgets(
      'the account page shows who you are from the phone when the server goes away',
      (tester) async {
        final r = (await tester.runAsync(rig))!;
        Future<void> open() async {
          await tester.pumpWidget(
            PrefsScope(
              source: r.prefs,
              child: MaterialApp(
                key: UniqueKey(),
                home: AccountScreen(account: PairedAccount(r.controller)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await open();
        expect(find.text('alice'), findsWidgets);
        r.server.unreachable = true;
        await open();
        expect(find.text('alice'), findsWidgets);
        expect(find.text('Change password'), findsOneWidget);
      },
    );

    test('a setting changed with no server is kept, survives the server being read back, and goes up', () async {
      final r = await rig();
      r.server.unreachable = true;
      expect(await r.prefs.save({'srDaily': 12}), isNull);
      expect(r.prefs.prefs.srDaily, 12);

      r.server.unreachable = false;
      await r.prefs.refresh();
      expect(r.server.prefWrites.last['srDaily'], 12);
      expect(r.prefs.prefs.srDaily, 12);

      // nothing is left waiting
      r.server.prefWrites.clear();
      await r.prefs.refresh();
      expect(r.server.prefWrites, isEmpty);
    });

    test('a setting changed with no server is not overwritten by an old server copy', () async {
      final r = await rig();
      r.server.unreachable = true;
      await r.prefs.save({'srDaily': 12});
      r.server.unreachable = true;
      await r.prefs.refresh();
      expect(
        r.prefs.prefs.srDaily,
        12,
        reason: 'still unreachable: the phone\'s value stands',
      );
    });

    testWidgets('a server refusal is shown to the reader', (tester) async {
      final (r, widget) = await app(tester, const ReviewPrefsScreen());
      await tester.pumpWidget(widget);
      final context = tester.element(find.byType(ReviewPrefsScreen));
      await tester.runAsync(() => savePrefs(context, {'srDaily': 99}));
      await tester.pump();
      expect(find.textContaining('between 5 and 20'), findsOneWidget);
      expect(r.prefs.prefs.srDaily, 8, reason: 'put back');
    });
  });
}
