import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/page_adjuster.dart';
import 'package:tippani/capture/page_geometry.dart';
import 'package:tippani/capture/photo_source.dart';
import 'package:tippani/capture/text_recogniser.dart';
import 'package:tippani/screens/adjust_screen.dart';
import 'package:tippani/screens/capture_screen.dart';

/// A page of "text": [lines] rows of short dark dashes on white, turned clockwise by [degrees] about the centre.
Luma page({
  double degrees = 0,
  int w = 300,
  int h = 400,
  int lines = 9,
  int left = 30,
  int right = 270,
  int top = 60,
  int step = 36,
}) {
  final data = Uint8List(w * h)..fillRange(0, w * h, 255);
  final r = degrees * math.pi / 180;
  final c = math.cos(r), s = math.sin(r);
  for (var i = 0; i < lines; i++) {
    final y = top + i * step;
    for (var x = left; x < right; x++) {
      if ((x ~/ 3) % 2 == 0) {
        // dashes with gaps, like words
        for (var t = 0; t < 3; t++) {
          final dx = x - w / 2, dy = y + t - h / 2;
          final px = (w / 2 + dx * c - dy * s).round();
          final py = (h / 2 + dx * s + dy * c).round();
          if (px >= 0 && px < w && py >= 0 && py < h) data[py * w + px] = 0;
        }
      }
    }
  }
  return Luma(w, h, data);
}

