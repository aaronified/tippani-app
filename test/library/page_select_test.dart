import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/photo_source.dart';
import 'package:tippani/capture/recognised_page.dart';
import 'package:tippani/capture/text_recogniser.dart';
import 'package:tippani/screens/capture_screen.dart';

const hocr = '''
<div class='ocr_page' id='page_1' title='image "/data/page.png"; bbox 0 0 400 200; ppageno 0'>
 <div class='ocr_carea' id='block_1_1' title="bbox 20 20 380 180">
  <p class='ocr_par' id='par_1_1' lang='eng' title="bbox 20 20 380 90">
   <span class='ocr_line' id='line_1_1' title="bbox 20 20 380 50; baseline 0 -5; x_size 30">
    <span class='ocrx_word' id='word_1_1' title='bbox 20 20 110 50; x_wconf 95'>Simplify,</span>
    <span class='ocrx_word' id='word_1_2' title='bbox 120 20 200 50; x_wconf 95'>sim-</span>
   </span>
   <span class='ocr_line' id='line_1_2' title="bbox 20 60 380 90; baseline 0 -5">
    <span class='ocrx_word' id='word_1_3' title='bbox 20 60 100 90; x_wconf 91'>plify.</span>
    <span class='ocrx_word' id='word_1_4' title='bbox 110 60 180 90; x_wconf 91'><strong>Our</strong></span>
    <span class='ocrx_word' id='word_1_5' title='bbox 190 60 300 90; x_wconf 91'>Tom &amp; Jerry</span>
   </span>
  </p>
  <p class='ocr_par' id='par_1_2' lang='eng' title="bbox 20 150 380 180">
   <span class='ocr_line' id='line_2_1' title="bbox 20 150 380 180; baseline 0 -5">
    <span class='ocrx_word' id='word_2_1' title='bbox 20 150 120 180; x_wconf 90'>Later.</span>
   </span>
  </p>
 </div>
</div>
''';

