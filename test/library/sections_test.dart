import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/nav_icons.dart';
import 'package:tippani/settings/settings_store.dart';

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

Future<void> go(WidgetTester tester, String section) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(section),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('each section has its name and an icon of its own', () {
    expect(NavSection.values.map((s) => s.label), [
      'Library',
      'Catalogue',
      'Quotes',
      'Anthologies',
    ]);
    expect({for (final s in NavSection.values) s.svg}, hasLength(4));
    for (final s in NavSection.values) {
      expect(s.svg, contains('<path'));
      expect(s.svg, contains('viewBox'));
    }
  });

  testWidgets(
    'the bar has Library, Catalogue, Quotes, Anthologies and Settings, each with an icon',
    (tester) async {
      await open(tester);
      final bar = find.byType(NavigationBar);
      for (final label in [
        'Library',
        'Catalogue',
        'Quotes',
        'Anthologies',
        'Settings',
      ]) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.descendant(of: bar, matching: find.text('Server')),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byType(SvgPicture)),
        findsNWidgets(4),
      );
    },
  );

  testWidgets(
    'without the means to reach anthologies there is no Anthologies tab',
    (tester) async {
      await open(tester, anthologies: false);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Anthologies'),
        ),
        findsNothing,
      );
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
    expect(find.text('Walden'), findsNothing);
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

  testWidgets('the Quotes section shows the quotes, with their boards', (
    tester,
  ) async {
    await open(tester);
    await go(tester, 'Quotes');
    // the board holds quotes with no work; a book's quote stays with its book
    expect(find.text('A stitch in time.'), findsOneWidget);
    expect(find.text('Simplify, simplify.'), findsNothing);
    expect(find.text('Add a quote'), findsOneWidget);
    expect(find.byTooltip('Boards'), findsOneWidget);
    expect(find.text('Group by board'), findsOneWidget);
  });

  testWidgets('the Library and the Catalogue have no Boards button', (
    tester,
  ) async {
    await open(tester);
    expect(find.byTooltip('Boards'), findsNothing);
    await go(tester, 'Catalogue');
    expect(find.byTooltip('Boards'), findsNothing);
  });

  testWidgets('a section with nothing in it says so in its own words', (
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
    'a quote added while another section is open is there when its section is opened',
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

  testWidgets('the Anthologies tab is the anthologies screen', (tester) async {
    await open(tester);
    await go(tester, 'Anthologies');
    expect(find.text('No anthologies yet.'), findsOneWidget);
  });
}
