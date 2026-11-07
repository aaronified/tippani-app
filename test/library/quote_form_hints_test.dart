import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/quote_form_screen.dart';

import '../support/memory_library.dart';

void main() {
  testWidgets(
    'the form offers the work\'s characters, its chapters and the tags you have',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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

      // the cast and the speakers already used in this work
      expect(find.widgetWithText(ActionChip, 'Rick Blaine'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Ilsa Lund'), findsOneWidget);
      expect(
        find.widgetWithText(ActionChip, 'Captain Renault'),
        findsOneWidget,
      );
      // the chapters already used
      expect(find.widgetWithText(ActionChip, 'Act 3'), findsOneWidget);
      // the tags the library has
      expect(find.widgetWithText(ActionChip, 'love'), findsOneWidget);

      // pressing a name adds it to the box, and a second one after a comma
      await tester.tap(find.widgetWithText(ActionChip, 'Rick Blaine'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ActionChip, 'Ilsa Lund'));
      await tester.pump();
      final who = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Who said it'),
      );
      expect(who.controller!.text, 'Rick Blaine, Ilsa Lund');

      // a tag already in the box is no longer offered
      await tester.tap(find.widgetWithText(ActionChip, 'love'));
      await tester.pump();
      expect(find.widgetWithText(ActionChip, 'love'), findsNothing);
    },
  );
}
