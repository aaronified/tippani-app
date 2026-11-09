import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/add_quote_sheet.dart';

import '../support/memory_library.dart';

void main() {
  late MemoryLibrary lib;
  var imported = 0;

  Future<void> open(WidgetTester tester, {bool withImport = true}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    lib = MemoryLibrary();
    await lib.addWork(const WorkDraft(title: 'Walden'));
    await lib.addWork(
      const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
    );
    imported = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAddQuoteSheet(
                  context,
                  store: lib,
                  onImport: withImport ? () => imported++ : null,
                ),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet offers every kind of quote the app and server keep', (
    tester,
  ) async {
    await open(tester);
    for (final t in [
      'A line from a book',
      'A line from a film, show or game',
      'A quote from anywhere',
      'Scan a page',
      'Speak it',
      'Import a file',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('without an import screen there is no Import a file', (
    tester,
  ) async {
    await open(tester, withImport: false);
    expect(find.text('Import a file'), findsNothing);
  });

  testWidgets(
    'a book line offers only books, a film line only films, shows and games',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('A line from a book'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int?>).first);
      await tester.pumpAndSettle();
      expect(find.text('Walden'), findsWidgets);
      expect(find.text('Casablanca'), findsNothing);
    },
  );

  testWidgets('a standalone quote has no work to choose', (tester) async {
    await open(tester);
    await tester.tap(find.text('A quote from anywhere'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int?>).first);
    await tester.pumpAndSettle();
    expect(find.text('Walden'), findsNothing);
    expect(find.text('Casablanca'), findsNothing);
  });

  testWidgets('Import a file hands over to the import screen', (tester) async {
    await open(tester);
    await tester.tap(find.text('Import a file'));
    await tester.pumpAndSettle();
    expect(imported, 1);
  });
}
