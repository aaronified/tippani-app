import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/quiz/quiz.dart';
import 'package:tippani/screens/dashboard_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_quiz.dart';
import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

/// A tall screen, so the whole of Home is built (a list builds only what is on screen).
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<AppController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final c = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
  );
  return c;
}

void main() {
  test('the greeting follows the clock and names the reader', () {
    expect(greetingFor(DateTime(2026, 11, 7, 3), 'asha'), 'Up late, asha');
    expect(greetingFor(DateTime(2026, 11, 7, 9), 'asha'), 'Good morning, asha');
    expect(greetingFor(DateTime(2026, 11, 7, 14), null), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 11, 7, 19), ''), 'Good evening');
    expect(greetingFor(DateTime(2026, 11, 7, 23), 'x'), 'Winding down, x');
  });

  test('the line for the day holds all day and moves on tomorrow', () {
    final a = epigraphFor(DateTime(2026, 11, 7, 1));
    expect(epigraphFor(DateTime(2026, 11, 7, 23)), a);
    expect(epigraphFor(DateTime(2026, 11, 8, 1)), isNot(a));
    expect(dateLine(DateTime(2026, 11, 7)), 'Saturday 7 November');
  });

  testWidgets(
    'Home shows the day, the library, the quiz, favourites, a shuffled line and this day in earlier years',
    (tester) async {
      _tall(tester);
      final lib = MemoryLibrary(clock: () => DateTime(2026, 11, 7, 10));
      final walden = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Henry David Thoreau'),
      );
      final film = await lib.addWork(
        const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
      );
      for (var i = 0; i < 6; i++) {
        await lib.addQuote(
          QuoteDraft(
            text: 'Favourite number $i',
            workId: walden.id,
            favorite: true,
          ),
        );
      }
      await lib.addQuote(
        QuoteDraft(text: 'Here is looking at you', workId: film.id),
      );
      final quiz = FakeQuiz(
        scoresValue: const QuizScores(
          dailyAnswered: 3,
          dailyGot: 2,
          streak: 4,
          remaining: 5,
          quota: 8,
          practiceAnswered: 10,
          practiceGot: 7,
          states: QuizStates(
            remembered: 6,
            forgetting: 2,
            unseen: 2,
            total: 10,
          ),
        ),
      );
      final controller = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              store: lib,
              quiz: quiz,
              controller: controller,
              picker: _Picker(),
              // a year later, on the day the quotes were noted
              clock: () => DateTime(2027, 11, 7, 10),
              random: math.Random(1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SUNDAY 7 NOVEMBER'), findsOneWidget);
      expect(find.text('Good morning'), findsOneWidget);
      // the two tiles
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('book · 6 quotes'), findsOneWidget);
      expect(find.text('title · 1 line'), findsOneWidget);
      // the quiz card
      expect(find.text('5 cards due today'), findsOneWidget);
      expect(find.text('4-day streak'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('7 of 10 recalled'), findsOneWidget);
      expect(find.text('WHERE YOU STAND'), findsOneWidget);
      // all seven were noted on this day last year
      expect(find.text('ON THIS DAY'), findsOneWidget);
      // favourites: four, then the rest on request
      expect(find.text('FAVOURITES'), findsOneWidget);
      expect(find.text('View more (2)'), findsOneWidget);
    },
  );

  testWidgets(
    'a quiz that is not available says to connect, and Start practice is off',
    (tester) async {
      _tall(tester);
      final lib = MemoryLibrary();
      final controller = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              store: lib,
              quiz: FakeQuiz(available: false),
              controller: controller,
              picker: _Picker(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Connect to your server in Settings'),
        findsOneWidget,
      );
      final practice = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Start practice'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(practice.onPressed, isNull);
      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
    },
  );

  testWidgets(
    'Shuffle picks a line from the library, Start opens the round, and waiting answers can be sent',
    (tester) async {
      _tall(tester);
      final lib = MemoryLibrary();
      await lib.addQuote(const QuoteDraft(text: 'The only line there is.'));
      final quiz = FakeQuiz(
        scoresValue: const QuizScores(remaining: 2, quota: 8),
        deck: const QuizDeck(items: []),
      )..waitingCount = 3;
      final controller = await _controller();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              store: lib,
              quiz: quiz,
              controller: controller,
              picker: _Picker(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The only line there is.'), findsNothing);
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(find.text('The only line there is.'), findsOneWidget);
      expect(find.text('Another one'), findsOneWidget);

      expect(find.text('3 answers waiting to be sent'), findsOneWidget);
      final before = quiz.drains;
      await tester.tap(find.text('Send now'));
      await tester.pump();
      expect(quiz.drains, before + 1);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Daily quiz'), findsWidgets);
      expect(find.text('Nothing due today.'), findsOneWidget);
    },
  );
}