void main() {
  group('finding the tilt', () {
    test('a level page needs no turning', () {
      expect(estimateSkewDegrees(page()), 0);
    });

    test(
      'a page turned clockwise is turned back anticlockwise by the same amount',
      () {
        for (final d in [3.0, 5.0, 8.0, 12.0]) {
          expect(
            estimateSkewDegrees(page(degrees: d)),
            closeTo(-d, 0.7),
            reason: '$d',
          );
        }
      },
    );

    test('and one turned anticlockwise is turned back clockwise', () {
      for (final d in [-3.0, -6.0, -10.0]) {
        expect(
          estimateSkewDegrees(page(degrees: d)),
          closeTo(-d, 0.7),
          reason: '$d',
        );
      }
    });

    test('no ink, or a flat picture, is level', () {
      final blank = Luma(100, 100, Uint8List(10000)..fillRange(0, 10000, 255));
      expect(estimateSkewDegrees(blank), 0);
      final grey = Luma(100, 100, Uint8List(10000)..fillRange(0, 10000, 128));
      expect(estimateSkewDegrees(grey), 0);
    });

    test('the answer is never more than the most it is allowed to say', () {
      expect(
        estimateSkewDegrees(page(degrees: 14), max: 5).abs(),
        lessThanOrEqualTo(5),
      );
    });
  });

  group('finding the text', () {
    test('the box is where the ink is, with a margin', () {
      final b = textBounds(page(), 0);
      expect(b.left, closeTo(30 / 300 - 0.02, 0.03));
      expect(b.right, closeTo(270 / 300 + 0.02, 0.03));
      expect(b.top, closeTo(60 / 400 - 0.02, 0.03));
      expect(b.bottom, closeTo((60 + 8 * 36) / 400 + 0.02, 0.04));
    });

    test('a picture with no ink is kept whole', () {
      final blank = Luma(100, 100, Uint8List(10000)..fillRange(0, 10000, 255));
      expect(textBounds(blank, 0), const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('the box stays inside the picture', () {
      final b = textBounds(
        page(left: 0, right: 300, top: 0, lines: 11),
        0,
        margin: 0.2,
      );
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.top, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(1));
      expect(b.bottom, lessThanOrEqualTo(1));
    });

    test(
      'a crop is kept inside the picture and not smaller than a tenth of it',
      () {
        final c = clampCrop(const Rect.fromLTRB(-1, -1, 0.02, 0.02));
        expect(c.left, 0);
        expect(c.width, greaterThanOrEqualTo(0.1));
        final d = clampCrop(const Rect.fromLTRB(0.5, 0.5, 5, 5));
        expect(d.right, 1);
        expect(d.bottom, 1);
      },
    );
  });

  group('the real picture work', () {
    test('a tilted page picture is analysed and made into a straighter, cropped one', () async {
      final dir = Directory.systemTemp.createTempSync('tippani_adjust');
      addTearDown(() => dir.deleteSync(recursive: true));
      // draw a tilted page of lines with the phone's own canvas, as a PNG file
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 300, 400),
        ui.Paint()..color = Colors.white,
      );
      canvas.translate(150, 200);
      canvas.rotate(6 * math.pi / 180);
      canvas.translate(-150, -200);
      final ink = ui.Paint()..color = Colors.black;
      for (var i = 0; i < 9; i++) {
        for (var x = 30.0; x < 270; x += 6) {
          canvas.drawRect(Rect.fromLTWH(x, 60.0 + i * 36, 3, 3), ink);
        }
      }
      final img = await rec.endRecording().toImage(300, 400);
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('${dir.path}/page.png')
        ..writeAsBytesSync(bytes.buffer.asUint8List());

      final adjuster = DevicePageAdjuster(outDir: dir);
      final g = await adjuster.analyse(file.path);
      expect(g.angle, closeTo(-6, 1.2));
      expect(g.width / g.height, closeTo(0.75, 0.01));
      expect(g.crop.width, lessThan(1));

      final out = await adjuster.render(file.path, g.angle, g.crop);
      final raw = File(out).readAsBytesSync();
      expect(raw.sublist(1, 4), [0x50, 0x4e, 0x47]);
      final codec = await ui.instantiateImageCodec(raw);
      final made = (await codec.getNextFrame()).image;
      expect(made.width, closeTo(g.crop.width * 300, 2));
      expect(made.height, closeTo(g.crop.height * 400, 2));
    });
  });

  group('the adjust screen', () {
    late _Adjuster adjuster;
    String? popped;
    var opened = false;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      adjuster = _Adjuster();
      popped = null;
      opened = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => AdjustScreen(
                        imagePath: '/no/page.jpg',
                        adjuster: adjuster,
                      ),
                    ),
                  );
                  opened = false;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts from what the app worked out', (tester) async {
      await open(tester);
      expect(find.text('Turned -2.5°'), findsOneWidget);
      expect(adjuster.analysed, ['/no/page.jpg']);
    });

    testWidgets(
      'the nudge buttons and the slider turn it, within 15 degrees either way',
      (tester) async {
        await open(tester);
        await tester.tap(find.byTooltip('Turn clockwise'));
        await tester.pump();
        expect(find.text('Turned -2.0°'), findsOneWidget);
        await tester.tap(find.byTooltip('Turn anticlockwise'));
        await tester.tap(find.byTooltip('Turn anticlockwise'));
        await tester.pump();
        expect(find.text('Turned -3.0°'), findsOneWidget);
        await tester.drag(find.byType(Slider), const Offset(2000, 0));
        await tester.pump();
        expect(find.text('Turned 15.0°'), findsOneWidget);
      },
    );

    testWidgets(
      'Reset turns it to none and keeps the whole picture; Auto brings back the guess',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Reset'));
        await tester.pump();
        expect(find.text('Turned 0.0°'), findsOneWidget);
        await tester.tap(find.text('Use this'));
        await tester.pumpAndSettle();
        expect(adjuster.rendered.single.$2, 0);
        expect(adjuster.rendered.single.$3, const Rect.fromLTRB(0, 0, 1, 1));
      },
    );

    testWidgets('Auto puts back what the app guessed', (tester) async {
      await open(tester);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();
      expect(find.text('Turned -2.5°'), findsOneWidget);
      expect(adjuster.analysed, hasLength(2));
    });

    testWidgets('dragging a corner of the frame changes what is kept', (
      tester,
    ) async {
      await open(tester);
      await tester.drag(find.byKey(const Key('crop-tl')), const Offset(40, 40));
      await tester.pump();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      final crop = adjuster.rendered.single.$3;
      expect(crop.left, greaterThan(0.1));
      expect(crop.top, greaterThan(0.1));
      expect(crop.right, 0.95);
    });

    testWidgets(
      'Use this hands back the new picture, made with the angle and the frame shown',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Use this'));
        await tester.pumpAndSettle();
        expect(adjuster.rendered.single.$2, -2.5);
        expect(
          adjuster.rendered.single.$3,
          const Rect.fromLTRB(0.1, 0.1, 0.95, 0.9),
        );
        expect(popped, '/made/page.png');
        expect(opened, isFalse);
      },
    );

    testWidgets('Use as is hands back the original, unchanged', (tester) async {
      await open(tester);
      await tester.tap(find.text('Use as is'));
      await tester.pumpAndSettle();
      expect(popped, '/no/page.jpg');
      expect(adjuster.rendered, isEmpty);
    });

    testWidgets(
      'a picture that cannot be looked at can still be used as it is',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        adjuster = _Adjuster()..failAnalyse = true;
        await tester.pumpWidget(
          MaterialApp(
            home: AdjustScreen(imagePath: '/no/page.jpg', adjuster: adjuster),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be looked at'), findsOneWidget);
        expect(find.text('Use this'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Use as is'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('a picture that cannot be made is said, and the screen stays', (
      tester,
    ) async {
      await open(tester);
      adjuster.failRender = true;
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be adjusted'), findsOneWidget);
      expect(popped, isNull);
      expect(find.text('Use this'), findsOneWidget);
    });
  });

  group('reading a page after adjusting it', () {
    testWidgets('what is adjusted is what is read', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final adjuster = _Adjuster();
      final reader = _Reader();
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureScreen(
            photos: _Photos(),
            recogniser: reader,
            adjuster: adjuster,
          ),
        ),
      );
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(reader.read1.single, '/made/page.png');
      expect(find.text('Hello there.'), findsOneWidget);
    });

    testWidgets('backing out of the adjusting reads nothing', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final reader = _Reader();
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureScreen(
            photos: _Photos(),
            recogniser: reader,
            adjuster: _Adjuster(),
          ),
        ),
      );
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(reader.read1, isEmpty);
    });

    testWidgets('Use as is reads the picture as it was taken', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final reader = _Reader();
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureScreen(
            photos: _Photos(),
            recogniser: reader,
            adjuster: _Adjuster(),
          ),
        ),
      );
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as is'));
      await tester.pumpAndSettle();
      expect(reader.read1.single, '/no/page.jpg');
    });
  });
}

class _Adjuster implements PageAdjuster {
  final analysed = <String>[];
  final rendered = <(String, double, Rect)>[];
  bool failAnalyse = false;
  bool failRender = false;

  @override
  Future<PageGuess> analyse(String path) async {
    analysed.add(path);
    if (failAnalyse) throw Exception('no pixels');
    return const PageGuess(
      width: 300,
      height: 400,
      angle: -2.5,
      crop: Rect.fromLTRB(0.1, 0.1, 0.95, 0.9),
    );
  }

  @override
  Future<String> render(String path, double angle, Rect crop) async {
    if (failRender) throw Exception('no canvas');
    rendered.add((path, angle, crop));
    return '/made/page.png';
  }
}

class _Photos implements PhotoSource {
  @override
  Future<String?> take() async => '/no/page.jpg';
  @override
  Future<String?> choose() async => null;
}

class _Reader implements TextRecogniser {
  final read1 = <String>[];
  @override
  Future<String> hocr(String imagePath, String language) async => '';

  @override
  Future<String> read(String imagePath, String language) async {
    read1.add(imagePath);
    return 'Hello there.';
  }
}
