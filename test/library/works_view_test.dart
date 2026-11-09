import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/theme/tabler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_widgets.dart';
import 'package:tippani/screens/works_view.dart';

int _n = 0;

Work _w(
  String title, {
  String creator = '',
  int? year,
  String language = '',
  WorkKind kind = WorkKind.book,
  String status = '',
  int progress = 0,
  List<String> genres = const [],
  int added = 0,
}) => Work(
  id: ++_n,
  kind: kind,
  title: title,
  creator: creator,
  year: year,
  language: language,
  createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: added)),
  updatedAt: DateTime.utc(2026),
  details: WorkDetails(status: status, progress: progress, genres: genres),
);

List<String> _titles(List<Work> ws) => [for (final w in ws) w.title];

void main() {
  final dune = _w(
    'Dune',
    creator: 'Herbert',
    year: 1965,
    language: 'en',
    status: 'reading',
    progress: 40,
    genres: ['Sci-fi'],
    added: 3,
  );
  final emma = _w(
    'Emma',
    creator: 'Austen',
    year: 1815,
    language: 'en',
    status: 'completed',
    genres: ['Romance'],
    added: 1,
  );
  final walden = _w('Walden', creator: 'Thoreau', year: 1854, added: 2);
  final aeneid = _w('aeneid', creator: 'Virgil', status: 'abandoned', added: 4);
  final all = [dune, emma, walden, aeneid];

  group('ordering', () {
    test('by title, ignoring capitals', () {
      expect(_titles(sortWorks(all, WorkSort.title)), [
        'aeneid',
        'Dune',
        'Emma',
        'Walden',
      ]);
    });

    test('by maker', () {
      expect(_titles(sortWorks(all, WorkSort.creator)), [
        'Emma',
        'Dune',
        'Walden',
        'aeneid',
      ]);
    });

    test('by year, a work with no year last either way', () {
      expect(_titles(sortWorks(all, WorkSort.yearNewest)), [
        'Dune',
        'Walden',
        'Emma',
        'aeneid',
      ]);
      expect(_titles(sortWorks(all, WorkSort.yearOldest)), [
        'Emma',
        'Walden',
        'Dune',
        'aeneid',
      ]);
    });

    test('by when it was added, newest first', () {
      expect(_titles(sortWorks(all, WorkSort.added)), [
        'aeneid',
        'Dune',
        'Walden',
        'Emma',
      ]);
    });

    test('never changes the list it is given', () {
      final before = _titles(all);
      sortWorks(all, WorkSort.yearNewest);
      expect(_titles(all), before);
    });
  });

  group('grouping', () {
    String label(String k) => k.isEmpty ? '(none)' : k;

    test('by decade, newest first, "none" last', () {
      final g = groupWorks(all, WorkGroup.decade, labelOf: label);
      expect([for (final x in g) x.title], ['1960', '1850', '1810', '(none)']);
    });

    test('by where the reader is: in progress first, then not started, then finished', () {
      final g = groupWorks(all, WorkGroup.status, labelOf: label);
      expect(
        [for (final x in g) x.title],
        ['inprogress', '(none)', 'completed', 'abandoned'],
      );
      expect(_titles(g.first.works), ['Dune']);
    });

    test('by genre, with the genreless last', () {
      final g = groupWorks(all, WorkGroup.genre, labelOf: label);
      expect([for (final x in g) x.title], ['Romance', 'Sci-fi', '(none)']);
      expect(_titles(g.last.works), ['Walden', 'aeneid']);
    });

    test('none is one heading-less group, in the order given', () {
      final g = groupWorks(all, WorkGroup.none, labelOf: label);
      expect(g, hasLength(1));
      expect(g.single.title, '');
      expect(_titles(g.single.works), _titles(all));
    });
  });

  group('the shelf filter', () {
    test('keeps what each word says', () {
      expect(_titles(all.where(WorkShelfFilter.inProgress.keeps).toList()), [
        'Dune',
      ]);
      expect(_titles(all.where(WorkShelfFilter.notStarted.keeps).toList()), [
        'Walden',
      ]);
      expect(_titles(all.where(WorkShelfFilter.finished.keeps).toList()), [
        'Emma',
      ]);
      expect(_titles(all.where(WorkShelfFilter.abandoned.keeps).toList()), [
        'aeneid',
      ]);
      expect(all.where(WorkShelfFilter.all.keeps), hasLength(4));
    });

    test(
      'a film is in progress when it is being watched, a game when played',
      () {
        final film = _w('Casablanca', kind: WorkKind.film, status: 'watching');
        final game = _w('Hades', kind: WorkKind.game, status: 'playing');
        final book = _w('B', status: 'watching');
        expect(WorkShelfFilter.inProgress.keeps(film), isTrue);
        expect(WorkShelfFilter.inProgress.keeps(game), isTrue);
        expect(
          WorkShelfFilter.inProgress.keeps(book),
          isFalse,
          reason: 'a book is read, not watched',
        );
      },
    );
  });

  group('the view', () {
    Future<void> open(
      WidgetTester tester, {
      List<Work>? works,
      List<Work>? opened,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorksView(
              works: works ?? all,
              onOpen: (w) => opened?.add(w),
              sectionKey: 'books',
              prefs: prefs,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the works by title, with their count', (tester) async {
      await open(tester);
      expect(find.byType(WorkTile), findsNWidgets(4));
      expect(find.text('4 works'), findsOneWidget);
      final first = tester.widget<WorkTile>(find.byType(WorkTile).first);
      expect(first.work.title, 'aeneid');
    });

    testWidgets(
      'a filter keeps some, says how many of the whole, and can be undone',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('works-filter-finished')));
        await tester.pumpAndSettle();
        expect(find.byType(WorkTile), findsOneWidget);
        expect(find.text('1 of 4 works'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('works-filter-all')));
        await tester.pumpAndSettle();
        expect(find.byType(WorkTile), findsNWidgets(4));
      },
    );

    testWidgets('a filter with nothing in it says so', (tester) async {
      await open(tester, works: [walden]);
      await tester.tap(find.byKey(const ValueKey('works-filter-paused')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkTile), findsNothing);
      expect(find.textContaining('No works match'), findsOneWidget);
    });

    testWidgets('sorting and grouping are chosen from the menus', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('works-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decade').last);
      await tester.pumpAndSettle();
      expect(find.text('1960s'), findsOneWidget);
      expect(find.text('1850s'), findsOneWidget);
      expect(find.text('Year unknown'), findsOneWidget);

      // back to one list, then newest added first: the order changes from A-Z to by date
      await tester.tap(find.byKey(const ValueKey('works-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No grouping').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorkTile>(find.byType(WorkTile).first).work.title,
        'aeneid',
      );
      await tester.tap(find.byKey(const ValueKey('works-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year, oldest first').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorkTile>(find.byType(WorkTile).first).work.title,
        'Emma',
      );
    });

    testWidgets('covers: the grid shows every work, and one opens', (
      tester,
    ) async {
      final opened = <Work>[];
      await open(tester, opened: opened);
      await tester.tap(find.byKey(const ValueKey('works-view')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkTile), findsNothing);
      expect(find.byKey(ValueKey('cover-${dune.id}')), findsOneWidget);
      // the shelf status rides on the cover
      expect(find.textContaining('Reading'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('cover-${dune.id}')));
      expect(opened.single.title, 'Dune');
    });

    testWidgets(
      'selecting many: a long press picks, and the pick is marked in both views',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final longPressed = <Work>[];
        var picked = <int>{};
        Future<void> pump() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: WorksView(
                  works: all,
                  onOpen: (_) {},
                  onLongPress: longPressed.add,
                  selected: picked,
                  sectionKey: 'books',
                  prefs: prefs,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pump();
        await tester.longPress(find.byType(WorkTile).first);
        expect(longPressed.single.title, 'aeneid');
        picked = {aeneid.id};
        await pump();
        expect(
          tester
              .widgetList<WorkTile>(find.byType(WorkTile))
              .where((t) => t.selected)
              .single
              .work
              .title,
          'aeneid',
        );
        await tester.tap(find.byKey(const ValueKey('works-view')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Ti.circleCheckFilled), findsOneWidget);
        await tester.longPress(find.byKey(ValueKey('cover-${dune.id}')));
        expect(longPressed.last.title, 'Dune');
      },
    );

    testWidgets('the choices are kept for the next visit', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('works-view')));
      await tester.tap(find.byKey(const ValueKey('works-filter-finished')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('library_books_grid'), isTrue);
      expect(prefs.getString('library_books_filter'), 'finished');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorksView(
              works: all,
              onOpen: (_) {},
              sectionKey: 'books',
              prefs: prefs,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('cover-${emma.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('cover-${dune.id}')), findsNothing);
    });
  });
}
