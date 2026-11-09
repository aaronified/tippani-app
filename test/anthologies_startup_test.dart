import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';

void main() {
  testWidgets(
    'a phone that is paired is not told it is not, while it is still reading its pairing',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      final server = FakeServer();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      await tester.runAsync(() async {
        final first = AppController(store, clientFactory: server.factory);
        await first.load();
        await first.pair('ABCD2345', 'My phone');
      });
      // the app has just started: the token is stored but not read yet
      final controller = AppController(store, clientFactory: server.factory);
      await tester.pumpWidget(
        MaterialApp(
          home: AnthologiesScreen(
            service: ServerAnthologies(controller),
            controller: controller,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('not paired'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.runAsync(controller.load);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('not paired'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
