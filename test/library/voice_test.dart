import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/voice_listener.dart';
import 'package:tippani/screens/capture_screen.dart' show CapturedText;
import 'package:tippani/screens/quote_form_screen.dart';
import 'package:tippani/screens/voice_screen.dart';

import '../support/memory_library.dart';

class _Ear implements VoiceListener {
  bool canListen = true;
  bool boom = false;
  String? locale;
  int stops = 0;
  void Function(String)? onWords;

  @override
  Future<bool> start(String l, void Function(String) words) async {
    if (boom) throw Exception('no service');
    locale = l;
    onWords = words;
    return canListen;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('the speech screen', () {
    late _Ear ear;
    CapturedText? result;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ear = _Ear();
      result = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<CapturedText>(
                      MaterialPageRoute(
                        builder: (_) => VoiceScreen(listener: ear),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'speaking fills the box as words arrive, in the chosen language',
      (tester) async {
        await open(tester);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hindi').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start speaking'));
        await tester.pump();
        expect(ear.locale, 'hi_IN');
        expect(find.text('Listening…'), findsOneWidget);
        ear.onWords!('simplify');
        await tester.pump();
        ear.onWords!('simplify simplify');
        await tester.pump();
        expect(find.text('simplify simplify'), findsOneWidget);
      },
    );

    testWidgets('Stop stops listening and keeps the words', (tester) async {
      await open(tester);
      await tester.tap(find.text('Start speaking'));
      await tester.pump();
      ear.onWords!('hello there');
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(ear.stops, 1);
      expect(find.text('hello there'), findsOneWidget);
      expect(find.text('Start speaking'), findsOneWidget);
    });

    testWidgets('a second take adds to the words already there', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Start speaking'));
      await tester.pump();
      ear.onWords!('first');
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await tester.tap(find.text('Start speaking'));
      await tester.pump();
      ear.onWords!('second');
      await tester.pump();
      expect(find.text('first second'), findsOneWidget);
    });

    testWidgets('a phone that cannot listen says what to check', (
      tester,
    ) async {
      await open(tester);
      ear.canListen = false;
      await tester.tap(find.text('Start speaking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not listen'), findsOneWidget);
      expect(find.text('Start speaking'), findsOneWidget);
    });

    testWidgets('a recogniser that throws is said, not thrown', (tester) async {
      await open(tester);
      ear.boom = true;
      await tester.tap(find.text('Start speaking'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not listen'), findsOneWidget);
    });

    testWidgets(
      'the corrected words are handed back, as typed, and listening stops',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Start speaking'));
        await tester.pump();
        ear.onWords!('simplfy');
        await tester.pump();
        await tester.enterText(
          find.widgetWithText(TextField, 'The words, as heard'),
          'Simplify.',
        );
        await tester.tap(find.text('Use this text'));
        await tester.pumpAndSettle();
        expect(ear.stops, greaterThan(0));
        expect(result!.text, 'Simplify.');
        expect(result!.source, 'manual');
      },
    );

    testWidgets('there is no Use this text until there are words', (
      tester,
    ) async {
      await open(tester);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use this text'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('speaking from the Add a quote screen', () {
    late MemoryLibrary lib;
    late _Ear ear;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      ear = _Ear();
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteFormScreen(store: lib, listener: ear),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the words land in the form and save as a normal quote', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Speak'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start speaking'));
      await tester.pump();
      ear.onWords!('simplfy');
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'The words, as heard'),
        'Simplify.',
      );
      await tester.tap(find.text('Use this text'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Simplify.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await lib.quotes()).single;
      expect(saved.text, 'Simplify.');
      expect(saved.source, 'manual');
    });
  });
}
