import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/quiz/quiz.dart';
import 'package:tippani/screens/quiz_screen.dart';

import '../support/fake_quiz.dart';

QuizCard _choice({
  String direction = 'source',
  List<String> options = const ['Walden', 'Moby-Dick', 'Emma'],
  int answer = 0,
}) => QuizCard(
  kind: 'book',
  id: 7,
  direction: direction,
  quote: 'Simplify, simplify.',
  title: 'Walden',
  author: 'Henry David Thoreau',
  year: 1854,
  options: options,
  answer: answer,
  meta: [
    for (var i = 0; i < options.length; i++)
      QuizOption(
        source: options[i],
        creator: 'Someone $i',
        year: 1800 + i,
        itemKind: i == answer ? '' : 'book',
        itemId: i == answer ? 0 : 100 + i,
      ),
  ],
);

QuizCard _cloze() => const QuizCard(
  kind: 'book',
  id: 8,
  direction: 'cloze',
  quote: 'I went to the $clozeBlank because I wished to live deliberately.',
  title: 'Walden',
);

QuizCard _flip() => const QuizCard(
  kind: 'screen',
  id: 9,
  direction: 'flip',
  quote: 'Here is looking at you, kid.',
  title: 'Casablanca',
  mediaType: 'movie',
);

Future<void> _open(WidgetTester tester, FakeQuiz quiz, QuizMode mode) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuizScreen(key: UniqueKey(), service: quiz, mode: mode),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a wrong choice is sent as forgot, marked, and the other quotes are reported seen',
    (tester) async {
      final quiz = FakeQuiz(deck: QuizDeck(items: [_choice()], quota: 8));
      await _open(tester, quiz, QuizMode.daily);

      expect(find.text('WHICH BOOK IS THIS QUOTE FROM?'), findsOneWidget);
      expect(find.text('Simplify, simplify.'), findsOneWidget);
      // nothing is sent, and the answer is not shown, until one is chosen and submitted
      expect(find.text('Choose an answer'), findsOneWidget);
      await tester.tap(find.text('Emma'));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(quiz.answers, hasLength(1));
      expect(quiz.answers.single.result, 'forgot');
      expect(quiz.answers.single.mode, 'daily');
      expect(quiz.answers.single.id, 7);
      expect(find.text('not quite'), findsOneWidget);
      // after the grade the options say where they are from
      expect(find.text('Someone 1 · 1801'), findsOneWidget);
      expect(quiz.seenCalls, ['book/101', 'book/102']);
      expect(find.text('Finish'), findsOneWidget);
    },
  );

  testWidgets('the right choice is sent as got', (tester) async {
    final quiz = FakeQuiz(deck: QuizDeck(items: [_choice()]));
    await _open(tester, quiz, QuizMode.daily);
    await tester.tap(find.text('Walden').first);
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(quiz.answers.single.result, 'got');
    expect(find.text('correct'), findsOneWidget);
  });

  testWidgets(
    'a typed blank goes to the server, which grades it and says what was missing',
    (tester) async {
      final quiz = FakeQuiz(deck: QuizDeck(items: [_cloze()]))
        ..reply = (a) => AnswerOutcome(
          result: a.attempt == 'woods' ? 'got' : 'forgot',
          answer: 'woods',
        );
      await _open(tester, quiz, QuizMode.daily);

      expect(find.text('FILL IN THE BLANK'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'meadow');
      await tester.pump();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(quiz.answers.single.attempt, 'meadow');
      expect(find.text('not quite'), findsOneWidget);
      expect(find.text('woods'), findsOneWidget);
      expect(find.text('what you wrote: meadow'), findsOneWidget);
    },
  );

  testWidgets('a typed blank made offline is kept to be marked', (
    tester,
  ) async {
    final quiz = FakeQuiz(deck: QuizDeck(items: [_cloze()]))
      ..reply = (_) => null;
    await _open(tester, quiz, QuizMode.daily);
    await tester.enterText(find.byType(TextField), 'woods');
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(find.text('kept, to be marked'), findsOneWidget);
    expect(find.text('correct'), findsNothing);
    expect(find.text('not quite'), findsNothing);
  });

  testWidgets(
    'practice: flip, mark yourself, skip, and the round ends with a score',
    (tester) async {
      final quiz = FakeQuiz(practiceCards: [_flip(), _choice()]);
      await _open(tester, quiz, QuizMode.practice);

      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Got it'), findsNothing);
      await tester.tap(find.text('Show me'));
      await tester.pump();
      expect(find.text('Casablanca'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(quiz.answers.single.result, 'got');
      expect(quiz.answers.single.mode, 'practice');
      expect(find.text('recalled'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(quiz.answers.last.result, 'skip');
      // skipping the last card ends the round
      expect(find.text('Round finished.'), findsOneWidget);
      expect(find.text('1 recalled · 0 missed · 1 skipped'), findsOneWidget);
      expect(find.text('Another round'), findsOneWidget);
    },
  );

  testWidgets(
    'an empty deck says there is nothing due, and a failure says why',
    (tester) async {
      await _open(tester, FakeQuiz(), QuizMode.daily);
      expect(find.text('Nothing due today.'), findsOneWidget);

      final broken = FakeQuiz()
        ..fail = const QuizException('The server could not be reached.');
      await _open(tester, broken, QuizMode.daily);
      expect(find.text('Could not load the cards.'), findsOneWidget);
      expect(find.text('The server could not be reached.'), findsOneWidget);
    },
  );

  testWidgets(
    'the daily round says it is done when the last card is answered',
    (tester) async {
      final quiz = FakeQuiz(
        deck: QuizDeck(items: [_choice()], answeredToday: 2),
      );
      await _open(tester, quiz, QuizMode.daily);
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.tap(find.text('Walden').first);
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.text('That is today done.'), findsOneWidget);
    },
  );
}