void main() {
  group('reading hOCR', () {
    test('finds the page, its lines and their words in order', () {
      final p = parseHocr(hocr);
      expect(p.width, 400);
      expect(p.height, 200);
      expect(p.lines, hasLength(3));
      expect(p.lines.map((l) => l.words.length), [2, 3, 1]);
      expect(p.words.map((w) => w.index), [0, 1, 2, 3, 4, 5]);
      expect(p.words.first.text, 'Simplify,');
      expect(p.words.first.box, const Rect.fromLTRB(20, 20, 110, 50));
      expect(p.lines.first.box, const Rect.fromLTRB(20, 20, 380, 50));
    });

    test('markup round a word is dropped and entities are read', () {
      final p = parseHocr(hocr);
      expect(p.words.map((w) => w.text), contains('Our'));
      expect(p.words.map((w) => w.text), contains('Tom & Jerry'));
    });

    test(
      'numeric entities too, and quotes of either kind round the attributes',
      () {
        final p = parseHocr(
          '<div class="ocr_page" title="bbox 0 0 50 20"><span class="ocr_line" title="bbox 0 0 50 20">'
          '<span class="ocrx_word" title="bbox 0 0 20 20">caf&#233;</span>'
          '<span class="ocrx_word" title="bbox 25 0 50 20">&#x41;&#x42;</span></span></div>',
        );
        expect(p.words.map((w) => w.text), ['café', 'AB']);
      },
    );

    test('a word with no box or no text is skipped, and nothing that is not hOCR is an error', () {
      final p = parseHocr(
        "<span class='ocr_line' title='bbox 0 0 50 20'>"
        "<span class='ocrx_word' title='x_wconf 90'>nobox</span>"
        "<span class='ocrx_word' title='bbox 0 0 20 20'>  </span>"
        "<span class='ocrx_word' title='bbox 25 0 50 20'>ok</span></span>",
      );
      expect(p.words.map((w) => w.text), ['ok']);
      for (final junk in [
        '',
        'plain text',
        '<html></html>',
        '<span class="ocr_line">',
      ]) {
        expect(parseHocr(junk).isEmpty, isTrue, reason: junk);
      }
    });

    test('a page with no size of its own takes the size of what is on it', () {
      final p = parseHocr(
        "<span class='ocr_line' title='bbox 0 0 300 20'><span class='ocrx_word' title='bbox 0 0 300 20'>x</span></span>",
      );
      expect(p.width, 300);
      expect(p.height, 20);
    });
  });

  group('choosing words', () {
    late RecognisedPage page;
    late PageSelection sel;

    setUp(() {
      page = parseHocr(hocr);
      sel = PageSelection(page);
    });

    test('nothing is chosen at first; Select all chooses everything', () {
      expect(sel.isEmpty, isTrue);
      expect(sel.text(), '');
      sel.selectAll();
      expect(sel.count, 6);
    });

    test('the text mends a word cut at a line end, joins a paragraph, and keeps a gap as a break', () {
      sel.selectAll();
      expect(sel.text(), 'Simplify, simplify. Our Tom & Jerry\n\nLater.');
    });

    test('tapping a word takes it, tapping again leaves it out; a tap on nothing does nothing', () {
      expect(sel.toggleAt(const Offset(60, 35)), isTrue);
      expect(sel.text(), 'Simplify,');
      expect(sel.toggleAt(const Offset(60, 35)), isTrue);
      expect(sel.isEmpty, isTrue);
      expect(sel.toggleAt(const Offset(390, 120)), isFalse);
    });

    test('a few pixels off a word still finds it', () {
      expect(sel.wordAt(const Offset(113, 35))?.text, 'Simplify,');
      expect(sel.wordAt(const Offset(150, 120)), isNull);
    });

    test('a box takes the words it covers, and only those', () {
      sel.addInRect(const Rect.fromLTRB(10, 55, 390, 95));
      expect(sel.text(), 'Our Tom & Jerry');
    });

    test('a box that only grazes a line does not pick it up', () {
      sel.addInRect(const Rect.fromLTRB(10, 10, 390, 55));
      expect(sel.text(), 'Simplify, sim-');
      // 5 of the second line's 30 pixels
      final other = PageSelection(page)
        ..addInRect(const Rect.fromLTRB(10, 10, 390, 65));
      expect(other.text(), 'Simplify, sim-');
    });

    test('boxes add to each other, and Clear starts over', () {
      sel.addInRect(const Rect.fromLTRB(10, 55, 390, 95));
      sel.addInRect(const Rect.fromLTRB(10, 145, 390, 185));
      expect(sel.text(), 'Our Tom & Jerry\n\nLater.');
      sel.clear();
      expect(sel.isEmpty, isTrue);
    });

    test('words chosen from different lines keep their reading order whatever order they were chosen in', () {
      sel.addInRect(const Rect.fromLTRB(10, 145, 390, 185));
      sel.addInRect(const Rect.fromLTRB(10, 10, 390, 55));
      expect(sel.text(), 'Simplify, sim-\n\nLater.');
    });
  });

  group('choosing on the picture', () {
    late _Reader reader;
    CapturedText? result;

    Future<void> open(
      WidgetTester tester, {
      String html = hocr,
      bool failHocr = false,
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      reader = _Reader(html)..failHocr = failHocr;
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
                          photos: _Photos(),
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
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
    }

    /// A point on the picture, given in the page's own pixels.
    Offset at(WidgetTester tester, double x, double y) {
      final stage = find.byKey(const Key('page-stage'));
      final scale = tester.getSize(stage).width / 400;
      return tester.getTopLeft(stage) + Offset(x * scale, y * scale);
    }

    String field(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'The text, as read'))
        .controller!
        .text;

    testWidgets(
      'the page is shown with every word chosen, and its text is in the box',
      (tester) async {
        await open(tester);
        expect(find.byKey(const Key('page-stage')), findsOneWidget);
        expect(field(tester), 'Simplify, simplify. Our Tom & Jerry\n\nLater.');
      },
    );

    testWidgets(
      'tapping a word leaves it out of the text, and again takes it back',
      (tester) async {
        await open(tester);
        await tester.tapAt(at(tester, 60, 165));
        await tester.pump();
        expect(field(tester), 'Simplify, simplify. Our Tom & Jerry');
        await tester.tapAt(at(tester, 60, 165));
        await tester.pump();
        expect(field(tester), 'Simplify, simplify. Our Tom & Jerry\n\nLater.');
      },
    );

    testWidgets(
      'Clear empties it and the text cannot be used; dragging a box across a line picks just that line',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Clear'));
        await tester.pump();
        expect(field(tester), '');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this text'),
              )
              .onPressed,
          isNull,
        );
        await tester.dragFrom(at(tester, 10, 55), const Offset(700, 0));
        await tester.pump();
        // a flat drag has no height: nothing yet
        expect(field(tester), '');
        final from = at(tester, 10, 55);
        final to = at(tester, 390, 95);
        await tester.dragFrom(from, to - from);
        await tester.pump();
        expect(field(tester), 'Our Tom & Jerry');
      },
    );

    testWidgets('Select all takes everything again', (tester) async {
      await open(tester);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(field(tester), 'Simplify, simplify. Our Tom & Jerry\n\nLater.');
    });

    testWidgets('what is chosen is what is handed back', (tester) async {
      await open(tester);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      final from = at(tester, 10, 145);
      final to = at(tester, 390, 185);
      await tester.dragFrom(from, to - from);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Use this text'));
      await tester.pumpAndSettle();
      expect(result!.text, 'Later.');
      expect(result!.source, 'ocr');
    });

    testWidgets('the text can still be corrected by hand after choosing', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'The text, as read'),
        'Fixed by hand.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Use this text'));
      await tester.pumpAndSettle();
      expect(result!.text, 'Fixed by hand.');
    });

    testWidgets(
      'if Tesseract gives no words with places, the plain text is used as before',
      (tester) async {
        await open(tester, html: '');
        expect(find.byKey(const Key('page-stage')), findsNothing);
        expect(field(tester), 'Plain fallback.');
      },
    );

    testWidgets(
      'if the words with places cannot be had, the plain text is used as before',
      (tester) async {
        await open(tester, failHocr: true);
        expect(find.byKey(const Key('page-stage')), findsNothing);
        expect(field(tester), 'Plain fallback.');
      },
    );
  });
}

class _Photos implements PhotoSource {
  @override
  Future<String?> take() async => '/no/page.jpg';
  @override
  Future<String?> choose() async => null;
}

class _Reader implements TextRecogniser {
  _Reader(this.html);
  final String html;
  bool failHocr = false;

  @override
  Future<String> hocr(String imagePath, String language) async {
    if (failHocr) throw Exception('no hocr');
    return html;
  }

  @override
  Future<String> read(String imagePath, String language) async =>
      'Plain fallback.';
}
