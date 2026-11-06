import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/voice_listener.dart';
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
  late MemoryLibrary lib;
  late _Ear ear;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    lib = MemoryLibrary();
    ear = _Ear();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceScreen(store: lib, listener: ear),
      ),
    );
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

  testWidgets('a second take adds to the words already there', (tester) async {
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

  testWidgets('a phone that cannot listen says what to check', (tester) async {
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
    'the text is corrected, carried to the form and saved as a manual quote',
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
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await lib.quotes()).single;
      expect(saved.text, 'Simplify.');
      expect(saved.source, 'manual');
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
}
