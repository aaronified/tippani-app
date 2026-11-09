import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/quote_form_screen.dart';

import '../support/memory_library.dart';

Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'who said it suggests the work\'s characters and the speakers already used, and a second name follows a comma',
    (tester) async {
      bigScreen(tester);
      final lib = MemoryLibrary();
      final film = await lib.addWork(
        const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
      );
      await lib.setWorkDetails(
        film.id,
        const WorkDetails(
          cast: [
            CastMember(character: 'Rick Blaine', actor: 'Humphrey Bogart'),
            CastMember(character: 'Ilsa Lund', actor: 'Ingrid Bergman'),
          ],
        ),
      );
      await lib.addQuote(
        QuoteDraft(
          text: 'Here\'s looking at you.',
          workId: film.id,
          speaker: 'Captain Renault',
          chapter: 'Act 3',
          tags: const ['love'],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteFormScreen(store: lib, workId: film.id),
        ),
      );
      await tester.pumpAndSettle();

      await _type(tester, 'Who said it', 'ri');
      expect(find.widgetWithText(ListTile, 'Rick Blaine'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Rick Blaine'));
      await tester.pumpAndSettle();
      await _type(tester, 'Who said it', 'Rick Blaine, cap');
      expect(find.widgetWithText(ListTile, 'Captain Renault'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Captain Renault'));
      await tester.pumpAndSettle();
      final who = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Who said it'),
      );
      expect(who.controller!.text, 'Rick Blaine, Captain Renault');
    },
  );

  testWidgets('a work in a series offers the characters of the whole series', (
    tester,
  ) async {
    bigScreen(tester);
    final lib = MemoryLibrary();
    final chamber = await lib.addWork(
      const WorkDraft(title: 'Chamber of Secrets'),
    );
    final azkaban = await lib.addWork(
      const WorkDraft(title: 'Prisoner of Azkaban'),
    );
    final other = await lib.addWork(const WorkDraft(title: 'Dune'));
    await lib.setWorkDetails(
      chamber.id,
      const WorkDetails(
        series: 'Harry Potter',
        cast: [CastMember(character: 'Dobby')],
      ),
    );
    await lib.setWorkDetails(
      azkaban.id,
      const WorkDetails(
        series: 'harry potter',
        cast: [CastMember(character: 'Sirius Black')],
      ),
    );
    await lib.setWorkDetails(
      other.id,
      const WorkDetails(cast: [CastMember(character: 'Paul Atreides')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QuoteFormScreen(store: lib, workId: azkaban.id),
      ),
    );
    await tester.pumpAndSettle();

    await _type(tester, 'Who said it', 'do');
    expect(find.widgetWithText(ListTile, 'Dobby'), findsOneWidget);
    await _type(tester, 'Who said it', 'si');
    expect(find.widgetWithText(ListTile, 'Sirius Black'), findsOneWidget);
    // a character of another work stays out
    await _type(tester, 'Who said it', 'pa');
    expect(find.widgetWithText(ListTile, 'Paul Atreides'), findsNothing);
  });

  testWidgets(
    'the chapter is chosen by name or by number and keeps both, and tags suggest the library\'s tags',
    (tester) async {
      bigScreen(tester);
      final lib = MemoryLibrary();
      final w = await lib.addWork(const WorkDraft(title: 'Moby-Dick'));
      for (final c in [
        '10. The Carpet-Bag',
        '2. The Carpet-Bag Returns',
        '1. Loomings',
      ]) {
        await lib.addQuote(
          QuoteDraft(
            text: 'x $c',
            workId: w.id,
            chapter: c,
            tags: const ['sea'],
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteFormScreen(store: lib, workId: w.id),
        ),
      );
      await tester.pumpAndSettle();

      // by the name
      await _type(tester, 'Chapter', 'loom');
      expect(find.widgetWithText(ListTile, '1. Loomings'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '1. Loomings'));
      await tester.pumpAndSettle();
      var chapter = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Chapter'),
      );
      expect(chapter.controller!.text, '1. Loomings');
      // by the number, in chapter order
      await _type(tester, 'Chapter', '10');
      await tester.tap(find.widgetWithText(ListTile, '10. The Carpet-Bag'));
      await tester.pumpAndSettle();
      chapter = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Chapter'),
      );
      expect(chapter.controller!.text, '10. The Carpet-Bag');

      await _type(tester, 'Tags', 'se');
      expect(find.widgetWithText(ListTile, 'sea'), findsOneWidget);
    },
  );
}
