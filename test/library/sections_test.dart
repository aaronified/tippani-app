import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/boards_tab.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/widgets/swipe_pager.dart';

import '../support/fake_anthologies.dart';
import '../support/memory_library.dart';

late MemoryLibrary lib;

Future<void> open(WidgetTester tester, {bool anthologies = true}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  lib = MemoryLibrary();
  final book = await lib.addWork(
    const WorkDraft(title: 'Walden', creator: 'Thoreau'),
  );
  await lib.addWork(const WorkDraft(title: 'Casablanca', kind: WorkKind.film));
  await lib.addWork(const WorkDraft(title: 'Dark', kind: WorkKind.show));
  await lib.addWork(const WorkDraft(title: 'Hades', kind: WorkKind.game));
  await lib.addQuote(QuoteDraft(text: 'Simplify, simplify.', workId: book.id));
  await lib.addQuote(const QuoteDraft(text: 'A stitch in time.'));
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store);
  await tester.pumpWidget(
    TippaniApp(
      controller: c,
      harness: Harness.fake(
        store,
        controller: c,
        library: lib,
        anthologies: anthologies ? FakeAnthologies() : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _boards = ['Library', 'Catalogue', 'Quotes', 'Anthologies'];

/// Moves the Boards tab to [board] with its arrows.
Future<void> go(WidgetTester tester, String board) async {
  final want = _boards.indexOf(board);
  for (var i = 0; i < 8; i++) {
    if (find.text(board).evaluate().isNotEmpty && _title(tester) == board) {
      return;
    }
    final at = _boards.indexOf(_title(tester));
    await tester.tap(
      find.byKey(ValueKey(want > at ? 'board-next' : 'board-previous')),
    );
    await tester.pumpAndSettle();
  }
}

/// The name in the Boards header.
String _title(WidgetTester tester) {
  for (final b in _boards) {
    final f = find.descendant(
      of: find.byType(BoardsTab),
      matching: find.text(b),
    );
    for (final e in f.evaluate()) {
      final w = e.widget as Text;
      if (w.style?.fontSize != null && (w.style!.fontSize! >= 20)) return b;
    }
  }
  return 'Library';
}

void main() {
  test('the boards are the four pages of the collection, each with a name', () {
    expect(BoardKind.values.map((k) => k.name), [
      'library',
      'catalogue',
      'quotes',
      'anthologies',
    ]);
  });

  testWidgets('the bar has Boards, Server and Settings, each with an icon', (
    tester,
  ) async {
    await open(tester);
    final bar = find.byType(NavigationBar);
    for (final label in ['Boards', 'Server', 'Settings']) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    for (final gone in ['Library', 'Catalogue', 'Quotes', 'Anthologies']) {
      expect(
        find.descendant(of: bar, matching: find.text(gone)),
        findsNothing,
        reason: '$gone is a board now, not a tab',
      );
    }
  });

  testWidgets(
    'without the means to reach anthologies there is no Anthologies board',
    (tester) async {
      await open(tester, anthologies: false);
      expect(find.byKey(const ValueKey('board-next')), findsOneWidget);
      await go(tester, 'Quotes');
      final next = tester.widget<IconButton>(
        find.byKey(const ValueKey('board-next')),
      );
      expect(next.onPressed, isNull, reason: 'Quotes is the last of three');
    },
  );

  testWidgets(
    'the app opens on the Library, which shows the books and nothing else',
    (tester) async {
      await open(tester);
      expect(find.text('Walden'), findsOneWidget);
      expect(find.text('Casablanca'), findsNothing);
      expect(find.text('Dark'), findsNothing);
      expect(find.text('Add a book'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    },
  );

  testWidgets('the Catalogue shows films, shows and games, not books', (
    tester,
  ) async {
    await open(tester);
    await go(tester, 'Catalogue');
    expect(find.text('Casablanca'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Hades'), findsOneWidget);
    expect(find.text('Add a film, show or game'), findsOneWidget);
  });

  testWidgets(
    'adding from the Catalogue starts as a film; from the Library, as a book',
    (tester) async {
      await open(tester);
      await go(tester, 'Catalogue');
      await tester.tap(find.text('Add a film, show or game'));
      await tester.pumpAndSettle();
      final film = tester.widget<SegmentedButton<WorkKind>>(
        find.byType(SegmentedButton<WorkKind>),
      );
      expect(film.selected, {WorkKind.film});
      await tester.pageBack();
      await tester.pumpAndSettle();
      await go(tester, 'Library');
      await tester.tap(find.text('Add a book'));
      await tester.pumpAndSettle();
      final book = tester.widget<SegmentedButton<WorkKind>>(
        find.byType(SegmentedButton<WorkKind>),
      );
      expect(book.selected, {WorkKind.book});
    },
  );

  testWidgets('the Quotes board shows the standalone quotes and their boards', (
    tester,
  ) async {
    await open(tester);
    await go(tester, 'Quotes');
    expect(find.text('A stitch in time.'), findsOneWidget);
    expect(find.text('Add a quote'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Boards'), findsOneWidget);
    expect(find.text('Group by board'), findsOneWidget);
  });

  testWidgets('a board with nothing in it says so in its own words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
    final c = AppController(store);
    await tester.pumpWidget(
      TippaniApp(
        controller: c,
        harness: Harness.fake(store, controller: c, library: MemoryLibrary()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No books yet.'), findsOneWidget);
    await go(tester, 'Catalogue');
    expect(find.text('No films, shows or games yet.'), findsOneWidget);
    await go(tester, 'Quotes');
    expect(find.textContaining('No quotes yet'), findsOneWidget);
  });

  testWidgets(
    'a quote added while another board is open is there on its board',
    (tester) async {
      await open(tester);
      await go(tester, 'Quotes');
      await lib.addQuote(const QuoteDraft(text: 'Added somewhere else.'));
      await tester.pumpAndSettle();
      expect(find.text('Added somewhere else.'), findsOneWidget);
      await go(tester, 'Library');
      await lib.addWork(const WorkDraft(title: 'A new book'));
      await tester.pumpAndSettle();
      expect(find.text('A new book'), findsOneWidget);
    },
  );

  testWidgets('the Anthologies board is the anthologies screen', (
    tester,
  ) async {
    await open(tester);
    await go(tester, 'Anthologies');
    expect(find.text('No anthologies yet.'), findsOneWidget);
  });

  testWidgets('a sideways swipe moves to the next board, and back', (
    tester,
  ) async {
    await open(tester);
    expect(_title(tester), 'Library');
    await tester.fling(find.byType(SwipePager), const Offset(-500, 0), 1500);
    await tester.pumpAndSettle();
    expect(_title(tester), 'Catalogue');
    await tester.fling(find.byType(SwipePager), const Offset(500, 0), 1500);
    await tester.pumpAndSettle();
    expect(_title(tester), 'Library');
    // past the first board there is nothing, and it springs back
    await tester.fling(find.byType(SwipePager), const Offset(500, 0), 1500);
    await tester.pumpAndSettle();
    expect(_title(tester), 'Library');
  });

  testWidgets('the other tabs do not swipe', (tester) async {
    await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(ListView).first,
      const Offset(-500, 0),
      1500,
    );
    await tester.pumpAndSettle();
    // still the settings, not another tab
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(SwipePager), findsNothing);
  });
}
