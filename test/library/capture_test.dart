import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/photo_source.dart';
import 'package:tippani/capture/text_recogniser.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/capture_screen.dart';
import 'package:tippani/screens/quote_form_screen.dart';

import '../support/memory_library.dart';

class _Photos implements PhotoSource {
  String? taken = '/no/such/page.jpg';
  String? chosen;
  bool boom = false;

  @override
  Future<String?> take() async {
    if (boom) throw Exception('no camera');
    return taken;
  }

  @override
  Future<String?> choose() async => chosen;
}

class _Reader implements TextRecogniser {
  _Reader(this.result);
  String result;
  bool boom = false;
  final calls = <(String, String)>[];

  @override
  Future<String> hocr(String imagePath, String language) async => '';

  @override
  Future<String> read(String imagePath, String language) async {
    calls.add((imagePath, language));
    if (boom) throw Exception('bad data');
    return result;
  }
}

void main() {
  group('tidying what Tesseract read', () {
    test('lines of a paragraph join; a blank line stays a paragraph break', () {
      expect(
        tidyRecognisedText('I went to the woods\nbecause I wished\n\nTo live.'),
        'I went to the woods because I wished\n\nTo live.',
      );
    });

    test('a word cut by a hyphen at a line end is mended', () {
      expect(tidyRecognisedText('the simpli-\nfy life'), 'the simplify life');
    });

    test('a hyphen before a capital or number is kept, not mended', () {
      expect(tidyRecognisedText('Jean-\nPaul'), 'Jean- Paul');
      expect(tidyRecognisedText('page 5-\n6'), 'page 5- 6');
    });

    test('Hindi lines join too, and stray spaces collapse', () {
      expect(tidyRecognisedText('सरल  बनो\nसरल'), 'सरल बनो सरल');
    });

    test('nothing in, nothing out', () {
      expect(tidyRecognisedText(' \n\n  \n'), '');
    });
  });

  group('the capture screen', () {
    late _Photos photos;
    late _Reader reader;
    CapturedText? result;

    /// Opens the screen the way the quote form does, and keeps what it hands back.
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      photos = _Photos();
      reader = _Reader('Simplify,\nsimplify.');
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
                        builder: (_) => CaptureScreen(
                          photos: photos,
                          recogniser: reader,
                          adjust: false,
                        ),
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
      'a photo is read in the chosen language and shown as editable text',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Take a photo'));
        await tester.pumpAndSettle();
        expect(reader.calls.single, ('/no/such/page.jpg', 'eng'));
        expect(find.text('Simplify, simplify.'), findsOneWidget);
      },
    );

    testWidgets('the language chosen is the one Tesseract is given', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English and Hindi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(reader.calls.single.$2, 'eng+hin');
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      await open(tester);
      photos.taken = null;
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(reader.calls, isEmpty);
      expect(find.text('Use this text'), findsNothing);
    });

    testWidgets('a picture with no text says so', (tester) async {
      await open(tester);
      reader.result = '  \n ';
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No text was found'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this text'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a reader that fails is said, not thrown', (tester) async {
      await open(tester);
      reader.boom = true;
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(
        find.text('The text could not be read from that picture.'),
        findsOneWidget,
      );
    });

    testWidgets('a camera that fails is said, not thrown', (tester) async {
      await open(tester);
      photos.boom = true;
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      expect(find.text('The picture could not be opened.'), findsOneWidget);
    });

    testWidgets('the corrected text is handed back, as scanned', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'The text, as read'),
        'Simplify.',
      );
      await tester.tap(find.text('Use this text'));
      await tester.pumpAndSettle();
      expect(result!.text, 'Simplify.');
      expect(result!.source, 'ocr');
    });

    testWidgets('going back without using the text hands back nothing', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('scanning from the Add a quote screen', () {
    late MemoryLibrary lib;
    late _Photos photos;
    late _Reader reader;

    Future<void> open(WidgetTester tester, {bool existing = false}) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      final quote = existing
          ? await lib.addQuote(const QuoteDraft(text: 'Old.'))
          : null;
      photos = _Photos();
      reader = _Reader('Simplfy.');
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteFormScreen(
            store: lib,
            quote: quote,
            photos: photos,
            recogniser: reader,
            adjustPage: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> scan(WidgetTester tester, {String fix = 'Simplify.'}) async {
      await tester.tap(find.text('Scan a page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'The text, as read'),
        fix,
      );
      await tester.tap(find.text('Use this text'));
      await tester.pumpAndSettle();
    }

    testWidgets('the buttons are on the form itself', (tester) async {
      await open(tester);
      expect(find.text('Scan a page'), findsOneWidget);
      expect(find.text('Speak'), findsOneWidget);
    });

    testWidgets(
      'scanned text lands in the words, and the saved quote is marked as scanned',
      (tester) async {
        await open(tester);
        await scan(tester);
        expect(find.widgetWithText(TextField, 'Simplify.'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final saved = (await lib.quotes()).single;
        expect(saved.text, 'Simplify.');
        expect(saved.source, 'ocr');
      },
    );

    testWidgets('a second page is added after the first, not over it', (
      tester,
    ) async {
      await open(tester);
      await scan(tester, fix: 'First page.');
      await scan(tester, fix: 'Second page.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await lib.quotes()).single.text, 'First page.\n\nSecond page.');
    });

    testWidgets('words already typed are kept, with the scan after them', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'The words'),
        'Typed.',
      );
      await scan(tester, fix: 'Scanned.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await lib.quotes()).single;
      expect(saved.text, 'Typed.\n\nScanned.');
      expect(saved.source, 'ocr');
    });

    testWidgets('backing out of the scan changes nothing', (tester) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'The words'),
        'Typed.',
      );
      await tester.tap(find.text('Scan a page'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Typed.'), findsOneWidget);
    });

    testWidgets(
      'scanning into a quote that already exists keeps the way it was first captured',
      (tester) async {
        await open(tester, existing: true);
        await scan(tester);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final saved = (await lib.quotes()).single;
        expect(saved.text, 'Old.\n\nSimplify.');
        expect(saved.source, 'manual');
      },
    );
  });
}
