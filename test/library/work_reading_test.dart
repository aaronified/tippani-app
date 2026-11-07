import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/quote_text.dart';
import 'package:tippani/library/work_order.dart';
import 'package:tippani/screens/work_read_screen.dart';
import 'package:tippani/screens/work_screen.dart';

import 'dart:typed_data';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<PickedFile?> pick() async => null;
}

Quote q(
  int id,
  String text, {
  String chapter = '',
  String location = '',
  String translation = '',
  String note = '',
}) => Quote(
  id: id,
  workId: 1,
  text: text,
  translation: translation,
  language: '',
  speaker: '',
  chapter: chapter,
  location: location,
  note: note,
  color: 'yellow',
  favorite: false,
  notedAt: DateTime.utc(2026, 1, id),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

Work walden() => Work(
  id: 1,
  kind: WorkKind.book,
  title: 'Walden',
  creator: 'Thoreau',
  year: 1854,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('reading order', () {
    test('numbers count as numbers and case does not matter', () {
      expect(naturalCompare('p. 8', 'p. 10'), lessThan(0));
      expect(naturalCompare('Chapter 10', 'chapter 2'), greaterThan(0));
      expect(naturalCompare('a', 'a'), 0);
      expect(naturalCompare('a', 'a1'), lessThan(0));
    });

    test(
      'quotes sort by chapter, then place, then when met; no chapter goes last',
      () {
        final sorted = readingOrder([
          q(1, 'none'),
          q(2, 'b-10', chapter: 'Ch 10', location: 'p. 1'),
          q(3, 'b-2b', chapter: 'Ch 2', location: 'p. 20'),
          q(4, 'b-2a', chapter: 'Ch 2', location: 'p. 3'),
          q(6, 'tie-late', chapter: 'Ch 2', location: 'p. 3'),
        ]).map((e) => e.text).toList();
        expect(sorted, ['b-2a', 'tie-late', 'b-2b', 'b-10', 'none']);
      },
    );

    test('groups cut at each chapter change', () {
      final g = groupByChapter(
        readingOrder([
          q(1, 'a', chapter: 'One'),
          q(2, 'b', chapter: 'One'),
          q(3, 'c', chapter: 'Two'),
          q(4, 'd'),
        ]),
      );
      expect(g.map((e) => e.name), ['One', 'Two', '']);
      expect(g.map((e) => e.quotes.length), [2, 1, 1]);
    });
  });

  group('whole-work text', () {
    final quotes = readingOrder([
      q(
        1,
        'First',
        chapter: 'One',
        location: 'p. 1',
        translation: 'Pehla',
        note: 'mine',
      ),
      q(2, 'Second', chapter: 'Two'),
    ]);

    test(
      'headed by the work, chapters and quotes in order; notes only on request',
      () {
        expect(
          workShareText(walden(), quotes),
          'Walden — Thoreau\n\nOne\n\n“First” (p. 1)\nPehla\n\nTwo\n\n“Second”',
        );
        expect(
          workShareText(walden(), quotes, translations: false),
          isNot(contains('Pehla')),
        );
        expect(
          workShareText(walden(), quotes, notes: true),
          contains('Note: mine'),
        );
      },
    );
  });

  group('the screens', () {
    late MemoryLibrary lib;
    late Work work;
    final shared = <String>[];

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      shared.clear();
      lib = MemoryLibrary();
      work = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      await lib.addQuote(
        QuoteDraft(text: 'late one', workId: work.id, chapter: 'Ch 10'),
      );
      await lib.addQuote(
        QuoteDraft(
          text: 'early one',
          workId: work.id,
          chapter: 'Ch 2',
          favorite: true,
          translation: 'pehla',
          note: 'my note',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkScreen(
            store: lib,
            workId: work.id,
            picker: _Picker(),
            share: (t, s) async => shared.add(t),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder heading(String t) => find.byWidgetPredicate(
      (w) => w is Text && w.data == t && w.style?.fontSize == 16,
    );

    testWidgets('the header counts quotes, chapters and favourites', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('2 quotes · 2 chapters · 1 favourite'), findsOneWidget);
    });

    testWidgets('quotes show under chapter headings in reading order', (
      tester,
    ) async {
      await open(tester);
      expect(heading('Ch 2'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('early one')).dy,
        lessThan(tester.getTopLeft(find.text('late one')).dy),
      );
    });

    testWidgets('choosing no grouping drops the headings', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('work-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No grouping').last);
      await tester.pumpAndSettle();
      expect(heading('Ch 2'), findsNothing);
    });

    testWidgets('the favourites chip hides the rest', (tester) async {
      await open(tester);
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('early one'), findsOneWidget);
      expect(find.text('late one'), findsNothing);
    });

    testWidgets(
      'Read opens the document with translations on and notes off; the toggles work; share all sends the text',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        expect(find.byType(WorkReadScreen), findsOneWidget);
        expect(find.text('pehla'), findsOneWidget);
        expect(find.text('my note'), findsNothing);
        await tester.tap(find.text('My notes'));
        await tester.pumpAndSettle();
        expect(find.text('my note'), findsOneWidget);
        await tester.tap(find.text('Translations'));
        await tester.pumpAndSettle();
        expect(find.text('pehla'), findsNothing);
        await tester.tap(find.byTooltip('Share all'));
        await tester.pumpAndSettle();
        expect(shared.single, startsWith('Walden — Thoreau'));
        expect(shared.single, contains('Note: my note'));
        expect(shared.single, isNot(contains('pehla')));
      },
    );

    testWidgets('the text size slider changes the size of the words', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      double size() => tester
          .widget<SelectableText>(
            find.ancestor(
              of: find.text('“early one”'),
              matching: find.byType(SelectableText),
            ),
          )
          .style!
          .fontSize!;
      expect(size(), 18);
      await tester.drag(find.byType(Slider), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(size(), greaterThan(18));
    });
  });
}
