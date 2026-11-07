import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/auto_sync.dart';
import 'package:tippani/sync/pull_sync.dart';
import 'package:tippani/sync/push_sync.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class Rig {
  Rig(this.server, this.lib, this.controller, this.auto, this.clock, this.net);
  final FakeServer server;
  final MemoryLibrary lib;
  final AppController controller;
  final AutoSync auto;
  final Clock clock;
  final FakeNet net;
}

/// A phone's network that the test can bring back.
class FakeNet implements Connectivity {
  final _c = StreamController<void>.broadcast();
  @override
  Stream<void> get regained => _c.stream;
  void regain() => _c.add(null);
}

class Clock {
  DateTime now = DateTime.utc(2026, 11, 7, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Future<Rig> rig({
  bool paired = true,
  Duration? lastRunAgo,
  bool waiting = false,
}) async {
  final clock = Clock();
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
    if (lastRunAgo != null)
      'auto_sync_last': clock.now.subtract(lastRunAgo).millisecondsSinceEpoch,
    if (waiting) 'auto_sync_dirty': true,
  });
  final server = FakeServer();
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final log = AppLog();
  final controller = AppController(
    store,
    clientFactory: server.factory,
    log: log,
  );
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My Android phone');
  final lib = MemoryLibrary();
  final net = FakeNet();
  final auto = AutoSync(
    push: PushSync(lib, controller, log: log),
    pull: PullSync(lib, controller, log: log),
    controller: controller,
    log: log,
    clock: clock.call,
    connectivity: net,
  );
  return Rig(server, lib, controller, auto, clock, net);
}

/// A widget test with a started [AutoSync], stopped again before the test ends (a timer left running fails it).
void testAuto(
  String name,
  Future<void> Function(WidgetTester tester, Rig r) body, {
  bool paired = true,
  Duration? lastRunAgo,
  bool waiting = false,
}) {
  testWidgets(name, (tester) async {
    final r = await rig(
      paired: paired,
      lastRunAgo: lastRunAgo,
      waiting: waiting,
    );
    try {
      await body(tester, r);
    } finally {
      r.auto.dispose();
    }
  });
}

