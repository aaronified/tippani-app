import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_checks.dart';
import '../support/fake_server.dart';
import '../support/memory_library.dart';

Future<void> _open(
  WidgetTester tester, {
  FakeImports? imports,
  FakeChecks? checks,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store, clientFactory: FakeServer().factory);
  await c.load();
  await c.pair('ABCD2345', 'My phone');
  await tester.pumpWidget(
    TippaniApp(
      controller: c,
      harness: Harness.fake(
        store,
        controller: c,
        library: MemoryLibrary(),
        imports: imports,
        checks: checks,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings has Import and checks, badged with what waits', (
    tester,
  ) async {
    final imports = FakeImports()
      ..staging = const Staging(
        pending: 5,
        total: 5,
        batches: [],
        works: [],
        quotes: [],
      );
    await _open(tester, imports: imports, checks: FakeChecks());

    expect(find.text('Import and checks'), findsOneWidget);
    expect(
      find.text('5 imported quotes wait for your approval'),
      findsOneWidget,
    );
    expect(find.widgetWithText(Badge, '5'), findsOneWidget);
  });

  testWidgets(
    'it opens the screen, with a Markdown import that needs no server',
    (tester) async {
      await _open(tester);
      await tester.ensureVisible(find.text('Import and checks'));
      await tester.tap(find.text('Import and checks'));
      await tester.pumpAndSettle();
      expect(find.text('Import Markdown into this phone'), findsOneWidget);
    },
  );
}
