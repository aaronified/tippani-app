import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/boards/board_service.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/board_screen.dart';
import 'package:tippani/screens/boards_screen.dart';

import '../support/memory_library.dart';

/// A stand-in for the server's side of boards that keeps its answers in the phone's library, as the real one does.
class FakeBoards implements BoardService {
  FakeBoards(this.lib, {this.available = true});

  final MemoryLibrary lib;

  @override
  bool available;
  final calls = <String>[];

  @override
  Future<void> update(Board board, Map<String, Object?> changes) async {
    calls.add('update ${board.name} $changes');
    await lib.linkBoard(board.id, board.serverId!, 'h', {
      ...board.serverRow,
      ...changes,
    });
  }

  @override
  Future<void> setImage(Board board, Uint8List bytes, String fileName) async {
    calls.add('picture ${board.name}');
  }

  @override
  Future<void> removeImage(Board board) async {
    calls.add('nopicture ${board.name}');
  }

  @override
  Future<List<StarterOffer>> starters() async => const [
    StarterOffer('Bengali', 12),
    StarterOffer('English', 10),
  ];

  @override
  Future<int> addStarters(Board board, String language) async {
    calls.add('starters ${board.name} $language');
    return 12;
  }
}

Map<String, Object?> row(int id, String name, {int pos = 0, Object? extra}) => {
  'id': id,
  'name': name,
  'description': '',
  'color': 'yellow',
  'image_path': '',
  'hidden': false,
  'pos': pos,
  'kind': 'plain',
  'languages': <String>[],
  'text_order': '',
};

