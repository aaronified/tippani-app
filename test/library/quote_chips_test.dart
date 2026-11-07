import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/quote_chips.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/quote_chips_row.dart';

import '../support/memory_library.dart';

Quote quote({String speaker = '', int? workId}) => Quote(
  id: 1,
  workId: workId,
  text: 'Here\'s looking at you, kid.',
  translation: '',
  language: '',
  speaker: speaker,
  chapter: '',
  location: '',
  note: '',
  color: 'yellow',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

Work work(
  WorkKind kind, {
  String creator = '',
  List<CastMember> cast = const [],
}) => Work(
  id: 1,
  kind: kind,
  title: 'Casablanca',
  creator: creator,
  year: 1942,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  details: WorkDetails(cast: cast),
);

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

void main() {
  group('who is named', () {
    test('one name, or an ensemble in the order typed, each once', () {
      expect(speakerNames('Rick'), ['Rick']);
      expect(speakerNames('Rick, Ilsa and Victor'), ['Rick', 'Ilsa', 'Victor']);
      expect(speakerNames('Rick & Ilsa; Sam / rick'), ['Rick', 'Ilsa', 'Sam']);
      expect(speakerNames('  '), isEmpty);
      expect(speakerNames('Brandon Sanderson'), ['Brandon Sanderson']);
    });
  });

  group('the chips for a quote', () {
    test('a book: its author, then who said it', () {
      final c = chipsFor(
        quote(speaker: 'Ishmael'),
        work(WorkKind.book, creator: 'Melville'),
      );
      expect(c, const [
        QuoteChip(ChipKind.author, 'Melville'),
        QuoteChip(ChipKind.speaker, 'Ishmael'),
      ]);
    });

    test('a film: the character carries the actor the cast gives', () {
      final c = chipsFor(
        quote(speaker: 'rick blaine'),
        work(
          WorkKind.film,
          creator: 'Michael Curtiz',
          cast: const [
            CastMember(character: 'Rick Blaine', actor: 'Humphrey Bogart'),
          ],
        ),
      );
      expect(c, const [
        QuoteChip(ChipKind.character, 'rick blaine', 'Humphrey Bogart'),
      ]);
    });

    test('a film has no author chip (its creator is a director)', () {
      expect(
        chipsFor(quote(), work(WorkKind.film, creator: 'Michael Curtiz')),
        isEmpty,
      );
    });

    test('a character the cast does not list has no actor', () {
      final c = chipsFor(
        quote(speaker: 'Sam'),
        work(
          WorkKind.show,
          cast: const [CastMember(character: 'Rick', actor: 'B')],
        ),
      );
      expect(c.single.actor, '');
      expect(c.single.kind, ChipKind.character);
    });

    test('an ensemble gets a chip each, with their own actors', () {
      final c = chipsFor(
        quote(speaker: 'Rick, Ilsa'),
        work(
          WorkKind.film,
          cast: const [
            CastMember(character: 'Rick', actor: 'Humphrey Bogart'),
            CastMember(character: 'Ilsa', actor: 'Ingrid Bergman'),
          ],
        ),
      );
      expect(c.map((x) => x.actor), ['Humphrey Bogart', 'Ingrid Bergman']);
    });

    test('a standalone quote has its speaker as a person, and no author', () {
      expect(chipsFor(quote(speaker: 'Lincoln'), null), const [
        QuoteChip(ChipKind.speaker, 'Lincoln'),
      ]);
    });

    test('a book with no author and a quote with no speaker have none', () {
      expect(chipsFor(quote(), work(WorkKind.book)), isEmpty);
      expect(chipsFor(quote(), null), isEmpty);
    });
  });

  group('the chips on screen', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets(
      'each is a button showing the name, and a character shows the actor under it',
      (tester) async {
        ChipFilter? got;
        await tester.pumpWidget(
          host(
            QuoteChipsRow(
              quote: quote(speaker: 'Rick'),
              work: work(
                WorkKind.film,
                cast: const [
                  CastMember(character: 'Rick', actor: 'Humphrey Bogart'),
                ],
              ),
              onTap: (f) => got = f,
            ),
          ),
        );
        expect(find.text('Rick'), findsOneWidget);
        expect(find.text('Humphrey Bogart'), findsOneWidget);
        expect(find.text('R'), findsOneWidget);
        await tester.tap(find.text('Rick'));
        expect(got!.name, 'Rick');
      },
    );

    testWidgets(
      'a book shows the author and the speaker, and nothing for a quote with no one',
      (tester) async {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                QuoteChipsRow(
                  quote: quote(speaker: 'Ishmael'),
                  work: work(WorkKind.book, creator: 'Herman Melville'),
                  onTap: (_) {},
                ),
                QuoteChipsRow(quote: quote(), work: null, onTap: (_) {}),
              ],
            ),
          ),
        );
        expect(find.text('Herman Melville'), findsOneWidget);
        expect(find.text('Ishmael'), findsOneWidget);
        expect(find.byType(PersonChip), findsNWidgets(2));
      },
    );

    testWidgets('a long name is cut with an ellipsis, not wrapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuoteChipsRow(
            quote: quote(speaker: 'A Very Long Name Indeed ' * 6),
            work: null,
            onTap: (_) {},
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text).last);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('in the library', () {
    late MemoryLibrary lib;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      final book = await lib.addWork(
        const WorkDraft(title: 'Moby-Dick', creator: 'Herman Melville'),
      );
      await lib.addQuote(
        QuoteDraft(
          text: 'Call me Ishmael.',
          workId: book.id,
          speaker: 'Ishmael',
        ),
      );
      final other = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Henry Thoreau'),
      );
      await lib.addQuote(QuoteDraft(text: 'Simplify.', workId: other.id));
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(store: lib, picker: _Picker()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a quote in the list shows its people as chips, and no second copy of the speaker in the text line',
      (tester) async {
        await open(tester);
        expect(
          find.widgetWithText(PersonChip, 'Herman Melville'),
          findsOneWidget,
        );
        expect(find.widgetWithText(PersonChip, 'Ishmael'), findsOneWidget);
        expect(find.text('Ishmael · Moby-Dick'), findsNothing);
      },
    );

    testWidgets('pressing a chip shows the library for that name', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Simplify.'), findsOneWidget);
      await tester.tap(find.widgetWithText(PersonChip, 'Herman Melville'));
      await tester.pumpAndSettle();
      expect(find.text('Call me Ishmael.'), findsOneWidget);
      expect(find.text('Simplify.'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Herman Melville',
      );
    });

    testWidgets(
      'a chip pressed on the quote screen brings the library back filtered by it',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Call me Ishmael.'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PersonChip, 'Ishmael'));
        await tester.pumpAndSettle();
        expect(find.text('Call me Ishmael.'), findsOneWidget);
        expect(find.text('Simplify.'), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Ishmael',
        );
      },
    );
  });
}
