import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/screens/tools_screens.dart';
import 'package:tippani/tools/server_tools.dart';

import '../support/fake_tools.dart';

void main() {
  test('stats read the server own shape, and count every kind of quote', () {
    final s = LibraryStats.fromJson({
      'annotations': 2,
      'dialogues': 3,
      'quotes': 4,
      'books': 5,
      'films': 6,
      'shows': 7,
      'games': 0,
      'favorites': 8,
      'tags': 9,
      'anthologies': 1,
      'first_saved': '2026-11-06',
      'busiest_month': {'month': '2026-11', 'count': 4},
      'colors': {'blue': 1},
      'top_tags': [
        {'name': 'life', 'count': 3},
      ],
      'most_quoted': {'title': 'Walden', 'count': 9},
    });
    expect(s.quotes, 9);
    expect(s.favourites, 8);
    expect(s.busiestMonth, '2026-11');
    expect(s.topTags.single.name, 'life');
    expect(s.mostQuoted, 'Walden');
  });

  test('stats from a bare server still read', () {
    final s = LibraryStats.fromJson({});
    expect(s.quotes, 0);
    expect(s.topTags, isEmpty);
  });

  group('the Bin', () {
    late FakeTools tools;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: BinScreen(tools: tools)));
      await tester.pumpAndSettle();
    }

    setUp(() => tools = FakeTools());

    testWidgets('an empty bin says so', (tester) async {
      await open(tester);
      expect(find.text('The bin is empty.'), findsOneWidget);
    });

    testWidgets(
      'it lists what was deleted, what it held, and how long it is kept',
      (tester) async {
        tools.put(1, 'Walden', kind: 'book', children: 2);
        tools.put(2, 'Simplify.');
        await open(tester);
        expect(
          find.text('Things you delete are kept here for 30 days.'),
          findsOneWidget,
        );
        expect(find.text('Walden'), findsOneWidget);
        expect(find.textContaining('with 2 quotes'), findsOneWidget);
        expect(find.textContaining('Book quote'), findsOneWidget);
      },
    );

    testWidgets('restoring takes it out of the list', (tester) async {
      tools.put(2, 'Simplify.');
      await open(tester);
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();
      expect(tools.calls, ['restore 2']);
      expect(find.text('The bin is empty.'), findsOneWidget);
    });

    testWidgets('deleting for good asks first', (tester) async {
      tools.put(2, 'Simplify.');
      await open(tester);
      await tester.tap(find.byTooltip('Delete for good'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tools.calls, isEmpty);
      await tester.tap(find.byTooltip('Delete for good'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tools.calls, ['forever 2']);
    });

    testWidgets('emptying asks first, then clears everything', (tester) async {
      tools.put(1, 'A');
      tools.put(2, 'B');
      await open(tester);
      await tester.tap(find.byTooltip('Empty the bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty it'));
      await tester.pumpAndSettle();
      expect(tools.calls, ['empty']);
      expect(find.text('The bin is empty.'), findsOneWidget);
    });

    testWidgets(
      'a server that cannot be reached is said, with a way to try again',
      (tester) async {
        tools.fail = const ServerException('The server could not be reached.');
        await open(tester);
        expect(find.text('The server could not be reached.'), findsOneWidget);
        tools.fail = null;
        tools.put(1, 'Back');
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Back'), findsOneWidget);
      },
    );

    testWidgets('a failed restore is said and the list stays', (tester) async {
      tools.put(2, 'Simplify.');
      await open(tester);
      tools.fail = const ServerException('The server could not do that.');
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('The server could not do that.'), findsOneWidget);
    });
  });

  group('Statistics', () {
    testWidgets('shows the totals and the top tags', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tools = FakeTools()
        ..statsToShow = LibraryStats.fromJson({
          'annotations': 2,
          'books': 5,
          'first_saved': '2026-11-06',
          'top_tags': [
            {'name': 'life', 'count': 3},
          ],
        });
      await tester.pumpWidget(MaterialApp(home: StatsScreen(tools: tools)));
      await tester.pumpAndSettle();
      expect(find.text('Quotes'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2026-11-06'), findsOneWidget);
      expect(find.text('#life'), findsOneWidget);
      expect(find.text('Games'), findsNothing);
    });

    testWidgets('a failure is said', (tester) async {
      final tools = FakeTools()
        ..fail = const ServerException('The server took too long to answer.');
      await tester.pumpWidget(MaterialApp(home: StatsScreen(tools: tools)));
      await tester.pumpAndSettle();
      expect(find.text('The server took too long to answer.'), findsOneWidget);
    });
  });
}
