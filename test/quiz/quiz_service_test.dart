import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/quiz/quiz.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

Future<(FakeServer, ServerQuiz, SettingsStore, DateTime Function())> _rig({
  bool paired = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final settings = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final controller = AppController(settings, clientFactory: server.factory);
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My phone');
  var now = DateTime.utc(2026, 11, 7, 12);
  DateTime clock() => now = now.add(const Duration(seconds: 1));
  return (
    server,
    ServerQuiz(controller, settings, clock: clock),
    settings,
    clock,
  );
}

Map<String, Object?> _card(String direction, {int id = 1}) => {
  'kind': 'book',
  'id': id,
  'direction': direction,
  'quote': 'Simplify, simplify.',
  'title': 'Walden',
  'author': 'Henry David Thoreau',
  'year': 1854,
  'media_type': '',
  'options': ['Walden', 'Emma'],
  'answer': 0,
  'option_meta': [
    {'art': '0123456789abcdef.png', 'source': 'Walden', 'creator': 'Thoreau'},
    {'item_kind': 'book', 'item_id': 5},
  ],
  'easy_chips': [
    {'name': 'Ishmael', 'path': 'fedcba9876543210.png'},
  ],
};

void main() {
  test('answers waiting for the server go when the phone is unpaired, and the count is told', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    final server = FakeServer();
    final settings = SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
    final controller = AppController(settings, clientFactory: server.factory);
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    final quiz = ServerQuiz(controller, settings);
    server.unreachable = true;
    await quiz.queue.keep(
      const QuizAnswer(kind: 'annotation', id: 1, result: 'got', mode: 'daily'),
      offset: 0,
    );
    expect(quiz.queue.length, 1);
    var told = 0;
    quiz.queue.addListener(() => told++);
    await controller.unpair();
    expect(quiz.queue.length, 0, reason: 'never sent for the next account');
    expect(settings.quizAnswers, isNull);
    expect(told, greaterThan(0));
  });

  test('the daily deck, the practice deck and the scores are read as the server sends them', () async {
    final (server, quiz, _, _) = await _rig();
    server.reviewDaily = {
      'items': [_card('source'), _card('cloze', id: 2)],
      'answered_today': 3,
      'got_today': 2,
      'forgot_today': 1,
      'quota': 8,
      'streak': 4,
      'states': {
        'unseen': 1,
        'remembered': 2,
        'forgetting': 3,
        'probably_forgotten': 4,
        'total': 10,
      },
      'capacity': 2900,
    };
    server.reviewPractice = {
      'items': [_card('flip')],
    };
    server.reviewScores = {
      'daily': {
        'answered': 3,
        'got': 2,
        'streak': 4,
        'days': 9,
        'remaining': 5,
        'quota': 8,
      },
      'practice': {'answered': 10, 'got': 7, 'sessions': 2},
      'states': {'total': 10, 'remembered': 6},
      'capacity': 2900,
    };

    final deck = await quiz.daily();
    expect(deck.items, hasLength(2));
    expect(deck.items.first.options, ['Walden', 'Emma']);
    expect(deck.items.first.meta.last.itemId, 5);
    expect(deck.items.first.easyChips.single.image, 'fedcba9876543210.png');
    expect(deck.items.first.creditLine, 'Henry David Thoreau · 1854');
    expect(deck.answeredToday, 3);
    expect(deck.streak, 4);
    expect(deck.states.probablyForgotten, 4);
    expect((await quiz.practice()).single.isFlip, isTrue);
    await quiz.practice(anthology: 4);
    expect(
      server.requests.last.url.queryParameters['anthology'],
      '4',
      reason: 'Practise on an anthology asks the server for that anthology',
    );
    expect(
      server.requests
          .where((r) => r.url.path.endsWith('/review/practice'))
          .first
          .url
          .queryParameters
          .containsKey('anthology'),
      isFalse,
    );
    final scores = await quiz.scores();
    expect(scores.remaining, 5);
    expect(scores.practiceGot, 7);
    expect(scores.states.remembered, 6);
    // the phone's UTC offset is sent, so "today" is the reader's day
    final asked = server.requests
        .where((r) => r.url.path.endsWith('/review/daily'))
        .single;
    expect(asked.url.queryParameters['offset'], isNotNull);
  });

  test('an answer is sent with an id and its age, and the reply says what was graded', () async {
    final (server, quiz, settings, _) = await _rig();
    final out = await quiz.answer(
      const QuizAnswer(kind: 'book', id: 1, result: 'got', mode: 'daily'),
    );
    expect(out!.correct, isTrue);
    expect(out.remaining, 0);
    final sent = server.reviewAnswers.single;
    expect(sent['kind'], 'book');
    expect(sent['mode'], 'daily');
    expect(sent['client_id'], matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
    expect(sent['answered_ago_ms'], isA<int>());
    expect(sent.containsKey('attempt'), isFalse);
    expect(quiz.waiting, 0);
    expect(settings.quizAnswers, isNull);
  });

  test('a typed blank carries its attempt and the server grades it', () async {
    final (server, quiz, _, _) = await _rig();
    final out = await quiz.answer(
      const QuizAnswer(
        kind: 'book',
        id: 1,
        result: 'forgot',
        mode: 'daily',
        attempt: 'woods',
      ),
    );
    expect(server.reviewAnswers.single['attempt'], 'woods');
    expect(out!.result, 'got');
    expect(out.answer, 'woods');
  });

  test('answers made offline wait on the phone, in order, and go when the server can be reached', () async {
    final (server, quiz, settings, _) = await _rig();
    server.reviewOffline = true;
    expect(
      await quiz.answer(
        const QuizAnswer(kind: 'book', id: 1, result: 'got', mode: 'daily'),
      ),
      isNull,
    );
    expect(
      await quiz.answer(
        const QuizAnswer(kind: 'book', id: 2, result: 'forgot', mode: 'daily'),
      ),
      isNull,
    );
    expect(quiz.waiting, 2);
    // kept in the preferences, so closing the app does not lose them
    expect(settings.quizAnswers, isNotNull);
    expect(server.reviewAnswers, isEmpty);

    server.reviewOffline = false;
    await quiz.drain();
    expect(quiz.waiting, 0);
    expect(server.reviewAnswers.map((a) => a['id']), [1, 2]);
    // each carries how long ago it was given, so it counts for its own day
    expect(
      server.reviewAnswers.every((a) => (a['answered_ago_ms'] as int) >= 0),
      isTrue,
    );
    expect(settings.quizAnswers, isNull);
  });

  test(
    'an answer the server refuses for good is dropped, not sent again for ever',
    () async {
      final (server, quiz, _, _) = await _rig();
      server.reviewAnswerRefusal = 404; // the quote was deleted on the server
      final out = await quiz.answer(
        const QuizAnswer(kind: 'book', id: 1, result: 'got', mode: 'daily'),
      );
      expect(out, isNull);
      expect(quiz.waiting, 0);

      // while one the server is too busy for (429) is kept
      server.reviewAnswerRefusal = 429;
      await quiz.answer(
        const QuizAnswer(kind: 'book', id: 2, result: 'got', mode: 'daily'),
      );
      expect(quiz.waiting, 1);
    },
  );

  test('without a pairing nothing is asked and the answer waits', () async {
    final (server, quiz, _, _) = await _rig(paired: false);
    expect(quiz.available, isFalse);
    await expectLater(quiz.daily(), throwsA(isA<QuizException>()));
    expect(
      await quiz.answer(
        const QuizAnswer(kind: 'book', id: 1, result: 'got', mode: 'daily'),
      ),
      isNull,
    );
    expect(quiz.waiting, 1);
    expect(server.reviewAnswers, isEmpty);
  });

  test('seen and the practice reset reach the server', () async {
    final (server, quiz, _, _) = await _rig();
    await quiz.seen('screen', 4);
    await quiz.resetPractice();
    expect(server.reviewSeen.single, {'kind': 'screen', 'id': 4});
    expect(server.practiceResets, 1);
  });
}
