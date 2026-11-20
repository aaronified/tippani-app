import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/anthologies/offline_anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/screens/offline_note.dart';
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

Widget _list(AppController c, OfflineAnthologies svc) => OfflineScope(
  offline: c.offline,
  child: MaterialApp(
    home: AnthologiesScreen(service: svc, controller: c),
  ),
);

/// The app's own frame for a screen: the shared note reads the phone's kept answers from here.
Widget _scoped(
  ({FakeServer server, AppController controller, OfflineAnthologies svc}) r,
  Widget home,
) => OfflineScope(
  offline: r.controller.offline,
  child: MaterialApp(home: home),
);

const _offline = 'The server cannot be reached';
const _refused = 'The server did not accept the refresh';

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
    expect(find.textContaining(_refused), findsOneWidget);
    expect(find.textContaining(_offline), findsNothing);
  });

  testWidgets(
    'an opened anthology draws from the phone at once while the server is silent, and says it is the phone\'s copy',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologiesWait = Completer<void>().future;
      await tester.pumpWidget(
        _scoped(r, AnthologyScreen(service: r.svc, id: 1)),
      );
      await tester.pump();
      expect(find.textContaining('The cached passage'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining(_offline), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(find.textContaining('The cached passage'), findsOneWidget);
      expect(find.textContaining(_offline), findsOneWidget);
    },
  );

  testWidgets(
    'an opened anthology keeps the phone\'s copy when the server refuses the read, and says the copy is old',
    (tester) async {
      final r = await _rig(tester);
      r.server.refuseReadsWith = 500;
      await tester.pumpWidget(
        _scoped(r, AnthologyScreen(service: r.svc, id: 1)),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('The cached passage'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining(_refused), findsOneWidget);
      expect(find.textContaining(_offline), findsNothing);
    },
  );

  testWidgets(
    'an anthology deleted on the web, opened from the phone\'s copy, stays readable and says the copy is old',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologies.clear();
      await tester.pumpWidget(
        _scoped(r, AnthologyScreen(service: r.svc, id: 1)),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('The cached passage'), findsOneWidget);
      expect(find.textContaining(_refused), findsOneWidget);
    },
  );

  Future<void> changedOnline(WidgetTester tester, AppController c) =>
      tester.runAsync(
        () =>
            c.withClient<Object?>((x) => x.postJson('/anthologies/touch', {})),
      );

  testWidgets(
    'after a change that reached the server, the phone\'s older copy of the list is not drawn first',
    (tester) async {
      final r = await _rig(tester);
      r.server.extra = (req, path) async =>
          req.method == 'POST' ? r.server.json({}) : null;
      await changedOnline(tester, r.controller);
      final wait = Completer<void>();
      r.server.anthologiesWait = wait.future;
      await tester.pumpWidget(_list(r.controller, r.svc));
      await tester.pump();
      expect(find.text('Evenings'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      wait.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Evenings'), findsOneWidget);
    },
  );

  testWidgets(
    'changes still waiting on the phone show at once even after one that reached the server',
    (tester) async {
      final r = await _rig(tester);
      r.server.extra = (req, path) async =>
          req.method == 'POST' ? r.server.json({}) : null;
      await changedOnline(tester, r.controller);
      r.server.anthologiesWait = Completer<void>().future;
      r.server.readsWait = Completer<void>().future;
      r.server.writesWait = Completer<void>().future;
      // the copy is drawn from the phone's own list when the server is given up on
      await tester.pumpWidget(
        _scoped(r, AnthologiesScreen(service: r.svc, controller: r.controller)),
      );
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('Evenings'), findsOneWidget);
      await tester.tap(find.text('Evenings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.text('Evenings'), findsNothing);
      expect(find.text('No anthologies yet.'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
    },
  );

  testWidgets('a slow earlier read never lands over a later one', (
    tester,
  ) async {
    final r = await _rig(tester);
    final first = Completer<void>();
    var asks = 0;
    r.server.extra = (req, path) async {
      if (req.method != 'GET' || path != '/anthologies') return null;
      final answer = r.server.json({
        'anthologies': [
          {
            'id': 1,
            'title': ++asks == 1
                ? 'Evenings, the slow answer'
                : 'Evenings, the quick answer',
            'entries': 1,
          },
        ],
      });
      if (asks == 1) await first.future; // the first read is slow
      return answer;
    };
    await tester.pumpWidget(
      _scoped(r, AnthologiesScreen(service: r.svc, controller: r.controller)),
    );
    await tester.pump();
    // the reader opens the anthology and comes back: the list is read a second time, and that answer lands first
    await tester.tap(find.text('Evenings'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Evenings, the quick answer'), findsOneWidget);
    first.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Evenings, the slow answer'), findsNothing);
    expect(find.text('Evenings, the quick answer'), findsOneWidget);
  });

  testWidgets(
    'what was deleted with the server silent is off the list at once, not half a minute later',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologiesWait = Completer<void>().future;
      r.server.readsWait = Completer<void>().future;
      r.server.writesWait = Completer<void>().future;
      await tester.pumpWidget(
        _scoped(r, AnthologiesScreen(service: r.svc, controller: r.controller)),
      );
      await tester.pump();
      await tester.tap(find.text('Evenings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      // the app gives the silent server its time, then keeps the change for later
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.text('Evenings'), findsNothing);
      expect(find.text('No anthologies yet.'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
    },
  );

  testWidgets(
    'a passage taken out with the server silent is gone from the opened anthology at once',
    (tester) async {
      final r = await _rig(tester);
      r.server.anthologiesWait = Completer<void>().future;
      r.server.writesWait = Completer<void>().future;
      await tester.pumpWidget(
        _scoped(r, AnthologyScreen(service: r.svc, id: 1)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('More for this one').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from anthology'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.textContaining('The cached passage'), findsNothing);
      await tester.pump(const Duration(minutes: 1));
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

  Widget pickerHost(AppController c, OfflineAnthologies svc) => OfflineScope(
    offline: c.offline,
    child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => addToAnthologyDialog(
                      context,
                      svc,
                      kind: 'book',
                      itemId: 7,
                    ),
                    child: const Text('Add it'),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('Open the page'),
        ),
      ),
    ),
  );

  testWidgets(
    'adding to an anthology with nothing kept and a server that refuses says why and closes the question',
    (tester) async {
      final r = await _rig(tester, cached: false);
      r.server.refuseReadsWith = 500;
      await tester.pumpWidget(pickerHost(r.controller, r.svc));
      await tester.tap(find.text('Open the page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add it'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Add it'), findsOneWidget);
    },
  );

  testWidgets(
    'adding to an anthology with a copy shown and a server that refuses leaves the copy to choose from',
    (tester) async {
      final r = await _rig(tester);
      r.server.refuseReadsWith = 500;
      await tester.pumpWidget(pickerHost(r.controller, r.svc));
      await tester.tap(find.text('Open the page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add it'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.text('Evenings'), findsOneWidget);
      expect(find.textContaining(_refused), findsOneWidget);
    },
  );

  testWidgets(
    'an answer that fails in the very moment the reader dismisses the question does not close the page beneath it',
    (tester) async {
      final r = await _rig(tester, cached: false);
      final gate = Completer<List<Anthology>>();
      final svc = _Gated(
        ServerAnthologies(r.controller),
        r.controller.offline,
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        gate.future,
      );
      await tester.pumpWidget(pickerHost(r.controller, svc));
      await tester.tap(find.text('Open the page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SimpleDialog), findsOneWidget);
      // the failure and the dismissal arrive together, the failure's handler first
      gate.completeError(AnthologyException('nope'));
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.text('Add it'), findsOneWidget);
    },
  );
}

/// An anthology service whose list is read when a test says so.
class _Gated extends OfflineAnthologies {
  _Gated(super.inner, super.cache, super.store, this._list);
  final Future<List<Anthology>> _list;

  @override
  Future<List<Anthology>> list() => _list;
}