Quote quote(
  int id,
  String text, {
  String speaker = '',
  String color = 'blue',
  bool fav = false,
  int day = 1,
}) => Quote(
  id: id,
  workId: null,
  text: text,
  translation: '',
  language: '',
  speaker: speaker,
  chapter: '',
  location: '',
  note: '',
  color: color,
  favorite: fav,
  notedAt: DateTime.utc(2026, 1, day),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

void main() {
  test('quotes are put in the order the reader picks', () {
    final a = quote(1, 'banana', speaker: 'Zed', day: 1);
    final b = quote(2, 'apple', speaker: 'Ann', day: 2, fav: true);
    final c = quote(3, 'cherry', day: 3, color: 'green');
    List<int> ids(BoardSort s) => [
      for (final q in sortBoardQuotes([a, b, c], s)) q.id,
    ];
    expect(ids(BoardSort.newest), [3, 2, 1]);
    expect(ids(BoardSort.oldest), [1, 2, 3]);
    expect(ids(BoardSort.text), [2, 1, 3]);
    expect(ids(BoardSort.speaker), [2, 1, 3], reason: 'Ann, Zed, then nobody');
    expect(ids(BoardSort.favourites), [2, 3, 1]);
    expect(
      ids(BoardSort.colour).first,
      isNot(3),
      reason: 'blue sorts before green',
    );
  });

  group('the Boards screen', () {
    late MemoryLibrary lib;
    late FakeBoards service;

    Future<void> open(WidgetTester tester, {bool available = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      service = FakeBoards(lib, available: available);
      await tester.pumpWidget(
        BoardScope(
          service: service,
          child: MaterialApp(home: BoardsScreen(store: lib)),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      lib = MemoryLibrary();
      await lib.adoptBoard('Proverbs', 'yellow', 1, 'h', {
        ...row(1, 'Proverbs', pos: 0),
        'kind': 'proverb',
        'languages': ['Bengali'],
      });
      await lib.adoptBoard('Speeches', 'blue', 2, 'h', {
        ...row(2, 'Speeches', pos: 1),
        'description': 'big words',
      });
    });

    Future<void> menu(WidgetTester tester, String board, String item) async {
      await tester.tap(find.byTooltip('More for $board'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows each board with its kind and description, in the reader\'s order',
      (tester) async {
        await open(tester);
        expect(find.textContaining('Proverbs'), findsWidgets);
        expect(find.textContaining('big words'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Proverbs').first).dy,
          lessThan(tester.getTopLeft(find.text('Speeches').first).dy),
        );
      },
    );

    testWidgets('a board is hidden and shown again', (tester) async {
      await open(tester);
      await menu(tester, 'Speeches', 'Hide');
      expect(service.calls.last, contains('hidden: true'));
      expect(find.textContaining('Hidden'), findsOneWidget);
      await menu(tester, 'Speeches', 'Show');
      expect(service.calls.last, contains('hidden: false'));
      expect(find.textContaining('Hidden'), findsNothing);
    });

    testWidgets('a board moves down, and each place is sent', (tester) async {
      await open(tester);
      await menu(tester, 'Proverbs', 'Move down');
      final order = [
        for (final b
            in await lib.boards()
              ..sort((x, y) => x.pos!.compareTo(y.pos!)))
          b.name,
      ];
      expect(order, ['Speeches', 'Proverbs']);
      expect(
        tester.getTopLeft(find.text('Speeches').first).dy,
        lessThan(tester.getTopLeft(find.text('Proverbs').first).dy),
      );
    });

    testWidgets('editing sends the kind, languages and description', (
      tester,
    ) async {
      await open(tester);
      await menu(tester, 'Speeches', 'Edit');
      await tester.tap(find.text('Proverbs').last);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Languages'),
        'Bengali, Hindi',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What it is for'),
        'sayings',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent = service.calls.last;
      expect(sent, contains('kind: proverb'));
      expect(sent, contains('[Bengali, Hindi]'));
      expect(sent, contains('description: sayings'));
    });

    testWidgets('starter proverbs are offered on a proverb board only', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('More for Speeches'));
      await tester.pumpAndSettle();
      expect(find.text('Add starter proverbs'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await menu(tester, 'Proverbs', 'Add starter proverbs');
      await tester.tap(find.textContaining('Bengali (12)'));
      await tester.pumpAndSettle();
      expect(service.calls.last, 'starters Proverbs Bengali');
      expect(find.textContaining('Added 12 proverbs'), findsOneWidget);
    });

    testWidgets('without the server there is only edit and delete', (
      tester,
    ) async {
      await open(tester, available: false);
      await tester.tap(find.byTooltip('More for Speeches'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);
      expect(find.text('Add a picture'), findsNothing);
    });

    testWidgets(
      'a board that is not on the server yet offers nothing from it',
      (tester) async {
        await lib.addBoard('Local');
        await open(tester);
        await tester.tap(find.byTooltip('More for Local'));
        await tester.pumpAndSettle();
        expect(find.text('Hide'), findsNothing);
      },
    );
  });

  group('one board', () {
    late MemoryLibrary lib;
    late Board board;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: BoardScreen(store: lib, boardId: board.id),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      lib = MemoryLibrary();
      board = await lib.adoptBoard('Proverbs', 'yellow', 1, 'h', {
        ...row(1, 'Proverbs'),
        'description': 'old sayings',
        'kind': 'proverb',
        'languages': ['Bengali'],
      });
      await lib.addQuote(
        QuoteDraft(text: 'banana', speaker: 'Zed', boardId: board.id),
      );
      await lib.addQuote(
        QuoteDraft(text: 'apple', speaker: 'Ann', boardId: board.id),
      );
      await lib.addQuote(QuoteDraft(text: 'elsewhere'));
    });

    double y(WidgetTester t, String text) =>
        t.getTopLeft(find.textContaining(text)).dy;

    testWidgets('shows its own quotes, its description, kind and languages', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('2 quotes'), findsOneWidget);
      expect(find.text('old sayings'), findsOneWidget);
      expect(find.text('Proverbs'), findsWidgets);
      expect(find.text('Bengali'), findsOneWidget);
      expect(find.textContaining('elsewhere'), findsNothing);
    });

    testWidgets('sorts A to Z and groups by who said it', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A to Z'));
      await tester.pumpAndSettle();
      expect(y(tester, 'apple'), lessThan(y(tester, 'banana')));

      await tester.tap(find.byTooltip('Group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Who said it'));
      await tester.pumpAndSettle();
      expect(find.text('Ann · 1'), findsOneWidget);
      expect(find.text('Zed · 1'), findsOneWidget);
    });
  });
}
