// Runs the quiz code against a real Tippani server that holds a few books with quotes. Skipped unless
// TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/quiz/quiz.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'a real server sets the cards, grades a typed blank and takes answers',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final settings = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final controller = AppController(settings, log: AppLog());
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live quiz')).ok, isTrue);
      final quiz = ServerQuiz(controller, settings);

      final scores = await quiz.scores();
      expect(scores.quota, greaterThan(0));
      // may be empty inside the first week; it must at least be read
      await quiz.daily();

      // practice deals every direction; ask until a typed blank and a choice have turned up
      QuizCard? cloze, choice, flip;
      for (var i = 0; i < 30 && (cloze == null || choice == null); i++) {
        for (final c in await quiz.practice()) {
          if (c.isCloze) cloze ??= c;
          if (c.isChoice) choice ??= c;
          if (c.isFlip) flip ??= c;
        }
      }
      expect(flip, isNotNull);
      expect(choice, isNotNull, reason: 'a multiple-choice card');
      expect(choice!.options.length, greaterThan(1));
      expect(choice.answer, inInclusiveRange(0, choice.options.length - 1));
      expect(cloze, isNotNull, reason: 'a fill-in-the-blank card');
      expect(cloze!.hasBlank, isTrue);

      final wrong = await quiz.answer(
        QuizAnswer(
          kind: cloze.kind,
          id: cloze.id,
          result: 'got',
          mode: 'practice',
          attempt: 'zzzz-not-it',
        ),
      );
      expect(wrong, isNotNull);
      expect(
        wrong!.correct,
        isFalse,
        reason: 'the server grades the attempt, not the phone',
      );
      expect(wrong.answer, isNotEmpty, reason: 'and says what was missing');

      final got = await quiz.answer(
        QuizAnswer(
          kind: flip!.kind,
          id: flip.id,
          result: 'got',
          mode: 'practice',
        ),
      );
      expect(got!.result, 'got');
      expect(quiz.waiting, 0);
      await quiz.seen(flip.kind, flip.id);
      await quiz.resetPractice();
      expect((await quiz.scores()).practiceAnswered, 0);
    },
    skip: skip,
  );
}
