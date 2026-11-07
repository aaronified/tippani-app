import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/pull_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/fingerprint.dart';
import 'package:tippani/sync/pull_sync.dart';
import 'package:tippani/sync/push_sync.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

void main() {
  group('describePull', () {
    test('nothing at all says the two agree', () {
      expect(describePull(const PullResult()), [
        'Your phone and your server already agree.',
      ]);
    });

    test(
      'what came down and what went up are counted, singular and plural',
      () {
        final lines = describePull(
          const PullResult(
            worksAdded: 1,
            quotesAdded: 2,
            quotesUpdated: 1,
            worksSent: 1,
            quotesSent: 3,
          ),
        );
        expect(
          lines[0],
          'Brought down: 1 new work, 2 new quotes, 1 changed quote.',
        );
        expect(lines[1], 'Sent up your changes to 1 work and 3 quotes.');
      },
    );

    test('a clash says nothing was changed for it', () {
      final lines = describePull(
        PullResult(
          conflicts: [
            const SyncConflict(
              isWork: false,
              localId: 1,
              realm: _book,
              serverId: 1,
              title: 't',
              diffs: [],
              serverFields: {},
              serverRow: {},
            ),
          ],
        ),
      );
      expect(lines.single, contains('1 item changed on both sides'));
      expect(lines.single, contains('Nothing was changed for it'));
    });

    test('items left alone, skipped and refused are each said', () {
      final lines = describePull(
        const PullResult(
          goneOnServer: 2,
          skipped: 1,
          refused: [PushRefusal('quote 4', 'colour is not one of them')],
        ),
      ).join('\n');
      expect(
        lines,
        contains(
          '2 items were removed on the server while syncing, and left alone here.',
        ),
      );
      expect(lines, contains('1 item on the server could not be brought down'));
      expect(
        lines,
        contains('The server refused quote 4: colour is not one of them.'),
      );
    });

    test('deletes and a distrusted server are each said', () {
      final lines = describePull(
        const PullResult(
          deletedThere: 1,
          deletedHere: 2,
          relinked: 1,
          heldBack: 15,
        ),
      ).join('\n');
      expect(
        lines,
        contains('1 item you deleted here was deleted on the server too'),
      );
      expect(
        lines,
        contains('2 items deleted on the server were removed here too'),
      );
      expect(
        lines,
        contains('1 item deleted on the server but changed here was kept'),
      );
      expect(lines, contains('15 items are missing from the server'));
      expect(lines, contains('nothing was removed here'));
    });

    test('each reason a sync stops has its own words', () {
      String one(ApiFailure f) =>
          describePull(PullResult(stoppedBy: f)).join(' ');
      expect(one(ApiFailure.network), contains('could not be reached'));
      expect(one(ApiFailure.unauthorised), contains('Pair it again'));
      expect(one(ApiFailure.rateLimited), contains('slow down'));
      expect(one(ApiFailure.forbidden), contains('not allowed'));
      expect(one(ApiFailure.server), contains('error'));
    });
  });

  group('the screen, from Settings', () {
    late FakeServer server;
    late MemoryLibrary lib;

    Future<void> open(
      WidgetTester tester, {
      bool pair = true,
      Future<void> Function(MemoryLibrary lib, FakeServer server)? seed,
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
      if (pair) await controller.pair('ABCD2345', 'My Android phone');
      await tester.pumpWidget(
        TippaniApp(
          controller: controller,
          harness: Harness.fake(store, controller: controller, library: lib),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
    }

    /// A quote the phone and the server both hold, whose note each side has written differently, and which
    /// the phone has never recorded an agreement for, so it is a clash.
    Future<void> clash(
      MemoryLibrary lib,
      FakeServer server,
      String text, {
      required int serverWork,
      required int workId,
      required int serverQuote,
    }) async {
      final q = await lib.addQuote(
        QuoteDraft(text: text, workId: workId, note: 'phone note on $text'),
      );
      await lib.setQuoteServerId(q.id, serverQuote);
      server.seed('/annotations', {
        'book_id': serverWork,
        'quote': text,
        'note': 'server note on $text',
        'translation': '',
        'language': '',
        'color': 'yellow',
        'favorite': false,
        'tags': <String>[],
        'chapter': '',
        'location': '',
        'character': '',
      }, id: serverQuote);
    }

    Future<void> twoClashes(MemoryLibrary lib, FakeServer server) async {
      final w = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      await lib.setWorkServerId(w.id, 1);
      await lib.markWorkSynced(w.id, 'x');
      server.seed('/books', {'title': 'Walden', 'author': 'Thoreau'}, id: 1);
      await clash(
        lib,
        server,
        'First',
        serverWork: 1,
        workId: w.id,
        serverQuote: 10,
      );
      await clash(
        lib,
        server,
        'Second',
        serverWork: 1,
        workId: w.id,
        serverQuote: 11,
      );
    }

    testWidgets('an unpaired phone is not offered the sync', (tester) async {
      await open(tester, pair: false);
      expect(find.text('Sync with server'), findsNothing);
    });

    testWidgets('sync now brings down what is new and says so', (tester) async {
      await open(
        tester,
        seed: (lib, server) async {
          final b = server.seed('/books', {
            'title': 'Dune',
            'author': 'Herbert',
          });
          server.seed('/annotations', {
            'book_id': b,
            'quote': 'Fear.',
            'tags': <String>[],
            'color': 'yellow',
          });
        },
      );
      await tester.tap(find.text('Sync with server'));
      await tester.pumpAndSettle();
      expect(find.text('Sync now'), findsOneWidget);
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(
        find.text('Brought down: 1 new work, 1 new quote.'),
        findsOneWidget,
      );
      expect(find.text('Changed on both sides'), findsNothing);
      expect((await lib.quotes()).single.text, 'Fear.');
    });

    testWidgets(
      'a clash shows both versions and nothing changes until a choice is made; keep the server\'s changes the phone only',
      (tester) async {
        await open(tester, seed: twoClashes);
        await tester.tap(find.text('Sync with server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sync now'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('conflicts waiting'));
        await tester.pumpAndSettle();

        expect(find.text('Changed on both sides'), findsOneWidget);
        expect(find.text('Phone: phone note on First'), findsOneWidget);
        expect(find.text('Server: server note on First'), findsOneWidget);
        expect(find.text('Keep the phone’s'), findsNWidgets(2));
        expect(find.text('Keep the server’s'), findsNWidgets(2));
        expect(
          (await lib.quotes()).map((q) => q.note),
          everyElement(startsWith('phone')),
        );

        await tester.tap(find.text('Keep the server’s').first);
        await tester.pumpAndSettle();

        expect(find.text('Phone: phone note on First'), findsNothing);
        expect(find.text('Phone: phone note on Second'), findsOneWidget);
        final notes = {for (final q in await lib.quotes()) q.text: q.note};
        expect(notes['First'], 'server note on First');
        expect(notes['Second'], 'phone note on Second');
        expect(server.updated, isEmpty);
      },
    );

    testWidgets('keep the phone\'s sends that quote up', (tester) async {
      await open(tester, seed: twoClashes);
      await tester.tap(find.text('Sync with server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('conflicts waiting'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep the phone’s').first);
      await tester.pumpAndSettle();

      expect(server.updated, hasLength(1));
      expect(server.updated.single.body['note'], 'phone note on First');
      expect(server.row('/annotations', 11)['note'], 'server note on Second');
    });

    testWidgets('choosing for all asks first, and Cancel changes nothing', (
      tester,
    ) async {
      await open(tester, seed: twoClashes);
      await tester.tap(find.text('Sync with server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('conflicts waiting'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep the server’s for all'));
      await tester.pumpAndSettle();
      expect(find.text('Keep the server’s for all?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Changed on both sides'), findsOneWidget);
      expect(
        (await lib.quotes()).map((q) => q.note),
        everyElement(startsWith('phone')),
      );

      await tester.tap(find.text('Keep the server’s for all'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Keep the server’s'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Changed on both sides'), findsNothing);
      expect(
        (await lib.quotes()).map((q) => q.note),
        everyElement(startsWith('server')),
      );
    });

    testWidgets('a choice the server refuses stays on screen with the reason', (
      tester,
    ) async {
      await open(tester, seed: twoClashes);
      await tester.tap(find.text('Sync with server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('conflicts waiting'));
      await tester.pumpAndSettle();
      server.failUpdatesWith = 400;

      await tester.tap(find.text('Keep the phone’s').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('The server refused it'), findsOneWidget);
      expect(find.text('Phone: phone note on First'), findsOneWidget);
    });
  });
}

const _book = Realm.book;
