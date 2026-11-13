import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/account_service.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';
import 'support/memory_library.dart';

Future<(AppController, FakeServer)> open(
  WidgetTester tester, {
  String? url,
  bool pair = false,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'server_url': ?url});
  final server = FakeServer();
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store, clientFactory: server.factory);
  await c.load();
  if (pair) await c.pair('ABCD2345', 'My phone');
  await tester.pumpWidget(
    TippaniApp(
      controller: c,
      harness: Harness.fake(store, controller: c, library: MemoryLibrary()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Server'));
  await tester.pumpAndSettle();
  return (c, server);
}

void main() {
  testWidgets('the bar has Boards, Server and Settings', (tester) async {
    await open(tester);
    for (final label in ['Boards', 'Server', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets(
    'the Server tab is the server\'s, and the app\'s own settings are on their own tab',
    (tester) async {
      await open(tester);
      expect(find.text('Connect to your server'), findsOneWidget);
      expect(find.text('Not connected to a server yet.'), findsOneWidget);
      expect(find.text('Read aloud'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect to your server'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Read aloud'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Read aloud'), findsOneWidget);
    },
  );

  testWidgets(
    'the settings kept on the server are on the Server tab; the app\'s own stay on Settings',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      final server = FakeServer();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final c = AppController(store, clientFactory: server.factory);
      await c.load();
      await c.pair('ABCD2345', 'My phone');
      await tester.pumpWidget(
        TippaniApp(
          controller: c,
          harness: Harness.fake(
            store,
            controller: c,
            library: MemoryLibrary(),
            prefs: PairedPreferences(c, store),
            account: PairedAccount(c),
            contextRules: PairedContextRules(c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      for (final kept in [
        'Your settings on the server',
        'Account',
        'Daily review',
        'Context around a quote',
      ]) {
        expect(find.text(kept), findsOneWidget, reason: kept);
      }
      expect(find.text('Language'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      for (final moved in [
        'Daily review',
        'Context around a quote',
        'Your settings on the server',
      ]) {
        expect(find.text(moved), findsNothing, reason: moved);
      }
    },
  );

  testWidgets(
    'with an address set, the section says whether the server answers, and Check again asks',
    (tester) async {
      final (_, server) = await open(tester, url: 'https://q.example.org');
      expect(find.text('Server'), findsWidgets);
      expect(find.textContaining('https://q.example.org'), findsOneWidget);
      expect(find.textContaining('Connected'), findsOneWidget);
      final before = server.paths.where((p) => p == 'GET /capabilities').length;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(
        server.paths.where((p) => p == 'GET /capabilities').length,
        greaterThan(before),
      );
    },
  );

  testWidgets(
    'a phone that has an address but is not paired is offered pairing, right there',
    (tester) async {
      await open(tester, url: 'https://q.example.org');
      expect(find.text('Pair this phone'), findsOneWidget);
      expect(find.text('Paired devices'), findsNothing);
    },
  );

  testWidgets(
    'a paired phone shows who it is paired as, and the things that need the server',
    (tester) async {
      await open(tester, url: 'https://q.example.org', pair: true);
      expect(find.text('Paired devices'), findsOneWidget);
      expect(find.textContaining('Paired as'), findsOneWidget);
      expect(find.text('Pair this phone'), findsNothing);
    },
  );

  testWidgets('a phone the server unpaired says so in the section', (
    tester,
  ) async {
    final (c, server) = await open(
      tester,
      url: 'https://q.example.org',
      pair: true,
    );
    server.tokenValid = false;
    await c.loadAccount();
    await c.refresh();
    await tester.pumpAndSettle();
    await c
        .withClient((client) => client.getJson('/auth/me'))
        .catchError((_) => null);
    await tester.pumpAndSettle();
    expect(
      find.text('This phone was unpaired from the server'),
      findsOneWidget,
    );
  });
}
