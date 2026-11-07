import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/stats_screen.dart';
import 'package:tippani/tools/server_tools.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

class _Tools implements ServerTools {
  _Tools(this.data);
  final LibraryStats data;

  @override
  bool get available => true;
  @override
  Future<Bin> bin() async => const Bin(30, []);
  @override
  Future<void> restore(int id) async {}
  @override
  Future<void> deleteForever(int id) async {}
  @override
  Future<void> emptyBin() async {}
  @override
  Future<LibraryStats> stats() async => data;
}

String _day(int back) {
  final d = DateTime.now().subtract(Duration(days: back));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, Object?> _payload() => {
  'annotations': 4,
  'books': 2,
  'favorites': 1,
  'first_saved': '2026-01-02',
  'colors': {'yellow': 3, 'blue': 1},
  'daily_activity': [
    {'date': _day(0), 'count': 3},
    {'date': _day(2), 'count': 1},
  ],
  'daily_quiz': [
    {'date': _day(1), 'count': 2, 'got': 1},
  ],
  'daily_practice': [],
  'recall': {
    'reviewed': 2,
    'avg_half_life': 3.5,
    'streak': 1,
    'longest_streak': 4,
    'states': {
      'total': 4,
      'remembered': 1,
      'forgetting': 1,
      'probably_forgotten': 0,
      'unseen': 2,
    },
  },
  'most_annotated': {'id': 1, 'title': 'Walden', 'cover_path': '', 'count': 3},
  'favourite_person': {'id': 0, 'title': 'Thoreau', 'count': 1},
  'timeline': [
    {'year': 1854, 'works': 1, 'quotes': 3},
    {'year': 1999, 'works': 1, 'quotes': 1},
  ],
  'breakdown': {
    'authors': {
      'count': 1,
      'top': [
        {
          'name': 'Thoreau',
          'works': 1,
          'quotes': 3,
          'remembered': 1,
          'forgetting': 1,
          'probably_forgotten': 0,
          'unseen': 1,
        },
      ],
    },
    'people': {
      'count': 1,
      'top': [
        {
          'name': 'Thoreau',
          'works': 1,
          'quotes': 3,
          'remembered': 1,
          'forgetting': 1,
          'probably_forgotten': 0,
          'unseen': 1,
        },
      ],
      'most_remembered': {
        'name': 'Thoreau',
        'works': 1,
        'quotes': 3,
        'remembered': 1,
        'forgetting': 1,
        'probably_forgotten': 0,
        'unseen': 1,
      },
    },
    'actors': {'count': 0, 'top': []},
  },
  'top_tags': [
    {'name': 'life', 'count': 3},
  ],
};

void main() {
  test('the whole payload is read', () {
    final s = LibraryStats.fromJson(_payload());
    expect(s.saves.map((d) => d.count), [3, 1]);
    expect(s.quiz.single.count, 2);
    expect(s.recall.total, 4);
    expect(s.recall.longestStreak, 4);
    expect(s.recall.avgHalfLife, 3.5);
    expect(s.mostAnnotated!.title, 'Walden');
    expect(s.favouritePerson!.title, 'Thoreau');
    expect(s.timeline.map((y) => y.year), [1854, 1999]);
    expect(s.breakdown['authors']!.top.single.name, 'Thoreau');
    expect(s.breakdown['people']!.mostRemembered!.remembered, 1);
    expect(s.breakdown['actors']!.top, isEmpty);
  });

  test('an old or empty payload still reads', () {
    final s = LibraryStats.fromJson({'annotations': 1});
    expect(s.quotes, 1);
    expect(s.saves, isEmpty);
    expect(s.recall.total, 0);
    expect(s.breakdown, isEmpty);
    expect(s.mostAnnotated, isNull);
  });

  testWidgets('shows every section the server has numbers for', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tools = _Tools(LibraryStats.fromJson(_payload()));
    await tester.pumpWidget(MaterialApp(home: StatsScreen(tools: tools)));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Quiz'), findsOneWidget);
    expect(find.text('Practice'), findsNothing, reason: 'no practice yet');
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('2 of 4 in rotation'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.text('Most annotated'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.text('Authors'), findsOneWidget);
    expect(find.text('Actors'), findsNothing, reason: 'none to list');
    expect(find.text('Colours'), findsOneWidget);
    expect(find.text('Yellow'), findsOneWidget);
    expect(find.text('#life'), findsOneWidget);
  });

  testWidgets('the calendar reads each stream and names a day on a tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsScreen(tools: _Tools(LibraryStats.fromJson(_payload()))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 saved in all'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('3 on ${_day(0)}'));
    await tester.pump();
    expect(find.text('3 saved on ${_day(0)}'), findsOneWidget);
    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();
    expect(find.text('2 answered in the quiz in all'), findsOneWidget);
  });

  testWidgets('switching the breakdown kind shows its rows', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StatsScreen(tools: _Tools(LibraryStats.fromJson(_payload()))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 quotes'), findsWidgets);
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    expect(find.text('Thoreau'), findsWidgets);
  });

  testWidgets('a name opens the quotes behind it, a tag likewise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = MemoryLibrary();
    final w = await lib.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau'),
    );
    await lib.addQuote(
      QuoteDraft(
        text: 'Simplify, simplify.',
        workId: w.id,
        tags: const ['life'],
      ),
    );
    await lib.addQuote(const QuoteDraft(text: 'Unrelated words.'));
    await tester.pumpWidget(
      MaterialApp(
        home: StatsScreen(
          tools: _Tools(LibraryStats.fromJson(_payload())),
          store: lib,
          picker: _Picker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('#life'));
    await tester.pumpAndSettle();
    expect(find.text('Simplify, simplify.'), findsOneWidget);
    expect(find.text('Unrelated words.'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thoreau').first);
    await tester.pumpAndSettle();
    expect(find.text('Simplify, simplify.'), findsOneWidget);
    expect(find.text('Unrelated words.'), findsNothing);
  });
}
