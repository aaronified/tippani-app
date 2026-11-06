import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/harness/log_screen.dart' show ShareText;
import 'package:tippani/harness/server_log.dart';
import 'package:tippani/harness/server_log_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';

Map<String, Object?> line(
  int id,
  String level,
  String text, {
  int at = 1762400000000,
  String code = '',
}) => {'id': id, 'at': at, 'level': level, 'code': code, 'line': text};

class Rig {
  Rig(this.server, this.store, this.controller, this.log);
  final FakeServer server;
  final SettingsStore store;
  final AppController controller;
  final AppLog log;
}

Future<Rig> paired(FakeServer server) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
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
  await controller.pair('ABCD2345', 'My Android phone');
  return Rig(server, store, controller, log);
}

Widget screen(Rig r, {ShareText? share}) => MaterialApp(
  home: ServerLogScreen(
    controller: r.controller,
    share: share ?? (text, subject) async {},
  ),
);

/// Settings is a long lazy list; a tile below the fold is not built until it is scrolled to.
Future<void> scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
  await tester.pumpAndSettle();
}

void main() {
  group('the request', () {
    test('the first page asks for a window ending now, by length, and the levels in the server\'s order', () {
      final path = serverLogPath(
        const ServerLogFilter(
          levels: {'request', 'error'},
          since: Duration(hours: 1),
        ),
      );
      final q = Uri.parse(path).queryParameters;
      expect(Uri.parse(path).path, '/admin/logs');
      expect(q['level'], 'error,request');
      expect(q['since'], '3600000');
      expect(q.containsKey('from'), isFalse);
      expect(q['limit'], '200');
    });

    test('a later page sends back the window the first answer gave, never since, plus before', () {
      final path = serverLogPath(
        const ServerLogFilter(),
        from: 1000,
        upto: 99,
        before: 42,
      );
      final q = Uri.parse(path).queryParameters;
      expect(q['from'], '1000');
      expect(q['upto'], '99');
      expect(q['before'], '42');
      expect(
        q.containsKey('since'),
        isFalse,
        reason: 'the server rejects since and from together',
      );
    });

    test('a keyword is sent trimmed and an empty one is not sent', () {
      expect(
        Uri.parse(serverLogPath(const ServerLogFilter(query: '  50% errors ')))
            .queryParameters['q'],
        '50% errors',
      );
      expect(
        Uri.parse(serverLogPath(const ServerLogFilter(query: '   ')))
            .queryParameters
            .containsKey('q'),
        isFalse,
      );
    });

    test('by default the file requests and traces are left out, as the server does', () {
      expect(defaultServerLogLevels, {'error', 'warn', 'info', 'request'});
    });
  });

  group('the answer', () {
    test('a page is read, with its window and whether more remains', () async {
      final s = FakeServer(admin: true)
        ..logLines.addAll([line(3, 'error', 'boom'), line(2, 'info', 'hello')]);
      final r = await paired(s);
      final page = await r.controller.withClient(
        (c) => fetchServerLog(c, const ServerLogFilter()),
      );
      expect(page!.lines.map((l) => l.id), [3, 2]);
      expect(page.lines.first.line, 'boom');
      expect(page.more, isFalse);
      expect(page.from, 1000);
      expect(page.upto, 99);
    });

    test('a line that is not a line is skipped, not fatal', () {
      expect(ServerLogLine.fromJson({'id': 'x'}), isNull);
      expect(ServerLogLine.fromJson('no'), isNull);
      expect(ServerLogLine.fromJson({'id': 1, 'at': 5})?.line, '');
    });

    test(
      'text is oldest first, one line each, with the time, level and code',
      () {
        final text = serverLogText([
          const ServerLogLine(
            id: 2,
            at: 1762400060000,
            level: 'error',
            code: 'E1',
            line: 'second',
          ),
          const ServerLogLine(
            id: 1,
            at: 1762400000000,
            level: 'info',
            code: '',
            line: 'first',
          ),
        ]);
        final lines = text.trim().split('\n');
        expect(lines, hasLength(2));
        expect(lines[0], endsWith('Z [info] first'));
        expect(lines[1], endsWith('Z [error] E1 second'));
      },
    );

    test(
      'a credential in a line is taken out before the text can leave the phone',
      () {
        final text = serverLogText([
          ServerLogLine(
            id: 1,
            at: 1762400000000,
            level: 'request',
            code: '',
            line: 'GET /x Authorization: Bearer ${'a1' * 20}',
          ),
        ]);
        expect(text, contains('Bearer [redacted]'));
        expect(text, isNot(contains('a1a1a1a1')));
      },
    );
  });

  group('the screen', () {
    testWidgets(
      'an admin sees the lines, newest first, and a note that this is the server\'s log',
      (tester) async {
        final s = FakeServer(admin: true)
          ..logLines.addAll([
            line(3, 'error', 'disk nearly full'),
            line(2, 'info', 'backup finished'),
          ]);
        await tester.pumpWidget(screen(await paired(s)));
        await tester.pumpAndSettle();
        expect(find.textContaining('disk nearly full'), findsOneWidget);
        expect(find.textContaining('backup finished'), findsOneWidget);
        expect(
          find.textContaining("The server's own log, not this phone's"),
          findsOneWidget,
        );
        final first = tester
            .getTopLeft(find.textContaining('disk nearly full'))
            .dy;
        final second = tester
            .getTopLeft(find.textContaining('backup finished'))
            .dy;
        expect(first, lessThan(second), reason: 'newest first');
      },
    );

    testWidgets(
      'a level chip narrows the request, and the last chip cannot be turned off',
      (tester) async {
        final s = FakeServer(admin: true)
          ..logLines.addAll([
            line(2, 'error', 'an error'),
            line(1, 'info', 'an info'),
          ]);
        await tester.pumpWidget(screen(await paired(s)));
        await tester.pumpAndSettle();
        for (final level in ['warn', 'info', 'request']) {
          await tester.tap(find.widgetWithText(FilterChip, level));
          await tester.pumpAndSettle();
        }
        final asked = s.requests
            .where((r) => r.url.path.endsWith('/admin/logs'))
            .last
            .url
            .queryParameters;
        expect(asked['level'], 'error');
        expect(find.textContaining('an error'), findsOneWidget);
        expect(find.textContaining('an info'), findsNothing);
        await tester.tap(find.widgetWithText(FilterChip, 'error'));
        await tester.pumpAndSettle();
        expect(
          s.requests
              .where((r) => r.url.path.endsWith('/admin/logs'))
              .last
              .url
              .queryParameters['level'],
          'error',
          reason: 'turning off the last level would ask for every level',
        );
      },
    );

    testWidgets('a search sends the keyword', (tester) async {
      final s = FakeServer(admin: true)
        ..logLines.addAll([
          line(2, 'info', 'imported 12 books'),
          line(1, 'info', 'signed in'),
        ]);
      await tester.pumpWidget(screen(await paired(s)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search the log'),
        'books',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(s.requests.last.url.queryParameters['q'], 'books');
      expect(find.textContaining('imported 12 books'), findsOneWidget);
      expect(find.textContaining('signed in'), findsNothing);
    });

    testWidgets('a window chip changes how far back is asked', (tester) async {
      final s = FakeServer(admin: true)..logLines.add(line(1, 'info', 'x'));
      await tester.pumpWidget(screen(await paired(s)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Last hour'));
      await tester.pumpAndSettle();
      expect(s.requests.last.url.queryParameters['since'], '3600000');
    });

    testWidgets(
      'Load older lines pages on with before and the first answer\'s window',
      (tester) async {
        final s = FakeServer(admin: true);
        for (var i = 250; i >= 1; i--) {
          s.logLines.add(line(i, 'info', 'line number $i'));
        }
        await tester.pumpWidget(screen(await paired(s)));
        await tester.pumpAndSettle();
        expect(
          find.text('Load older lines'),
          findsNothing,
          reason: 'it is below the first 200 and the list is lazy',
        );
        await tester.scrollUntilVisible(
          find.text('Load older lines'),
          400,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Load older lines'));
        await tester.pumpAndSettle();
        final q = s.requests
            .where((r) => r.url.path.endsWith('/admin/logs'))
            .last
            .url
            .queryParameters;
        expect(
          q['before'],
          '51',
          reason: 'the oldest id of the first page of 200 (250 down to 51)',
        );
        expect(q['from'], '1000');
        expect(q['upto'], '99');
        expect(q.containsKey('since'), isFalse);
      },
    );

    testWidgets(
      'Share hands over only the server\'s lines, oldest first, redacted',
      (tester) async {
        final s = FakeServer(admin: true)
          ..logLines.addAll([
            line(2, 'info', 'second ${'ab' * 25}'),
            line(1, 'info', 'first'),
          ]);
        final r = await paired(s);
        r.log.info(
          'a line from the APP log that must not be in the server share',
        );
        String? shared;
        String? subject;
        await tester.pumpWidget(
          screen(
            r,
            share: (text, sub) async {
              shared = text;
              subject = sub;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Share'));
        await tester.pumpAndSettle();
        expect(subject, 'Tippani server log');
        expect(shared!.indexOf('first'), lessThan(shared!.indexOf('second')));
        expect(shared, contains('[redacted]'));
        expect(shared, isNot(contains('APP log')));
      },
    );

    testWidgets(
      'a phone paired as a non-admin is told only an admin can read it, and stays paired',
      (tester) async {
        final s = FakeServer(admin: false);
        final r = await paired(s);
        await tester.pumpWidget(screen(r));
        await tester.pumpAndSettle();
        expect(find.textContaining('Only an admin can read'), findsOneWidget);
        expect(
          r.controller.paired,
          isTrue,
          reason: 'a 403 is not a refused token',
        );
        expect(r.controller.revoked, isFalse);
      },
    );

    testWidgets('a token the server no longer accepts says to pair again', (
      tester,
    ) async {
      final s = FakeServer(admin: true)..logLines.add(line(1, 'info', 'x'));
      final r = await paired(s);
      s.tokenValid = false;
      await tester.pumpWidget(screen(r));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no longer accepts this phone'),
        findsOneWidget,
      );
    });

    testWidgets('no lines match says so', (tester) async {
      final s = FakeServer(admin: true);
      await tester.pumpWidget(screen(await paired(s)));
      await tester.pumpAndSettle();
      expect(find.text('No lines match.'), findsOneWidget);
    });
  });

  group('two logs, kept apart', () {
    testWidgets(
      'Settings has the app log for everyone and the server log only for an admin',
      (tester) async {
        Future<void> settingsFor(FakeServer s) async {
          final r = await paired(s);
          await tester.pumpWidget(
            TippaniApp(
              controller: r.controller,
              harness: Harness.fake(
                r.store,
                controller: r.controller,
                log: r.log,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
        }

        await settingsFor(FakeServer(admin: false));

        await scrollToBottom(tester);
        expect(find.text('App log'), findsOneWidget);
        expect(find.text('Server log'), findsNothing);

        await settingsFor(FakeServer(admin: true));

        await scrollToBottom(tester);
        expect(find.text('App log'), findsOneWidget);
        expect(find.text('Server log'), findsOneWidget);
      },
    );

    testWidgets(
      'the app log screen never shows a server line, and the server log never shows an app line',
      (tester) async {
        final s = FakeServer(admin: true)
          ..logLines.add(line(1, 'info', 'SERVER-ONLY-LINE'));
        final r = await paired(s);
        r.log.info('APP-ONLY-LINE');
        await tester.pumpWidget(
          TippaniApp(
            controller: r.controller,
            harness: Harness.fake(
              r.store,
              controller: r.controller,
              log: r.log,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        await scrollToBottom(tester);

        await tester.tap(find.text('App log'));
        await tester.pumpAndSettle();
        expect(find.textContaining('APP-ONLY-LINE'), findsOneWidget);
        expect(find.textContaining('SERVER-ONLY-LINE'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await scrollToBottom(tester);

        await tester.tap(find.text('Server log'));
        await tester.pumpAndSettle();
        expect(find.textContaining('SERVER-ONLY-LINE'), findsOneWidget);
        expect(find.textContaining('APP-ONLY-LINE'), findsNothing);
      },
    );

    test('asking for the server\'s log writes nothing of its lines into the app log', () async {
      final s = FakeServer(admin: true)
        ..logLines.add(line(1, 'info', 'SERVER-ONLY-LINE'));
      final r = await paired(s);
      await r.controller.withClient(
        (c) => fetchServerLog(c, const ServerLogFilter()),
      );
      expect(r.log.text(), isNot(contains('SERVER-ONLY-LINE')));
    });

    test('a failed fetch is an ApiException the screen can word, with the kind kept', () async {
      final s = FakeServer(admin: false);
      final r = await paired(s);
      try {
        await r.controller.withClient(
          (c) => fetchServerLog(c, const ServerLogFilter()),
        );
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.failure, ApiFailure.forbidden);
      }
    });
  });
}
