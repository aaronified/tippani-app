import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/checks/checks_service.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/people/people_console.dart';
import 'package:tippani/screens/admin_users_screen.dart';
import 'package:tippani/screens/checks_screen.dart';
import 'package:tippani/screens/devices_screen.dart';
import 'package:tippani/screens/offline_note.dart';
import 'package:tippani/screens/people_console_screen.dart';
import 'package:tippani/screens/tags_screen.dart';
import 'package:tippani/screens/tools_screens.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tags/tag_service.dart';
import 'package:tippani/tools/server_tools.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

// One rule for every screen that shows what the server holds (ADR-0032): the phone's copy is drawn at once, the
// server is asked behind it, the answer replaces the copy in place, and the shared note says when the screen is
// showing the phone's copy. The server is the shared FakeServer, made slow, silent or failing; the screens are the
// real ones over the real services, so each test is what a reader sees.

const _offline = 'The server cannot be reached';

/// Any bar or ring that says something is loading.
final _spinner = find.byWidgetPredicate((w) => w is ProgressIndicator);

class _Rig {
  _Rig(this.server, this.controller);
  final FakeServer server;
  final AppController controller;
}

Future<_Rig> _rig(
  WidgetTester tester, {
  required void Function(_Rig) serves,
}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final controller = AppController(store, clientFactory: server.factory);
  final r = _Rig(server, controller);
  await tester.runAsync(() async {
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
  });
  serves(r);
  return r;
}

Widget _framed(_Rig r, Widget home) => OfflineScope(
  offline: r.controller.offline,
  child: MaterialApp(home: home),
);

