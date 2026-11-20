import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/anthologies/offline_anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

// How the Anthologies screens load (ADR-0030): like every other screen, what the phone holds is drawn at once,
// the server is asked behind it, and a server that is slow, silent or failing never holds the screen back or
// takes what is shown away. The server is the shared FakeServer, which can be made slow, silent or failing.

Future<({FakeServer server, AppController controller, OfflineAnthologies svc})>
_rig(WidgetTester tester, {bool cached = true}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer()
    ..anthologies.add({'id': 1, 'title': 'Evenings', 'entries': 1})
    ..anthologyEntries[1] = [
      {
        'kind': 'book',
        'item_id': 7,
        'quote': 'The cached passage',
        'position': 1,
      },
    ];
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final controller = AppController(store, clientFactory: server.factory);
  final svc = OfflineAnthologies(
    ServerAnthologies(controller),
    controller.offline,
    store,
  );
  await tester.runAsync(() async {
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    if (cached) {
      // a read the server answered: the phone now holds it
      await svc.list();
      await svc.get(1);
    }
  });
  return (server: server, controller: controller, svc: svc);
}

Widget _list(AppController c, OfflineAnthologies svc) => MaterialApp(
  home: AnthologiesScreen(service: svc, controller: c),
);

const _offline = 'The server cannot be reached';

void main() {
  testWidgets('with a copy and a server that never answers, the list is there at once and says it is the phone\'s copy '
      'when the server is given up on', (tester) async {
    final r = await _rig(tester);
    r.server.anthologiesWait = Completer<void>().future;
    await tester.pumpWidget(_list(r.controller, r.svc));
    await tester.pump();
    expect(find.text('Evenings'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining(_offline), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Evenings'), findsOneWidget);
    expect(find.textContaining(_offline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'with a copy and a slow server, the copy shows first and the fresh list replaces it',
    (tester) async {
      final r = await _rig(tester);
      final wait = Completer<void>();
      r.server.anthologiesWait = wait.future;
      r.server.anthologies[0]['title'] = 'Evenings, renamed on the web';
      await tester.pumpWidget(_list(r.controller, r.svc));
      await tester.pump();
      expect(find.text('Evenings'), findsOneWidget);
      wait.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Evenings'), findsNothing);
      expect(find.text('Evenings, renamed on the web'), findsOneWidget);
      expect(find.textContaining(_offline), findsNothing);
    },
  );

  testWidgets(
    'with nothing kept and no server, the first load waits, then says there are none like the other screens',
    (tester) async {
      final r = await _rig(tester, cached: false);
      r.server.anthologiesWait = Completer<void>().future;
      await tester.pumpWidget(_list(r.controller, r.svc));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No anthologies yet.'), findsOneWidget);
    },
  );

  testWidgets('a refresh the server refuses does not blank the list', (
    tester,
  ) async {
    final r = await _rig(tester);
    r.server.extra = (req, path) async =>
        path == '/anthologies' ? r.server.json({'error': 'broken'}, 500) : null;
    await tester.pumpWidget(_list(r.controller, r.svc));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Evenings'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    'an opened anthology draws from the phone at once while the server is silent, and keeps it when the read fails',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologiesWait = Completer<void>().future;
      await tester.pumpWidget(
        MaterialApp(home: AnthologyScreen(service: r.svc, id: 1)),
      );
      await tester.pump();
      expect(find.textContaining('The cached passage'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(find.textContaining('The cached passage'), findsOneWidget);
    },
  );

  testWidgets(
    'adding to an anthology offers the phone\'s own list at once, with the server silent',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologiesWait = Completer<void>().future;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  addToAnthologyDialog(context, r.svc, kind: 'book', itemId: 7),
              child: const Text('Add it'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Evenings'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Evenings'), findsOneWidget);
    },
  );
}
