import 'package:flutter/foundation.dart';
import 'package:tippani/quiz/quiz.dart';

/// The server's quiz, in memory, for screen tests.
class FakeQuiz extends ChangeNotifier implements QuizService {
  FakeQuiz({
    this.available = true,
    this.deck = const QuizDeck(items: []),
    this.practiceCards = const [],
    this.scoresValue = const QuizScores(),
  });

  @override
  bool available;

  QuizDeck deck;
  List<QuizCard> practiceCards;
  QuizScores scoresValue;

  /// When set, the loading calls throw it.
  QuizException? fail;

  /// Every answer given, in order.
  final answers = <QuizAnswer>[];
  final seenCalls = <String>[];
  int resets = 0;
  int drains = 0;

  /// What the server says to an answer; null makes the answer wait (as when offline).
  AnswerOutcome? Function(QuizAnswer a)? reply;

  int waitingCount = 0;

  @override
  int get waiting => waitingCount;

  @override
  Future<QuizDeck> daily() async {
    if (fail != null) throw fail!;
    return deck;
  }

  @override
  Future<List<QuizCard>> practice() async {
    if (fail != null) throw fail!;
    return practiceCards;
  }

  @override
  Future<QuizScores> scores() async {
    if (fail != null) throw fail!;
    return scoresValue;
  }

  @override
  Future<AnswerOutcome?> answer(QuizAnswer a) async {
    answers.add(a);
    final r = reply;
    if (r != null) return r(a);
    return AnswerOutcome(result: a.result);
  }

  @override
  Future<void> seen(String kind, int id) async => seenCalls.add('$kind/$id');

  @override
  Future<void> resetPractice() async => resets++;

  @override
  Future<void> drain() async => drains++;
}
