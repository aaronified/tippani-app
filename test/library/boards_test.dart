import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/boards_screen.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/quote_form_screen.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('boards in the real store', () {
    late SqliteLibraryStore store;

    setUp(() async {
      store = await SqliteLibraryStore.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
    });
    tearDown(() => store.close());

    test('a board is made with a name and a colour, and listed by name with its count', () async {
      await store.addBoard('Proverbs', color: 'green');
      await store.addBoard('Speeches');
      final b = await store.boards();
      expect(b.map((x) => x.name), ['Proverbs', 'Speeches']);
      expect(b.first.color, 'green');
      expect(b.last.color, '');
      expect(b.first.quotes, 0);
    });

    test(
      'a name is needed, and may not be used twice, in any letter case',
      () async {
        await store.addBoard('Proverbs');
        await expectLater(
          store.addBoard('  '),
          throwsA(isA<LibraryException>()),
        );
        await expectLater(
          store.addBoard('proverbs'),
          throwsA(isA<LibraryException>()),
        );
        final other = await store.addBoard('Speeches');
        await expectLater(
          store.renameBoard(other.id, 'PROVERBS'),
          throwsA(isA<LibraryException>()),
        );
      },
    );

    test('renaming and recolouring change only that board', () async {
      final a = await store.addBoard('A');
      await store.addBoard('B');
      await store.renameBoard(a.id, 'Alpha');
      await store.recolourBoard(a.id, 'pink');
      final b = await store.boards();
      expect(b.map((x) => x.name), ['Alpha', 'B']);
      expect(b.first.color, 'pink');
      await store.recolourBoard(a.id, 'not a colour');
      expect((await store.boards()).first.color, '');
    });

    test(
      'a standalone quote is filed on a board; a quote from a work never is',
      () async {
        final board = await store.addBoard('Proverbs');
        final w = await store.addWork(const WorkDraft(title: 'Walden'));
        final loose = await store.addQuote(
          QuoteDraft(text: 'A stitch in time.', boardId: board.id),
        );
        final fromWork = await store.addQuote(
          QuoteDraft(text: 'Simplify.', workId: w.id, boardId: board.id),
        );
        expect(loose.boardId, board.id);
        expect(fromWork.boardId, isNull);
        expect((await store.boards()).single.quotes, 1);
      },
    );

    test('quotes can be asked for by board, or those on none', () async {
      final a = await store.addBoard('A');
      final b = await store.addBoard('B');
      await store.addQuote(QuoteDraft(text: 'one', boardId: a.id));
      await store.addQuote(QuoteDraft(text: 'two', boardId: b.id));
      await store.addQuote(const QuoteDraft(text: 'three'));
      expect((await store.quotes(boardId: a.id)).map((q) => q.text), ['one']);
      expect((await store.quotes(unfiled: true)).map((q) => q.text), ['three']);
      expect(await store.quotes(), hasLength(3));
    });

    test('deleting a board keeps its quotes, on no board', () async {
      final a = await store.addBoard('A');
      final q = await store.addQuote(QuoteDraft(text: 'one', boardId: a.id));
      await store.deleteBoard(a.id);
      expect(await store.boards(), isEmpty);
      expect((await store.quote(q.id))!.boardId, isNull);
    });

    test(
      'an edit keeps the board; moving a quote onto a work takes it off',
      () async {
        final a = await store.addBoard('A');
        final w = await store.addWork(const WorkDraft(title: 'Walden'));
        final q = await store.addQuote(QuoteDraft(text: 'one', boardId: a.id));
        await store.updateQuote(q.id, QuoteDraft(text: 'one!', boardId: a.id));
        expect((await store.quote(q.id))!.boardId, a.id);
        await store.updateQuote(
          q.id,
          QuoteDraft(text: 'one!', workId: w.id, boardId: a.id),
        );
        expect((await store.quote(q.id))!.boardId, isNull);
      },
    );

    test('boards and what is on them go into a backup and come back', () async {
      final a = await store.addBoard('A', color: 'blue');
      await store.addQuote(QuoteDraft(text: 'one', boardId: a.id));
      await store.addQuote(const QuoteDraft(text: 'two'));
      final data = await store.exportAll();
      await store.deleteBoard(a.id);
      await store.replaceAll(data);
      final b = (await store.boards()).single;
      expect([b.name, b.color, b.quotes], ['A', 'blue', 1]);
    });

    test('a backup made before boards existed still restores', () async {
      await store.addQuote(const QuoteDraft(text: 'one'));
      final data = Map<String, Object?>.from(await store.exportAll())
        ..remove('boards');
      await store.replaceAll(data);
      expect(await store.boards(), isEmpty);
      expect(await store.quotes(), hasLength(1));
    });
  });

  group('the Boards screen', () {
    late MemoryLibrary lib;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: BoardsScreen(store: lib)));
      await tester.pumpAndSettle();
    }

    testWidgets('says what a board is when there are none', (tester) async {
      await open(tester);
      expect(find.textContaining('A board is a shelf'), findsOneWidget);
    });

    testWidgets('makes a board; Save needs a name', (tester) async {
      await open(tester);
      await tester.tap(find.text('New board'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Proverbs');
      await tester.pump();
      await tester.tap(find.byTooltip('green'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Proverbs'), findsOneWidget);
      expect((await lib.boards()).single.color, 'green');
    });

    testWidgets('a name already used is said, not thrown', (tester) async {
      await open(tester);
      await lib.addBoard('Proverbs');
      await tester.tap(find.text('New board'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'proverbs');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('a board is renamed from its menu', (tester) async {
      await open(tester);
      await lib.addBoard('Old');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: BoardsScreen(store: lib)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More for Old'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await lib.boards()).single.name, 'New');
    });

    testWidgets('deleting asks first and says the quotes stay', (tester) async {
      await open(tester);
      final b = await lib.addBoard('A');
      await lib.addQuote(QuoteDraft(text: 'one', boardId: b.id));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: BoardsScreen(store: lib)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More for A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 quote stays'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(await lib.boards(), hasLength(1));
      await tester.tap(find.byTooltip('More for A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(await lib.boards(), isEmpty);
      expect((await lib.quotes()).single.boardId, isNull);
    });
  });

  group('filing a quote', () {
    testWidgets(
      'the form offers boards for a standalone quote only, and saves the choice',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final lib = MemoryLibrary();
        final board = await lib.addBoard('Proverbs');
        await tester.pumpWidget(MaterialApp(home: QuoteFormScreen(store: lib)));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(DropdownButtonFormField<int?>, 'Board'),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'The words'),
          'A stitch in time.',
        );
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<int?>, 'Board'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proverbs').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect((await lib.quotes()).single.boardId, board.id);
      },
    );

    testWidgets('with no boards the form has no Board field', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: QuoteFormScreen(store: MemoryLibrary())),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(DropdownButtonFormField<int?>, 'Board'),
        findsNothing,
      );
    });
  });

  group('the library by board', () {
    late MemoryLibrary lib;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      final a = await lib.addBoard('Proverbs');
      final b = await lib.addBoard('Speeches');
      await lib.addQuote(QuoteDraft(text: 'A stitch in time.', boardId: a.id));
      await lib.addQuote(QuoteDraft(text: 'I have a dream.', boardId: b.id));
      await lib.addQuote(const QuoteDraft(text: 'Unfiled thought.'));
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(store: lib, picker: _Picker()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'filtering by a board shows only its quotes, and the chip clears it',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Board'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proverbs'));
        await tester.pumpAndSettle();
        expect(find.text('A stitch in time.'), findsOneWidget);
        expect(find.text('I have a dream.'), findsNothing);
        expect(find.text('Unfiled thought.'), findsNothing);
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(InputChip, 'Proverbs'),
            matching: find.byType(Icon),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('I have a dream.'), findsOneWidget);
      },
    );

    testWidgets('No board shows the quotes that are on none', (tester) async {
      await open(tester);
      await tester.tap(find.text('Board'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No board'));
      await tester.pumpAndSettle();
      expect(find.text('Unfiled thought.'), findsOneWidget);
      expect(find.text('A stitch in time.'), findsNothing);
    });

    testWidgets('grouping puts a heading over each board, then the rest', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Group by board'));
      await tester.pumpAndSettle();
      expect(find.text('Proverbs'), findsOneWidget);
      expect(find.text('Speeches'), findsOneWidget);
      expect(find.text('Not on a board'), findsOneWidget);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Proverbs'), lessThan(y('A stitch in time.')));
      expect(y('A stitch in time.'), lessThan(y('Speeches')));
      expect(y('I have a dream.'), lessThan(y('Not on a board')));
    });

    testWidgets(
      'the Boards button opens the boards, and a deleted board stops filtering',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Board'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proverbs'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Boards'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More for Proverbs'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Unfiled thought.'), findsOneWidget);
      },
    );
  });
}
