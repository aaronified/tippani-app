import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/sync_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/push_sync.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

void main() {
  group('describePush', () {
    test('nothing to do says everything is already there', () {
      expect(describePush(const PushResult()), [
        'Everything in your library is already on your server.',
      ]);
    });

    test('a complete push says what went, with singular and plural right', () {
      expect(describePush(const PushResult(worksSent: 1, quotesSent: 2)), [
        'Sent 1 work and 2 quotes to your server.',
      ]);
      expect(describePush(const PushResult(quotesSent: 1)), [
        'Sent 1 quote to your server.',
      ]);
    });

    test('quotes the server already had are linked, not copied', () {
      final lines = describePush(const PushResult(alreadyThere: 2));
      expect(lines.single, contains('2 quotes were already on the server'));
      expect(lines.single, contains('linked, not copied'));
    });

    test('a stop says why, what is left, and that what went up stays', () {
      final lines = describePush(
        const PushResult(
          quotesSent: 3,
          waiting: 2,
          stoppedBy: ApiFailure.network,
        ),
      );
      expect(lines[0], 'Sent 3 quotes to your server.');
      expect(lines[1], contains('could not be reached'));
      expect(lines[1], contains('stays there'));
      expect(lines[2], '2 quotes are still waiting to be sent.');
    });

    test('each reason a push stops has its own words', () {
      String one(ApiFailure f) =>
          describePush(PushResult(stoppedBy: f)).join(' ');
      expect(one(ApiFailure.unauthorised), contains('Pair it again'));
      expect(one(ApiFailure.rateLimited), contains('slow down'));
      expect(one(ApiFailure.forbidden), contains('not allowed'));
      expect(one(ApiFailure.server), contains('error'));
      expect(one(ApiFailure.timeout), contains('could not be reached'));
    });

    test('a refusal names the item by its number and the server\'s reason', () {
      final lines = describePush(
        const PushResult(
          worksSent: 1,
          refused: [PushRefusal('work 4', 'title is not acceptable')],
          waiting: 1,
        ),
      );
      expect(
        lines,
        contains('The server refused work 4: title is not acceptable.'),
      );
      expect(lines, contains('1 quote is still waiting to be sent.'));
    });
  });

  group('the screen, from Settings', () {
    late FakeServer server;
    late MemoryLibrary lib;

    Future<void> open(WidgetTester tester, {bool pair = true}) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      server = FakeServer();
      lib = MemoryLibrary();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final controller = AppController(store, clientFactory: server.factory);
      await controller.load();
      if (pair) await controller.pair('ABCD2345', 'My Android phone');
      final w = await lib.addWork(const WorkDraft(title: 'Walden'));
      await lib.addQuote(QuoteDraft(text: 'Simplify.', workId: w.id));
      await lib.addQuote(const QuoteDraft(text: 'A proverb.'));
      await tester.pumpWidget(
        TippaniApp(
          controller: controller,
          harness: Harness.fake(store, controller: controller, library: lib),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
    }

    testWidgets('an unpaired phone is not offered the push', (tester) async {
      await open(tester, pair: false);
      expect(find.text('Send library to server'), findsNothing);
    });

    testWidgets(
      'it says what is waiting, sends it, says what went, and then has nothing waiting',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Send library to server'));
        await tester.pumpAndSettle();
        expect(
          find.text('Waiting to be sent: 1 work and 2 quotes.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Send to server'));
        await tester.pumpAndSettle();
        expect(
          find.text('Sent 1 work and 2 quotes to your server.'),
          findsOneWidget,
        );
        expect(find.text('Nothing is waiting.'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(server.created['/books'], hasLength(1));
        expect(server.created['/annotations'], hasLength(1));
        expect(server.created['/quotes'], hasLength(1));
      },
    );

    testWidgets(
      'a server that cannot be reached is said so, and what is left stays waiting',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Send library to server'));
        await tester.pumpAndSettle();
        server.dropAfter = 1;
        await tester.tap(find.text('Send to server'));
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be reached'), findsOneWidget);
        expect(
          find.text('2 quotes are still waiting to be sent.'),
          findsOneWidget,
        );
        expect(
          find.text('Waiting to be sent: 0 works and 2 quotes.'),
          findsOneWidget,
        );
      },
    );
  });
}