/// Lets the fake server's answers (microtasks and real timers) land, then draws.
Future<void> _answered(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

/// The server wakes up and answers; nothing is asked of the screen.
Future<void> _release(WidgetTester tester, Completer<void> wait) async {
  wait.complete();
  await _answered(tester);
}

// ── each screen, as a table: how to serve it, how to open it, and the words that tell its answers apart ───────

class _Case {
  const _Case(
    this.name,
    this.serve,
    this.open,
    this.old,
    this.fresh,
    this.writePath, {
    this.retries = true,
  });
  final String name;

  /// Where a change the reader makes elsewhere in the app lands, in the same part of the server.
  final String writePath;

  /// Whether, with nothing to show and the server unreadable, it offers Try again (the Tags and Devices screens
  /// show the phone's own tags and say why, or say why under a bar, and are read again by pulling).
  final bool retries;

  /// Makes the server say [words] for this screen.
  final void Function(_Rig r, String words) serve;

  /// The screen, as the app builds it.
  final Widget Function(_Rig r) open;

  /// What the phone's copy says, and what the server says after it.
  final String old;
  final String fresh;
}

Map<String, Object?> _statsBody(String quotes) => {
  'annotations': int.parse(quotes),
  'books': 2,
  'favorites': 1,
  'daily_activity': <Object?>[],
};

final _cases = <_Case>[
  _Case(
    'Statistics',
    (r, words) =>
        r.server.extra = (req, path) async =>
            path == '/stats' ? r.server.json(_statsBody(words)) : null,
    (r) => StatsScreen(tools: PairedServerTools(r.controller)),
    '4111',
    '4222',
    '/quotes/touch',
  ),
  _Case(
    'Tags',
    (r, words) => r.server.tags
      ..clear()
      ..add({
        'id': 1,
        'name': words,
        'color': 'yellow',
        'style': 'sticker',
        'annotations': 2,
        'dialogues': 0,
      }),
    (r) => TagsScreen(
      store: MemoryLibrary(),
      picker: const _NoPicker(),
      service: PairedTagService(r.controller),
    ),
    'oldname',
    'newname',
    '/tags/touch',
    retries: false,
  ),
  _Case(
    'People',
    (r, words) =>
        r.server.extra = (req, path) async => path == '/people/records'
        ? r.server.json({
            'people': [
              {
                'id': 1,
                'name': words,
                'kinds': ['author'],
                'works': 1,
              },
            ],
          })
        : path == '/people/orphans'
        ? r.server.json({'people': 0, 'characters': 0})
        : null,
    (r) => PeopleConsoleScreen(
      console: PairedPeopleConsole(r.controller),
      onFilter: (_) {},
    ),
    'Oldperson',
    'Newperson',
    '/people/touch',
  ),
  _Case(
    'Checks',
    (r, words) => r.server.extra = (req, path) async => path == '/cleanup'
        ? r.server.json({
            'rules': <Object?>[],
            'counts': {'open': 1, 'ignored': 0},
            'items': [
              {
                'kind': 'book',
                'id': 1,
                'work_id': 1,
                'work_title': words,
                'findings': [
                  {
                    'rule': 'spaces',
                    'field': 'quote',
                    'snippet': 'a  b',
                    'after_snippet': 'a b',
                    'count': 1,
                    'hash': 'h1',
                    'ignored': false,
                  },
                ],
              },
            ],
          })
        : null,
    (r) => ChecksScreen(checks: PairedChecksService(r.controller)),
    'Oldwork',
    'Newwork',
    '/cleanup/touch',
  ),
  _Case(
    'Devices',
    (r, words) => r.server.devices
      ..clear()
      ..add({
        'id': 3,
        'name': words,
        'created_at': '2026-11-06 12:00:00',
        'last_seen_at': '',
      }),
    (r) => DevicesScreen(controller: r.controller),
    'Oldphone',
    'Newphone',
    '/auth/touch',
    retries: false,
  ),
  _Case(
    'Users',
    (r, words) => r.server.extra = (req, path) async => path == '/admin/users'
        ? r.server.json({
            'users': [
              {'id': 1, 'username': words, 'is_admin': true},
            ],
          })
        : null,
    (r) => AdminUsersScreen(service: PairedAdminService(r.controller)),
    'Oldreader',
    'Newreader',
    '/admin/touch',
  ),
  _Case(
    'the bin',
    (r, words) => r.server.trash
      ..clear()
      ..add({
        'id': 1,
        'kind': 'annotation',
        'label': words,
        'deleted_at': '2026-11-06 12:00:00',
      }),
    (r) => BinScreen(tools: PairedServerTools(r.controller)),
    'Oldbin',
    'Newbin',
    '/trash/touch',
  ),
];

class _NoPicker implements BackupPicker {
  const _NoPicker();
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<PickedFile?> pick() async => null;
}

/// Gives [c] a look: the Checks screen opens on Imports, and what it holds is on the Stray marks tab.
Future<void> _lookAt(WidgetTester tester, _Case c) async {
  if (c.name == 'Checks') {
    await tester.pump();
    await tester.tap(find.text('Stray marks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// A reader who has seen [c]'s screen with the server saying [Case.old]: the phone now holds it.
Future<_Rig> _seen(WidgetTester tester, _Case c) async {
  final r = await _rig(tester, serves: (_) {});
  c.serve(r, c.old);
  await tester.pumpWidget(_framed(r, c.open(r)));
  await _lookAt(tester, c);
  await _answered(tester);
  expect(find.textContaining(c.old), findsWidgets, reason: '${c.name} read');
  await tester.pumpWidget(const SizedBox());
  return r;
}

void main() {
  for (final c in _cases) {
    group(c.name, () {
      testWidgets(
        'with a copy and a server that never answers, it is there at once, '
        'and says it is the phone\'s copy once the server is given up on',
        (tester) async {
          final r = await _seen(tester, c);
          c.serve(r, c.fresh);
          r.server.readsWait = Completer<void>().future;
          await tester.pumpWidget(_framed(r, c.open(r)));
          await _lookAt(tester, c);
          await tester.pump();
          await tester.pump();
          expect(find.textContaining(c.old), findsWidgets);
          expect(_spinner, findsNothing);
          expect(find.textContaining(_offline), findsNothing);
          // each question the screen asks waits out its own timeout; the first is enough to say so
          await tester.pump(const Duration(seconds: 20));
          expect(find.textContaining(c.old), findsWidgets);
          expect(find.textContaining(_offline), findsOneWidget);
          await tester.pump(const Duration(minutes: 2));
        },
      );

      testWidgets(
        'with a copy and a slow server, the copy shows first and the fresh answer replaces it in place',
        (tester) async {
          final r = await _seen(tester, c);
          c.serve(r, c.fresh);
          final wait = Completer<void>();
          r.server.readsWait = wait.future;
          await tester.pumpWidget(_framed(r, c.open(r)));
          await _lookAt(tester, c);
          await tester.pump();
          await tester.pump();
          expect(find.textContaining(c.old), findsWidgets);
          await _release(tester, wait);
          expect(find.textContaining(c.old), findsNothing);
          expect(find.textContaining(c.fresh), findsWidgets);
          expect(find.textContaining(_offline), findsNothing);
        },
      );

      testWidgets(
        'with no copy and a server that never answers, it waits, then says it could not be read',
        (tester) async {
          final r = await _rig(tester, serves: (_) {});
          c.serve(r, c.fresh);
          r.server.readsWait = Completer<void>().future;
          await tester.pumpWidget(_framed(r, c.open(r)));
          await _lookAt(tester, c);
          await tester.pump();
          expect(_spinner, findsWidgets);
          await tester.pump(const Duration(seconds: 20));
          await tester.pump();
          expect(find.textContaining(c.fresh), findsNothing);
          expect(_spinner, findsNothing);
          expect(
            find.text('Try again'),
            c.retries ? findsOneWidget : findsNothing,
          );
        },
      );

      testWidgets(
        'a refresh the server refuses never blanks the copy, and says it is the phone\'s',
        (tester) async {
          final r = await _seen(tester, c);
          c.serve(r, c.fresh);
          r.server.refuseReadsWith = 500;
          await tester.pumpWidget(_framed(r, c.open(r)));
          await _lookAt(tester, c);
          await _answered(tester);
          expect(find.textContaining(c.old), findsWidgets);
          expect(find.text('Try again'), findsNothing);
          expect(find.textContaining(_offline), findsOneWidget);
        },
      );

      testWidgets(
        'after the reader changed what it shows elsewhere, the phone\'s older copy is not drawn first',
        (tester) async {
          final r = await _seen(tester, c);
          c.serve(r, c.fresh);
          // a change made through the app, to the same part of the server
          final serving = r.server.extra;
          r.server.extra = (req, path) async => req.method == 'POST'
              ? r.server.json({})
              : serving?.call(req, path);
          await tester.runAsync(
            () => r.controller.withClient<Object?>(
              (client) => client.postJson(c.writePath, {}),
            ),
          );
          final wait = Completer<void>();
          r.server.readsWait = wait.future;
          await tester.pumpWidget(_framed(r, c.open(r)));
          await _lookAt(tester, c);
          await tester.pump();
          await tester.pump();
          expect(find.textContaining(c.old), findsNothing);
          await _release(tester, wait);
          expect(find.textContaining(c.fresh), findsWidgets);
        },
      );
    });
  }

  group('what is kept belongs to one account', () {
    testWidgets(
      'after unpairing, the next account does not see the last one\'s copy',
      (tester) async {
        final c = _cases.first;
        final r = await _seen(tester, c);
        await tester.runAsync(() async {
          await r.controller.unpair();
          r.server.code = 'ZZZZ2345';
          r.server.tokenValid = true;
          await r.controller.pair('ZZZZ2345', 'Another phone');
        });
        c.serve(r, c.fresh);
        r.server.readsWait = Completer<void>().future;
        await tester.pumpWidget(_framed(r, c.open(r)));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining(c.old), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await tester.pump(const Duration(seconds: 20));
      },
    );
  });

  group('the screen\'s own reads', () {
    testWidgets('a slow earlier read never lands over a later one', (
      tester,
    ) async {
      final c = _cases.first; // Statistics: pulled down to read again
      final r = await _seen(tester, c);
      final first = Completer<void>();
      var asks = 0;
      r.server.extra = (req, path) async {
        if (path != '/stats') return null;
        final mine = ++asks;
        if (mine == 1) await first.future; // the screen's own read, slow
        return r.server.json(_statsBody(mine == 1 ? '4333' : '4222'));
      };
      await tester.pumpWidget(_framed(r, c.open(r)));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('4111'), findsWidgets);
      // the reader pulls down: a second, quick read starts and lands
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await _answered(tester);
      expect(find.textContaining('4222'), findsWidgets);
      // and now the first, slow one lands
      await _release(tester, first);
      expect(find.textContaining('4333'), findsNothing);
      expect(find.textContaining('4222'), findsWidgets);
    });

    testWidgets(
      'a screen asks the server once, not once for the copy and once more for the answer',
      (tester) async {
        final c = _cases.first;
        final r = await _seen(tester, c);
        c.serve(r, c.fresh);
        final before = r.server.requests.length;
        await tester.pumpWidget(_framed(r, c.open(r)));
        await _answered(tester);
        final asked = r.server.requests
            .skip(before)
            .where((q) => q.url.path.endsWith('/stats'))
            .length;
        expect(asked, 1);
      },
    );
  });

  group('a read that follows a change', () {
    testWidgets(
      'is never answered from the phone, even when the server cannot be reached',
      (tester) async {
        final c = _cases[1];
        final r = await _seen(tester, c);
        r.server.unreachable = true;
        Object? seen;
        await tester.runAsync(() async {
          try {
            await r.controller.withClient<Object?>(
              (client) => readLive(() => client.getJson('/tags')),
            );
          } on ApiException catch (e) {
            seen = e.failure;
          }
        });
        expect(seen, ApiFailure.network);
      },
    );

    testWidgets(
      'asked from the phone only, nothing reaches the server, not even a change',
      (tester) async {
        final r = await _seen(tester, _cases[1]);
        final before = r.server.requests.length;
        Object? seen;
        await tester.runAsync(() async {
          try {
            await r.controller.withClient<Object?>(
              (client) =>
                  readFromPhone(() => client.postJson('/tags', {'name': 'x'})),
            );
          } on ApiException catch (e) {
            seen = e.failure;
          }
        });
        expect(seen, ApiFailure.network);
        expect(r.server.requests.length, before);
      },
    );

    testWidgets(
      'is answered from the phone the ordinary way when nothing says it follows a change',
      (tester) async {
        final c = _cases[1];
        final r = await _seen(tester, c);
        r.server.unreachable = true;
        Object? got;
        await tester.runAsync(() async {
          got = await r.controller.withClient<Object?>(
            (client) => client.getJson('/tags'),
          );
        });
        expect('$got', contains(c.old));
      },
    );
  });
}