/// Lets timers and the futures they start run, in the test's own clock.
Future<void> settle(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

int reads(Rig r) => r.server.paths.where((p) => p == 'GET /books').length;

/// A quote the phone and the server both hold, whose note each side wrote differently, with no agreement ever
/// recorded: a clash.
Future<void> clash(Rig r, {String text = 'Clash'}) async {
  final w = await r.lib.addWork(const WorkDraft(title: 'Walden', creator: 'T'));
  await r.lib.setWorkServerId(w.id, 1);
  await r.lib.markWorkSynced(w.id, 'x');
  r.server.seed('/books', {'title': 'Walden', 'author': 'T'}, id: 1);
  final q = await r.lib.addQuote(
    QuoteDraft(text: text, workId: w.id, note: 'phone note'),
  );
  await r.lib.setQuoteServerId(q.id, 10);
  r.server.seed('/annotations', {
    'book_id': 1,
    'quote': text,
    'note': 'server note',
    'translation': '',
    'language': '',
    'color': 'yellow',
    'favorite': false,
    'tags': <String>[],
    'chapter': '',
    'location': '',
    'character': '',
  }, id: 10);
}

void main() {
  group('a run', () {
    test(
      'sends what is only here and brings down what is only there',
      () async {
        final r = await rig();
        await r.lib.addQuote(const QuoteDraft(text: 'From the phone.'));
        final b = r.server.seed('/books', {
          'title': 'Dune',
          'author': 'Herbert',
        });
        r.server.seed('/annotations', {
          'book_id': b,
          'quote': 'From the server.',
          'tags': <String>[],
          'color': 'yellow',
        });

        final res = await r.auto.syncNow();

        expect(res!.stoppedBy, isNull);
        expect(r.server.created['/quotes'], hasLength(1));
        expect(
          (await r.lib.quotes()).map((q) => q.text),
          contains('From the server.'),
        );
        expect(r.auto.lastSynced, r.clock.now);
        expect(r.auto.failure, isNull);
        expect(r.auto.syncing, isFalse);
      },
    );

    test('with no server paired does nothing', () async {
      final r = await rig(paired: false);
      expect(await r.auto.syncNow(), isNull);
      expect(r.server.requests, isEmpty);
    });

    test('tells its listeners when it starts and finishes', () async {
      final r = await rig();
      final seen = <bool>[];
      r.auto.addListener(() => seen.add(r.auto.syncing));
      await r.auto.syncNow();
      expect(seen.first, isTrue);
      expect(seen.last, isFalse);
    });

    test('a run called during a run joins it', () async {
      final r = await rig();
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});
      final a = r.auto.syncNow();
      final b = r.auto.syncNow();
      await Future.wait([a, b]);
      expect(reads(r), 1);
    });
  });

  group('conflicts are kept, not forced', () {
    test('a clash is held for the reader and nothing is changed', () async {
      final r = await rig();
      await clash(r);

      await r.auto.syncNow();

      expect(r.auto.conflicts, hasLength(1));
      expect((await r.lib.quotes()).single.note, 'phone note');
      expect(r.server.updated, isEmpty);
    });

    test(
      'still open on the next run; gone once settled, and not found again',
      () async {
        final r = await rig();
        await clash(r);
        await r.auto.syncNow();
        await r.auto.syncNow();
        expect(r.auto.conflicts, hasLength(1));

        final problem = await r.auto.resolve(
          r.auto.conflicts.single,
          ConflictSide.server,
        );

        expect(problem, isNull);
        expect(r.auto.conflicts, isEmpty);
        expect((await r.lib.quotes()).single.note, 'server note');
        await r.auto.syncNow();
        expect(r.auto.conflicts, isEmpty);
      },
    );

    test(
      'a choice the server refuses stays on the list with the reason',
      () async {
        final r = await rig();
        await clash(r);
        await r.auto.syncNow();
        r.server.failUpdatesWith = 400;

        final problem = await r.auto.resolve(
          r.auto.conflicts.single,
          ConflictSide.phone,
        );

        expect(problem, contains('refused'));
        expect(r.auto.conflicts, hasLength(1));
      },
    );

    testAuto(
      'a run never waits for the reader: the rest of the library syncs around a clash',
      (tester, r) async {
        await clash(r);
        r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});

        await r.auto.syncNow();

        expect(r.auto.conflicts, hasLength(1));
        expect((await r.lib.works()).map((w) => w.title), contains('Dune'));
      },
    );
  });

  group('when it runs', () {
    testAuto('on open, with no run ever made, it makes one', (tester, r) async {
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      expect((await r.lib.works()).map((w) => w.title), ['Dune']);
      expect(r.auto.lastSynced, r.clock.now);
    });

    testAuto('on open, a day after the last run, it makes one', (
      tester,
      r,
    ) async {
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      expect(await r.lib.works(), hasLength(1));
    }, lastRunAgo: const Duration(hours: 25));

    testAuto(
      'on open, within a day of the last run and nothing waiting, it asks nothing',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        expect(r.server.paths.where((p) => p == 'GET /books'), isEmpty);
        expect(r.auto.lastSynced, isNotNull);
      },
      lastRunAgo: const Duration(hours: 2),
    );

    testAuto(
      'on open, a change left waiting from last time goes, even within the day',
      (tester, r) async {
        await r.lib.addQuote(const QuoteDraft(text: 'Left waiting.'));
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        expect(r.server.created['/quotes'], hasLength(1));
        expect(r.auto.dirty, isFalse);
      },
      lastRunAgo: const Duration(hours: 2),
      waiting: true,
    );

    testAuto(
      'coming back to the front makes a run only if a day has passed or a change waits',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        expect(reads(r), 0);
        r.clock.advance(const Duration(hours: 25));
        r.auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle(tester, const Duration(seconds: 6));
        expect(reads(r), 1);
        r.auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle(tester, const Duration(seconds: 6));
        expect(
          reads(r),
          1,
          reason: 'a second coming back the same day asks nothing',
        );
      },
      lastRunAgo: const Duration(hours: 1),
    );

    testAuto(
      'a change to the library starts a run after a short wait; a burst is one run',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        final before = reads(r);

        await r.lib.addQuote(const QuoteDraft(text: 'One.'));
        await tester.pump(const Duration(seconds: 1));
        await r.lib.addQuote(const QuoteDraft(text: 'Two.'));
        await tester.pump(const Duration(seconds: 1));
        await r.lib.addQuote(const QuoteDraft(text: 'Three.'));
        expect(
          reads(r),
          before,
          reason: 'not yet: still waiting for the burst to end',
        );
        await settle(tester, const Duration(seconds: 6));

        expect(reads(r), before + 1);
        expect(r.server.created['/quotes'], hasLength(3));
        expect(r.auto.dirty, isFalse);
      },
      lastRunAgo: const Duration(hours: 1),
    );

    testAuto('what a sync itself writes does not start another sync', (
      tester,
      r,
    ) async {
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      final done = reads(r);
      await settle(tester, const Duration(seconds: 20));
      expect(reads(r), done);
    });

    testAuto(
      'left on, it makes the daily run when the day is up, and not before',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        r.clock.advance(const Duration(hours: 2));
        await tester.pump(const Duration(minutes: 31));
        await settle(tester, const Duration(seconds: 6));
        expect(reads(r), 0, reason: 'two hours on is not a day');
        r.clock.advance(const Duration(hours: 22));
        await tester.pump(const Duration(minutes: 31));
        await settle(tester, const Duration(seconds: 6));
        expect(reads(r), 1);
      },
      lastRunAgo: const Duration(hours: 1),
    );

    testAuto('there is no timer in between: hours pass with nothing asked', (
      tester,
      r,
    ) async {
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      for (var i = 0; i < 8; i++) {
        r.clock.advance(const Duration(hours: 2));
        await tester.pump(const Duration(minutes: 31));
        await tester.pump(const Duration(minutes: 31));
      }
      expect(reads(r), 0);
    }, lastRunAgo: const Duration(minutes: 5));

    testAuto(
      'turned off: it does not run by itself, but Sync now still works, and the choice is kept',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await r.auto.setEnabled(false);
        await settle(tester, const Duration(seconds: 6));
        final before = reads(r);

        await r.lib.addQuote(const QuoteDraft(text: 'Not yet.'));
        r.clock.advance(const Duration(days: 3));
        r.net.regain();
        await settle(tester, const Duration(minutes: 31));
        expect(reads(r), before);
        expect(r.server.created['/quotes'], isNull);

        await r.auto.syncNow();
        expect(r.server.created['/quotes'], hasLength(1));
        expect(
          (await SharedPreferences.getInstance()).getBool('auto_sync'),
          isFalse,
        );
      },
    );

    testAuto('a reader who turned it off finds it still off next time', (
      tester,
      r,
    ) async {
      SharedPreferences.setMockInitialValues({'auto_sync': false});
      await r.auto.start(null);
      expect(r.auto.enabled, isFalse);
    });
  });

  group('when the network comes back', () {
    testAuto('it makes the daily run if one is due', (tester, r) async {
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      expect(reads(r), 0);
      r.clock.advance(const Duration(hours: 25));
      r.net.regain();
      await settle(tester, const Duration(seconds: 6));
      expect(reads(r), 1);
    }, lastRunAgo: const Duration(hours: 1));

    testAuto('it asks nothing if the day is not up and nothing waits', (
      tester,
      r,
    ) async {
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      r.net.regain();
      await settle(tester, const Duration(seconds: 6));
      expect(reads(r), 0);
    }, lastRunAgo: const Duration(hours: 1));

    testAuto(
      'it sends a change that could not be sent while the phone was offline',
      (tester, r) async {
        r.server.failReadsWith = 500;
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        await r.lib.addQuote(const QuoteDraft(text: 'Made offline.'));
        await settle(tester, const Duration(seconds: 6));
        expect(r.auto.dirty, isTrue);
        expect(r.auto.failure, isNotNull);
        r.server.failReadsWith = null;
        r.net.regain();
        await settle(tester, const Duration(seconds: 6));
        expect(r.server.created['/quotes'], hasLength(1));
        expect(r.auto.dirty, isFalse);
        expect(r.auto.failure, isNull);
      },
      lastRunAgo: const Duration(hours: 1),
    );
  });

  group('when the server cannot be reached', () {
    testAuto(
      'the change is kept and not retried on a timer; the next opening sends it',
      (tester, r) async {
        r.server.failReadsWith = 500;
        await r.lib.addQuote(const QuoteDraft(text: 'Made while it was down.'));
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        expect(r.auto.failure, ApiFailure.server);
        expect(r.auto.dirty, isTrue);
        final n = r.server.requests.length;

        for (var i = 0; i < 6; i++) {
          r.clock.advance(const Duration(hours: 3));
          await tester.pump(const Duration(minutes: 31));
          await tester.pump(const Duration(minutes: 31));
        }
        expect(r.server.requests.length, n, reason: 'no timer asks again');

        r.server.failReadsWith = null;
        r.auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await settle(tester, const Duration(seconds: 6));
        expect(r.auto.failure, isNull);
        expect(r.auto.dirty, isFalse);
        expect(r.server.created['/quotes'], hasLength(1));
      },
      lastRunAgo: const Duration(hours: 1),
      waiting: true,
    );

    testAuto('the next change tries again', (tester, r) async {
      r.server.failReadsWith = 500;
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      r.server.failReadsWith = null;
      await r.lib.addQuote(const QuoteDraft(text: 'Next.'));
      await settle(tester, const Duration(seconds: 6));
      expect(r.auto.failure, isNull);
      expect(r.server.created['/quotes'], hasLength(1));
    });

    testAuto(
      'the time of the last finished run and the waiting flag are kept for next time',
      (tester, r) async {
        await r.auto.start(r.lib.changes);
        await settle(tester, const Duration(seconds: 6));
        final p = await SharedPreferences.getInstance();
        expect(p.getInt('auto_sync_last'), r.clock.now.millisecondsSinceEpoch);
        expect(p.getBool('auto_sync_dirty'), isFalse);
        r.server.failReadsWith = 500;
        await r.lib.addQuote(const QuoteDraft(text: 'Fails.'));
        await settle(tester, const Duration(seconds: 6));
        expect(p.getBool('auto_sync_dirty'), isTrue);
      },
    );

    testAuto('a server that refuses this phone is not asked again', (
      tester,
      r,
    ) async {
      r.server.tokenValid = false;
      await r.auto.start(r.lib.changes);
      await settle(tester, const Duration(seconds: 6));
      expect(r.auto.failure, ApiFailure.unauthorised);
      final n = r.server.requests.length;

      r.clock.advance(const Duration(days: 3));
      r.net.regain();
      r.auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle(tester, const Duration(seconds: 6));

      expect(r.server.requests.length, n);
    });
  });

  group('the screens', () {
    late FakeServer server;
    late MemoryLibrary lib;
    late Harness harness;

    Future<void> open(
      WidgetTester tester, {
      Future<void> Function(MemoryLibrary, FakeServer)? seed,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      server = FakeServer();
      lib = MemoryLibrary();
      if (seed != null) await seed(lib, server);
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final controller = AppController(store, clientFactory: server.factory);
      await controller.load();
      await controller.pair('ABCD2345', 'My Android phone');
      harness = Harness.fake(store, controller: controller, library: lib);
      await tester.pumpWidget(
        TippaniApp(controller: controller, harness: harness),
      );
      await tester.pumpAndSettle();
    }

    Future<void> withClash(MemoryLibrary l, FakeServer s) async {
      final w = await l.addWork(const WorkDraft(title: 'Walden', creator: 'T'));
      await l.setWorkServerId(w.id, 1);
      await l.markWorkSynced(w.id, 'x');
      s.seed('/books', {'title': 'Walden', 'author': 'T'}, id: 1);
      for (final (id, text) in [(10, 'First'), (11, 'Second')]) {
        final q = await l.addQuote(
          QuoteDraft(text: text, workId: w.id, note: 'phone $text'),
        );
        await l.setQuoteServerId(q.id, id);
        s.seed('/annotations', {
          'book_id': 1,
          'quote': text,
          'note': 'server $text',
          'translation': '',
          'language': '',
          'color': 'yellow',
          'favorite': false,
          'tags': <String>[],
          'chapter': '',
          'location': '',
          'character': '',
        }, id: id);
      }
    }

    testWidgets(
      'Settings has a Sync conflicts entry that says there is nothing to settle',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Sync conflicts'), findsOneWidget);
        expect(find.text('Nothing to settle'), findsOneWidget);
      },
    );

    testWidgets(
      'after a sync it counts them, and the Library bar shows them too',
      (tester) async {
        await open(tester, seed: withClash);
        await harness.auto!.syncNow();
        await tester.pumpAndSettle();

        expect(find.byTooltip('2 sync conflicts'), findsOneWidget);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('2 waiting for you'), findsOneWidget);
      },
    );

    testWidgets(
      'they can be settled one at a time, left, and come back to later',
      (tester) async {
        await open(tester, seed: withClash);
        await harness.auto!.syncNow();
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('2 sync conflicts'));
        await tester.pumpAndSettle();
        expect(find.text('Phone: phone First'), findsOneWidget);
        expect(find.text('Phone: phone Second'), findsOneWidget);

        await tester.tap(find.text('Keep the server’s').first);
        await tester.pumpAndSettle();
        expect(find.text('Phone: phone First'), findsNothing);
        expect(find.text('Phone: phone Second'), findsOneWidget);

        // leave the other one for later
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byTooltip('1 sync conflict'), findsOneWidget);
        await tester.tap(find.byTooltip('1 sync conflict'));
        await tester.pumpAndSettle();
        expect(find.text('Phone: phone Second'), findsOneWidget);
        final notes = {for (final q in await lib.quotes()) q.text: q.note};
        expect(notes['First'], 'server First');
        expect(notes['Second'], 'phone Second');
      },
    );

    testWidgets(
      'the Sync screen shows the switch and Sync now, and points to the conflicts',
      (tester) async {
        await open(tester, seed: withClash);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sync with server'));
        await tester.pumpAndSettle();
        expect(find.text('Sync automatically'), findsOneWidget);
        await tester.tap(find.text('Sync now'));
        await tester.pumpAndSettle();
        expect(find.text('2 conflicts waiting: settle them'), findsOneWidget);
        expect(find.textContaining('Last synced'), findsOneWidget);
      },
    );

    testWidgets('the switch turns automatic sync off', (tester) async {
      await open(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync with server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(harness.auto!.enabled, isFalse);
    });
  });
}
