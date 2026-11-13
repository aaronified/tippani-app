import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/pairing/pairing_code.dart';
import 'package:tippani/pairing/pairing_service.dart';
import 'package:tippani/screens/pair_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';

class Rig {
  Rig(this.server, this.store, this.vault, this.controller, this.log);
  final FakeServer server;
  final SettingsStore store;
  final MemoryTokenVault vault;
  final AppController controller;
  final AppLog log;
}

Future<Rig> rig(
  FakeServer server, {
  Map<String, Object> saved = const {'server_url': 'https://q.example.org'},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final vault = MemoryTokenVault();
  final store = SettingsStore(await SharedPreferences.getInstance(), vault);
  final log = AppLog();
  final controller = AppController(
    store,
    clientFactory: server.factory,
    log: log,
  );
  return Rig(server, store, vault, controller, log);
}

Future<void> open(WidgetTester tester, Rig r) async {
  await tester.pumpWidget(
    TippaniApp(
      controller: r.controller,
      harness: Harness.fake(r.store, controller: r.controller, log: r.log),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('normalisePairingCode', () {
    test('accepts the code as the server shows it', () {
      expect(normalisePairingCode('ABCD2345'), 'ABCD2345');
    });

    test('ignores case, spaces and dashes, since a code is read out or copied in groups', () {
      expect(normalisePairingCode('abcd 2345'), 'ABCD2345');
      expect(normalisePairingCode(' ab-cd-23-45 '), 'ABCD2345');
    });

    test(
      'reads the letters a reader confuses the way the server alphabet does',
      () {
        expect(normalisePairingCode('ABCDO345'), 'ABCD0345', reason: 'O is 0');
        expect(normalisePairingCode('ABCDI345'), 'ABCD1345', reason: 'I is 1');
        expect(normalisePairingCode('ABCDL345'), 'ABCD1345', reason: 'L is 1');
      },
    );

    test('refuses what cannot be a code', () {
      expect(normalisePairingCode(''), isNull);
      expect(normalisePairingCode('ABC'), isNull);
      expect(normalisePairingCode('ABCD23456'), isNull);
      expect(normalisePairingCode('ABCD234!'), isNull);
      expect(
        normalisePairingCode('ABCDU345'),
        isNull,
        reason: 'U is not in the alphabet',
      );
    });
  });

  group('PairingService', () {
    test('a good code stores the token in the vault and the name in preferences, and logs neither', () async {
      final s = FakeServer();
      final r = await rig(s);
      final result = await PairingService(
        r.store,
        clientFactory: s.factory,
        log: r.log,
      ).claim('https://q.example.org', 'ABCD2345', 'Pixel');
      expect(result.ok, isTrue);
      expect(result.username, 'alice');
      expect(await r.vault.read(), 'tok-1234');
      expect(r.store.username, 'alice');
      expect(r.log.text(), contains('paired as alice'));
      expect(r.log.text(), isNot(contains('tok-1234')));
      expect(r.log.text(), isNot(contains('ABCD2345')));
    });

    test(
      'the claim carries no credential, and sends the code and the name',
      () async {
        final s = FakeServer();
        final r = await rig(s);
        await PairingService(
          r.store,
          clientFactory: s.factory,
        ).claim('https://q.example.org', 'ABCD2345', '  Pixel  ');
        final req = s.requests.single;
        expect(
          req.url.toString(),
          'https://q.example.org/api/auth/devices/claim',
        );
        expect(req.headers.containsKey('Authorization'), isFalse);
        expect(req.body, '{"code":"ABCD2345","name":"Pixel"}');
      },
    );

    test(
      'a wrong, expired or spent code is invalid, and nothing is stored',
      () async {
        final s = FakeServer();
        final r = await rig(s);
        final svc = PairingService(r.store, clientFactory: s.factory);
        expect(
          (await svc.claim('https://q.example.org', 'ZZZZ2345', 'P')).failure,
          PairFailure.invalidCode,
        );
        expect(
          await svc
              .claim('https://q.example.org', 'ABCD2345', 'P')
              .then((x) => x.ok),
          isTrue,
        );
        expect(
          (await svc.claim('https://q.example.org', 'ABCD2345', 'P')).failure,
          PairFailure.invalidCode,
          reason: 'one shot',
        );
      },
    );

    test(
      'rate limiting, no network and a strange answer are told apart',
      () async {
        final s = FakeServer()..rateLimit = true;
        final r = await rig(s);
        expect(
          (await PairingService(
            r.store,
            clientFactory: s.factory,
          ).claim('https://q.example.org', 'ABCD2345', 'P')).failure,
          PairFailure.rateLimited,
        );
        ApiClient down(Uri b, String? t) =>
            throw const ApiException(ApiFailure.network, 'x');
        expect(
          (await PairingService(
            r.store,
            clientFactory: (b, t) => _Throwing(b, ApiFailure.network),
          ).claim('https://q.example.org', 'ABCD2345', 'P')).failure,
          PairFailure.unreachable,
        );
        expect(
          (await PairingService(
            r.store,
            clientFactory: (b, t) => _Throwing(b, ApiFailure.badResponse),
          ).claim('https://q.example.org', 'ABCD2345', 'P')).failure,
          PairFailure.unexpected,
        );
        expect(down, isNotNull);
        expect(await r.vault.read(), isNull);
      },
    );
  });

  group('AppController pairing', () {
    test(
      'pairing makes the phone paired, and asks who it is paired as',
      () async {
        final s = FakeServer(admin: true);
        final r = await rig(s);
        expect(r.controller.paired, isFalse);
        final result = await r.controller.pair('ABCD2345', 'My Android phone');
        expect(result.ok, isTrue);
        expect(r.controller.paired, isTrue);
        expect(r.controller.username, 'alice');
        expect(r.controller.isAdmin, isTrue);
        expect(s.paths, contains('GET /auth/me'));
      },
    );

    test('a phone paired as a non-admin is not an admin', () async {
      final r = await rig(FakeServer(admin: false));
      await r.controller.pair('ABCD2345', 'P');
      expect(r.controller.isAdmin, isFalse);
    });

    test('a stored token is picked up when the app opens', () async {
      final s = FakeServer(admin: true);
      final r = await rig(
        s,
        saved: {'server_url': 'https://q.example.org', 'paired_user': 'alice'},
      );
      await r.vault.write('tok-1234');
      await r.controller.load();
      expect(r.controller.paired, isTrue);
      expect(r.controller.isAdmin, isTrue);
    });

    test('an admin phone that starts with no server still shows the administration, and forgets it when unpaired', () async {
      final s = FakeServer(admin: true);
      final r = await rig(
        s,
        saved: {
          'server_url': 'https://q.example.org',
          'paired_user': 'alice',
          'paired_admin': 'yes',
        },
      );
      await r.vault.write('tok-1234');
      s.unreachable = true;
      await r.controller.load();
      expect(r.controller.paired, isTrue);
      expect(r.controller.isAdmin, isTrue);

      s.unreachable = false;
      await r.controller.unpair();
      final kept = await SharedPreferences.getInstance();
      expect(
        kept.getString('paired_admin'),
        isNull,
        reason: 'the flag is forgotten, not just hidden',
      );
      await r.controller.load();
      expect(r.controller.isAdmin, isFalse);
    });

    test('what the server last said is forgotten when the phone is unpaired, the server forgotten or the token refused', () async {
      final s = FakeServer(admin: true);
      final r = await rig(s);
      await r.controller.pair('ABCD2345', 'My phone');
      expect(r.controller.authedClient()!.offline, same(r.controller.offline));

      await r.controller.offline.write('/tags', '{"tags":[]}');
      await r.controller.unpair();
      expect(r.controller.offline.read('/tags'), isNull, reason: 'unpaired');

      await r.controller.offline.write('/tags', '{"tags":[]}');
      await r.controller.forget();
      expect(
        r.controller.offline.read('/tags'),
        isNull,
        reason: 'server forgotten',
      );
    });

    test('what the server last said is forgotten when the server refuses the token', () async {
      final s = FakeServer(admin: true);
      final r = await rig(s);
      await r.controller.pair('ABCD2345', 'My phone');
      await r.controller.offline.write('/tags', '{"tags":[]}');
      s.extra = (req, path) async => s.json({'error': 'no'}, 401);
      await expectLater(
        r.controller.withClient((c) => c.getJson('/books')),
        throwsA(isA<ApiException>()),
      );
      expect(r.controller.paired, isFalse);
      expect(r.controller.offline.read('/tags'), isNull);
    });

    test('unpairing asks the server to forget this phone (the row marked current), and keeps the server address', () async {
      final s = FakeServer();
      final r = await rig(s);
      await r.controller.pair('ABCD2345', 'My Android phone');
      await r.controller.unpair();
      expect(
        s.paths,
        contains('DELETE /auth/devices/3'),
        reason: 'the row the server marked current',
      );
      expect(
        s.devices.where((d) => d['id'] == 1),
        isNotEmpty,
        reason: 'other devices untouched',
      );
      expect(r.controller.paired, isFalse);
      expect(await r.vault.read(), isNull);
      expect(r.controller.serverUrl, 'https://q.example.org');
    });

    test(
      'unpairing still happens here when the server cannot be reached',
      () async {
        final s = FakeServer();
        final r = await rig(s);
        await r.controller.pair('ABCD2345', 'My Android phone');
        s.tokenValid = false;
        await r.controller.unpair();
        expect(r.controller.paired, isFalse);
        expect(await r.vault.read(), isNull);
      },
    );

    test('a token the server refuses (unpaired from the web) unpairs the phone here and says so', () async {
      final s = FakeServer();
      final r = await rig(s);
      await r.controller.pair('ABCD2345', 'My Android phone');
      s.tokenValid = false;
      await expectLater(r.controller.devices(), throwsA(isA<ApiException>()));
      expect(r.controller.paired, isFalse);
      expect(r.controller.revoked, isTrue);
      expect(await r.vault.read(), isNull);
    });

    test(
      'a 403 (not an admin) is NOT a refused token and leaves the phone paired',
      () async {
        final s = FakeServer(admin: false);
        final r = await rig(s);
        await r.controller.pair('ABCD2345', 'My Android phone');
        await expectLater(
          r.controller.withClient((c) => c.getJson('/admin/logs')),
          throwsA(isA<ApiException>()),
        );
        expect(r.controller.paired, isTrue);
        expect(r.controller.revoked, isFalse);
      },
    );

    test('forgetting the server forgets the pairing with it', () async {
      final r = await rig(FakeServer());
      await r.controller.pair('ABCD2345', 'P');
      await r.controller.forget();
      expect(r.controller.paired, isFalse);
      expect(r.store.username, isNull);
      expect(await r.vault.read(), isNull);
    });
  });

  group('the screens', () {
    testWidgets(
      'Home offers to pair once a server is set, and the pair screen pairs with a typed code',
      (tester) async {
        final r = await rig(FakeServer());
        await open(tester, r);
        expect(find.text('Pair this phone'), findsOneWidget);
        await tester.tap(find.text('Pair this phone'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Pairing code'),
          'abcd-2345',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
        await tester.pumpAndSettle();
        expect(r.controller.paired, isTrue);
        expect(find.text('Paired as alice.'), findsOneWidget);
        expect(find.text('Pair this phone'), findsNothing);
      },
    );

    testWidgets(
      'a code that is not a code is refused without asking the server',
      (tester) async {
        final s = FakeServer();
        final r = await rig(s);
        await open(tester, r);
        await tester.tap(find.text('Pair this phone'));
        await tester.pumpAndSettle();
        final before = s.requests.length;
        await tester.enterText(
          find.widgetWithText(TextField, 'Pairing code'),
          'nope',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
        await tester.pumpAndSettle();
        expect(s.requests.length, before);
        expect(find.textContaining('letters and numbers'), findsOneWidget);
      },
    );

    testWidgets('a wrong code says so in words and stays on the screen', (
      tester,
    ) async {
      final r = await rig(FakeServer());
      await open(tester, r);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Pairing code'),
        'ZZZZ2345',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pumpAndSettle();
      expect(
        find.text(pairFailureText(PairFailure.invalidCode)),
        findsOneWidget,
      );
      expect(r.controller.paired, isFalse);
    });

    testWidgets(
      'Settings lists the devices with this phone marked and no Unpair on it, and unpairs another after asking',
      (tester) async {
        final s = FakeServer();
        final r = await rig(s);
        await r.controller.pair('ABCD2345', 'My Android phone');
        await open(tester, r);
        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paired devices'));
        await tester.pumpAndSettle();
        expect(find.text('Old tablet'), findsOneWidget);
        expect(find.text('This phone'), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Unpair'),
          findsNWidgets(2),
          reason:
              'the tablet and the third, newly claimed device; not this phone',
        );

        await tester.tap(find.widgetWithText(TextButton, 'Unpair').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          s.paths.where((p) => p.startsWith('DELETE')),
          isEmpty,
          reason: 'Cancel unpairs nothing',
        );

        await tester.tap(find.widgetWithText(TextButton, 'Unpair').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Unpair'));
        await tester.pumpAndSettle();
        expect(s.paths.where((p) => p.startsWith('DELETE')), hasLength(1));
      },
    );

    testWidgets(
      'Unpair every device asks first, signs out every device of the account and unpairs this phone too',
      (tester) async {
        final s = FakeServer();
        final r = await rig(s);
        await r.controller.pair('ABCD2345', 'My Android phone');
        await open(tester, r);
        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paired devices'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Unpair every device'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          s.paths.where((p) => p.contains('revoke-all')),
          isEmpty,
          reason: 'Cancel signs nobody out',
        );
        expect(r.controller.paired, isTrue);

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Unpair every device'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Unpair every device'),
        );
        await tester.pumpAndSettle();
        expect(s.paths.where((p) => p.contains('revoke-all')), hasLength(1));
        expect(
          r.controller.paired,
          isFalse,
          reason: 'this phone was one of them',
        );
        expect(
          r.controller.revoked,
          isFalse,
          reason: 'the reader did this on purpose: no unpaired-from-the-server alert',
        );
      },
    );

    testWidgets(
      'on a server too old to mark the current device, the list says so',
      (tester) async {
        final s = FakeServer(revision: 8);
        final r = await rig(s);
        await r.controller.pair('ABCD2345', 'My Android phone');
        await open(tester, r);
        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paired devices'));
        await tester.pumpAndSettle();
        expect(find.textContaining('too old to say which'), findsOneWidget);
      },
    );

    testWidgets('a phone unpaired from the web is told so on Home', (
      tester,
    ) async {
      final s = FakeServer();
      final r = await rig(s);
      await r.controller.pair('ABCD2345', 'My Android phone');
      s.tokenValid = false;
      await expectLater(r.controller.devices(), throwsA(isA<ApiException>()));
      await open(tester, r);
      expect(
        find.textContaining('was unpaired from the server'),
        findsOneWidget,
      );
      expect(find.text('Pair this phone'), findsOneWidget);
    });

    testWidgets('Settings: Unpair this phone asks first', (tester) async {
      final r = await rig(FakeServer());
      await r.controller.pair('ABCD2345', 'My Android phone');
      await open(tester, r);
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpair this phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(r.controller.paired, isTrue);
      await tester.tap(find.text('Unpair this phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Unpair'));
      await tester.pumpAndSettle();
      expect(r.controller.paired, isFalse);
    });
  });

  test('every pairing failure has a sentence', () {
    for (final f in PairFailure.values) {
      expect(pairFailureText(f), isNotEmpty);
    }
  });
}

class _Throwing extends ApiClient {
  _Throwing(Uri base, this.failure) : super(base: base);
  final ApiFailure failure;

  @override
  Future<Object?> postJson(
    String path,
    Map<String, Object?> body, {
    String? idempotencyKey,
  }) async => failure == ApiFailure.badResponse
      ? <String, Object?>{'token': 5}
      : throw ApiException(failure, 'x');
}
