import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/settings/settings_store.dart';

late SettingsStore _store;

Future<AppController> controllerAnswering(
  MockClientHandler handler, {
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final store = _store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  return AppController(
    store,
    clientFactory: (base, token) =>
        ApiClient(base: base, token: token, client: MockClient(handler)),
  );
}

http.Response caps({int revision = 8, int minClient = 1}) => http.Response(
  '{"version":"3.6.2","api_revision":$revision,"min_client_revision":$minClient,"features":[]}',
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> start(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(
    TippaniApp(
      controller: c,
      harness: Harness.fake(_store, controller: c),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openConnect(WidgetTester tester) async {
  await tester.tap(find.text('Connect to your server'));
  await tester.pumpAndSettle();
}

Future<void> enterAndCheck(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextField), address);
  await tester.tap(find.text('Check and connect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no server it offers to connect', (tester) async {
    final c = await controllerAnswering((r) async => caps());
    await start(tester, c);
    expect(find.text('Not connected to a server yet.'), findsOneWidget);
    expect(find.text('Connect to your server'), findsOneWidget);
  });

  testWidgets(
    'a usable server is kept, and Home says connected with its version',
    (tester) async {
      late Uri asked;
      final c = await controllerAnswering((r) async {
        asked = r.url;
        return caps();
      });
      await start(tester, c);
      await openConnect(tester);
      await enterAndCheck(tester, '192.168.1.20:8124');
      expect(asked.toString(), 'https://192.168.1.20:8124/api/capabilities');
      expect(c.serverUrl, 'https://192.168.1.20:8124');
      expect(find.text('Connected (version 3.6.2).'), findsOneWidget);
    },
  );

  testWidgets('an unreachable server is not kept and says why', (tester) async {
    final c = await controllerAnswering(
      (r) async => throw http.ClientException('no route'),
    );
    await start(tester, c);
    await openConnect(tester);
    await enterAndCheck(tester, 'nas.local:8124');
    expect(c.serverUrl, isNull);
    expect(find.textContaining('Could not reach that address'), findsOneWidget);
  });

  testWidgets(
    'a server too new for this app is not kept and says to update the app',
    (tester) async {
      final c = await controllerAnswering(
        (r) async => caps(revision: 30, minClient: 20),
      );
      await start(tester, c);
      await openConnect(tester);
      await enterAndCheck(tester, 'nas.local');
      expect(c.serverUrl, isNull);
      expect(find.textContaining('Update the app'), findsOneWidget);
    },
  );

  testWidgets('something that is not Tippani is not kept', (tester) async {
    final c = await controllerAnswering(
      (r) async => http.Response('<html>router login</html>', 200),
    );
    await start(tester, c);
    await openConnect(tester);
    await enterAndCheck(tester, 'router.local');
    expect(c.serverUrl, isNull);
    expect(find.textContaining('not a Tippani server'), findsOneWidget);
  });

  testWidgets(
    'an address that is not an address is refused without asking anyone',
    (tester) async {
      var asked = false;
      final c = await controllerAnswering((r) async {
        asked = true;
        return caps();
      });
      await start(tester, c);
      await openConnect(tester);
      await enterAndCheck(tester, 'ftp://nope');
      expect(asked, isFalse);
      expect(find.textContaining('not an address'), findsOneWidget);
    },
  );

  testWidgets('plain http on the open internet is kept but warned about', (
    tester,
  ) async {
    final c = await controllerAnswering((r) async => caps());
    await start(tester, c);
    await openConnect(tester);
    await enterAndCheck(tester, 'http://203.0.113.9:8124');
    expect(c.serverUrl, 'http://203.0.113.9:8124');
    expect(find.textContaining('plain http'), findsOneWidget);
  });

  testWidgets('Settings forgets the server only after a confirmation', (
    tester,
  ) async {
    final c = await controllerAnswering(
      (r) async => caps(),
      saved: {'server_url': 'https://q.example.org'},
    );
    await start(tester, c);
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget this server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.serverUrl, 'https://q.example.org', reason: 'Cancel keeps it');
    await tester.tap(find.text('Forget this server'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();
    expect(c.serverUrl, isNull);
  });
}
