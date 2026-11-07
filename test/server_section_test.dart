import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  SharedPreferences.setMockInitialValues({if (url != null) 'server_url': url});
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
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  return (c, server);
}

void main() {
  testWidgets('there is no Server tab: the bar has the library and Settings', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Server'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Library'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Settings opens with a Server section, and the app\'s own settings come after it',
    (tester) async {
      await open(tester);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Connect to your server'), findsOneWidget);
      expect(find.text('Not connected to a server yet.'), findsOneWidget);
      final server = tester.getTopLeft(find.text('Connect to your server')).dy;
      await tester.scrollUntilVisible(
        find.text('App'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Read aloud'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Read aloud')).dy,
        greaterThan(server),
      );
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
