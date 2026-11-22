import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/account_service.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/screens/admin_jobs_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/server_link.dart';
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
    'everything the account keeps on the server is on the Server tab; Settings keeps only the app\'s own',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
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
      final kept = [
        'Your settings on the server',
        'Account',
        'Language',
        'Text and quotes',
        'Colours',
        'Sections',
        'Daily review',
        'Context around a quote',
      ];
      for (final entry in kept) {
        expect(
          find.text(entry),
          findsOneWidget,
          reason: '$entry on the Server tab',
        );
      }

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in kept) {
        expect(
          find.text(entry),
          findsNothing,
          reason: '$entry is not on Settings',
        );
      }
      await tester.scrollUntilVisible(
        find.text('Read aloud'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Read aloud'), findsOneWidget);
    },
  );

  testWidgets(
    'a phone with no pairing still has its settings on the Server tab, and the server tab says when it shows the phone\'s copy',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final server = FakeServer();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final c = AppController(store, clientFactory: server.factory);
      await c.load();
      await tester.pumpWidget(
        TippaniApp(
          controller: c,
          harness: Harness.fake(
            store,
            controller: c,
            library: MemoryLibrary(),
            prefs: PairedPreferences(c, store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      expect(find.text('Colours'), findsOneWidget);
      expect(find.text('Daily review'), findsOneWidget);
      expect(
        find.text('Account'),
        findsNothing,
        reason: 'there is no account to show',
      );
      expect(brokenLink, findsNothing);

      c.offline.servedFrom.value = DateTime.utc(2026, 11, 13);
      await tester.pump();
      await tester.pump();
      // no banner in the screen: the words are said once, by the toast, and the Server tab wears the mark
      expect(
        find.textContaining('Showing what this phone last saw'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Showing what this phone last saw'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.bySemanticsLabel('Server not reachable'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a screen opened over the tabs wears the broken-link mark too, and pressing it says what the phone is showing',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final server = FakeServer();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final c = AppController(store, clientFactory: server.factory);
      await c.load();
      await tester.pumpWidget(
        TippaniApp(
          controller: c,
          harness: Harness.fake(
            store,
            controller: c,
            library: MemoryLibrary(),
            prefs: PairedPreferences(c, store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colours'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: brokenLink),
        findsNothing,
        reason: 'the server answers',
      );

      c.offline.markRefused(DateTime.utc(2026, 11, 13), 'out of sorts');
      await tester.pump();
      await tester.pump();
      ScaffoldMessenger.of(tester.element(find.byType(AppBar)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: brokenLink),
        findsOneWidget,
      );
      await linkSays(
        tester,
        'The server did not accept the refresh: out of sorts',
        also: '2026-11-13',
        not: 'cannot be reached',
      );

      c.offline.markFresh();
      await tester.pumpAndSettle();
      expect(brokenLink, findsNothing);
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

  Future<(AppController, FakeServer)> openPaired(
    WidgetTester tester, {
    required bool admin,
  }) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    final server = FakeServer(admin: admin);
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
          admin: PairedAdminService(c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    return (c, server);
  }

  testWidgets(
    'a reader who is not an administrator has Jobs on the Server tab',
    (tester) async {
      final (c, _) = await openPaired(tester, admin: false);
      expect(c.isAdmin, isFalse);
      expect(find.text('Jobs'), findsOneWidget);
      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminJobsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'an administrator reaches Jobs through Run the server, not twice',
    (tester) async {
      final (c, _) = await openPaired(tester, admin: true);
      expect(c.isAdmin, isTrue);
      expect(find.text('Jobs'), findsNothing);
      expect(find.text('Run the server'), findsOneWidget);
    },
  );
}
