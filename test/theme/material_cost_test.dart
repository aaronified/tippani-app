// What a material costs to draw and to keep up to date (ADR-0028). The owner's report was "the app stutters a lot", from
// the day textures and the synced theme arrived, and a phone is not here to measure on, so this measures what a test can:
// the draw operations a paint records, the layers and shaders it makes, how often a surface is composed, and how many
// cards are rebuilt by a preference that has nothing to do with how they look.
//
// This file knows the machinery, because the cost IS the machinery and nothing on a screen shows it: `MaterialPainter`
// and what its `paint` records on a canvas, `SurfaceImages` (the composed surfaces, its byte budget and its `composed`
// counter), `MaterialPainter.debugPaints`, `ThemeMemo.builds`, and the rebuilds Flutter reports for `SurfaceCard` and
// `QuoteTile`. The look of the result stays with `materials_test.dart`, which draws real pixels.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/harness/harness.dart' show SystemBackupPicker;
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_widgets.dart';
import 'package:tippani/screens/quote_menu.dart';
import 'package:tippani/theme/app_theme.dart';
import 'package:tippani/theme/material_surface.dart';
import 'package:tippani/theme/materials.dart';
import 'package:tippani/theme/theme_choice.dart';

import '../account/account_test.dart' show Rig, rig;
import '../support/memory_library.dart';

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final f = File(key);
    if (!f.existsSync()) throw FlutterError('no $key');
    return ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()));
  }
}

Quote _quote(int i) => Quote(
  id: i,
  workId: 1,
  text: 'You are going to need a bigger boat, number $i.',
  translation: '',
  language: '',
  speaker: '',
  chapter: '',
  location: '',
  note: '',
  color: 'blue',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

final _work = Work(
  id: 1,
  kind: WorkKind.film,
  title: 'Jaws',
  creator: 'S',
  year: 1975,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const _drawOps = {
  'drawRect',
  'drawRRect',
  'drawDRRect',
  'drawImage',
  'drawImageRect',
  'drawPath',
  'drawPaint',
  'drawCircle',
};

class _Recorded {
  int draws = 0, layers = 0, shaders = 0;
}

/// What one paint of [name] puts on the canvas it is handed.
_Recorded _paintOnce(
  String name,
  Size size, {
  Color color = Colors.grey,
  BorderRadius radius = const BorderRadius.all(Radius.circular(20)),
}) {
  final t = textiles[name]!;
  final painter = MaterialPainter(
    color: color,
    accent: Colors.red,
    name: name,
    textile: t,
    phys: factoryPhys[name]!,
    dark: false,
    tile: TileCache.peek(t.file),
    radius: radius,
  );
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, size);
  final r = _Recorded();
  for (final i in canvas.invocations) {
    final m = i.invocation.memberName.toString();
    if (m == 'Symbol("saveLayer")') r.layers++;
    if (_drawOps.any((d) => m == 'Symbol("$d")')) r.draws++;
    for (final a in i.invocation.positionalArguments) {
      if (a is Paint && a.shader != null) r.shaders++;
    }
  }
  return r;
}

Future<void> _loadTiles(WidgetTester tester) => tester.runAsync(() async {
  for (final t in textiles.values) {
    await TileCache.load(t.file, _FileBundle());
  }
});

Widget _list(Rig r, {int count = 60}) => PrefsScope(
  source: r.prefs,
  child: DerivedPrefsScopes(
    child: MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: count,
          itemBuilder: (c, i) => QuoteTile(
            quote: _quote(i),
            work: _work,
            onTap: () {},
            onFavourite: () {},
            menu: QuoteMenu(
              store: MemoryLibrary(),
              quote: _quote(i),
              picker: const SystemBackupPicker(),
              onChanged: () {},
              work: _work,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Rig> _rigWith(WidgetTester tester, Map<String, Object?> prefs) async {
  final r = (await tester.runAsync(rig))!;
  r.server.prefs.addAll(prefs);
  await tester.runAsync(r.prefs.refresh);
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SurfaceImages.clear);

  group('a surface that has been drawn once', () {
    testWidgets(
      'costs one image draw on every paint after, under every material: no layer, no shader, nothing composed again',
      (tester) async {
        await _loadTiles(tester);
        for (final name in pickableTextiles) {
          SurfaceImages.clear();
          const size = Size(360, 200);
          _paintOnce(name, size); // the first paint composes it
          final composedAfterFirst = SurfaceImages.composed;
          expect(composedAfterFirst, 1, reason: '$name composes once');
          final again = _paintOnce(name, size);
          expect(again.layers, 0, reason: '$name saves no layer');
          expect(again.shaders, 0, reason: '$name makes no shader');
          // a flat card is one fill; a material may cost at most two operations more than that
          expect(again.draws, lessThanOrEqualTo(1 + 2), reason: name);
          expect(
            SurfaceImages.composed,
            composedAfterFirst,
            reason: '$name is not composed a second time',
          );
        }
      },
    );

    testWidgets(
      'is composed again when something it is drawn with changed, and not before',
      (tester) async {
        await _loadTiles(tester);
        const size = Size(360, 200);
        _paintOnce('paper', size);
        _paintOnce('paper', size);
        expect(SurfaceImages.composed, 1);
        _paintOnce('paper', size, color: Colors.teal);
        expect(SurfaceImages.composed, 2, reason: 'another colour');
        _paintOnce('paper', const Size(360, 240));
        expect(SurfaceImages.composed, 3, reason: 'another size');
        _paintOnce('wood', size);
        expect(SurfaceImages.composed, 4, reason: 'another material');
      },
    );

    testWidgets(
      'holds no more than its byte budget, the longest unused out first',
      (tester) async {
        await _loadTiles(tester);
        final was = SurfaceImages.budgetBytes;
        addTearDown(() => SurfaceImages.budgetBytes = was);
        SurfaceImages.budgetBytes = 3 * 360 * 200 * 4;
        for (var i = 0; i < 10; i++) {
          _paintOnce('paper', Size(360, 200.0 + i));
        }
        expect(SurfaceImages.held, lessThanOrEqualTo(3));
        // the newest is kept: painting it again composes nothing
        final composed = SurfaceImages.composed;
        _paintOnce('paper', const Size(360, 209));
        expect(SurfaceImages.composed, composed);
      },
    );
  });

  group('a screen of quote cards', () {
    testWidgets(
      'scrolling past sixty of them composes the card material once, not once per card',
      (tester) async {
        await _loadTiles(tester);
        final r = await _rigWith(tester, {
          'materialSet': 'atrium',
          'tileCard': 'marble',
        });
        await tester.pumpWidget(_list(r));
        await tester.pump();
        MaterialPainter.debugPaints = 0;
        for (var i = 0; i < 12; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -700));
          await tester.pump();
        }
        expect(
          MaterialPainter.debugPaints,
          greaterThan(20),
          reason: 'the cards did paint as they came in',
        );
        // every card is the same width and the same height here, so they are one image
        expect(SurfaceImages.composed, lessThanOrEqualTo(2));
      },
    );

    testWidgets(
      'a preference that has nothing to do with surfaces rebuilds no card',
      (tester) async {
        await _loadTiles(tester);
        final r = await _rigWith(tester, {
          'materialSet': 'atrium',
          'tileCard': 'paper',
        });
        var cards = 0, tiles = 0;
        debugOnRebuildDirtyWidget = (e, _) {
          if (e.widget is SurfaceCard) cards++;
          if (e.widget is QuoteTile) tiles++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);
        await tester.pumpWidget(_list(r));
        await tester.pump();
        expect(find.byType(SurfaceCard), findsWidgets);
        cards = 0;
        tiles = 0;
        await tester.runAsync(() => r.prefs.save({'srDaily': 9}));
        await tester.pump();
        expect(cards, 0, reason: 'a review count is not a look');
        expect(tiles, 0);
      },
    );

    testWidgets(
      'a preference that is a look does rebuild them, so the test above is not vacuous',
      (tester) async {
        await _loadTiles(tester);
        final r = await _rigWith(tester, {
          'materialSet': 'atrium',
          'tileCard': 'paper',
        });
        var cards = 0, tiles = 0;
        debugOnRebuildDirtyWidget = (e, _) {
          if (e.widget is SurfaceCard) cards++;
          if (e.widget is QuoteTile) tiles++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);
        await tester.pumpWidget(_list(r));
        await tester.pump();
        cards = 0;
        tiles = 0;
        await tester.runAsync(() => r.prefs.save({'tileCard': 'wood'}));
        await tester.pump();
        expect(cards, greaterThan(0));
        cards = 0;
        await tester.runAsync(() => r.prefs.save({'sizeDisplay': 150}));
        await tester.pump();
        expect(tiles, greaterThan(0), reason: 'a quote size is a reading');
      },
    );

    testWidgets(
      'a change in the phone own settings, such as its text size, rebuilds no surface',
      (tester) async {
        await _loadTiles(tester);
        final r = await _rigWith(tester, {
          'materialSet': 'atrium',
          'tileCard': 'paper',
        });
        var cards = 0;
        debugOnRebuildDirtyWidget = (e, _) {
          if (e.widget is MaterialSurface) cards++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);
        await tester.pumpWidget(_list(r));
        await tester.pump();
        cards = 0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(cards, 0);
      },
    );
  });

  group('the preferences', () {
    test(
      'a sync that brings back what the phone already holds is not announced',
      () async {
        final r = (await rig());
        r.server.prefs.addAll({'materialSet': 'quarry', 'sizeUi': 100});
        await r.prefs.refresh();
        var told = 0;
        r.prefs.addListener(() => told++);
        await r.prefs.refresh();
        await r.prefs.refresh();
        expect(told, 0);
        r.server.prefs['sizeUi'] = 125;
        await r.prefs.refresh();
        expect(told, 1);
        expect(r.prefs.prefs.sizeUi, 125);
      },
    );
  });

  group('the theme', () {
    ThemeChoice choice() => ThemeChoice();
    const look = MaterialLook(set: 'quarry', overrides: {}, tweaks: {});

    test('is built once for as long as what it is made of is equal', () {
      final memo = ThemeMemo();
      final c = choice();
      final a = memo.resolve(c, null, null, look);
      // a preference that is not the theme's arrives: a look equal to the last one, built afresh
      final b = memo.resolve(
        c,
        null,
        null,
        const MaterialLook(set: 'quarry', overrides: {}, tweaks: {}),
      );
      expect(memo.builds, 1);
      expect(identical(a.$1, b.$1), isTrue);
      expect(a.$1 == a.$2, isFalse);
    });

    test(
      'is built again when the colours, the seed or the look changed',
      () async {
        final memo = ThemeMemo();
        final c = choice();
        memo.resolve(c, null, null, look);
        memo.resolve(
          c,
          null,
          null,
          const MaterialLook(set: 'atelier', overrides: {}, tweaks: {}),
        );
        expect(memo.builds, 2, reason: 'the look');
        await c.choose('teal');
        memo.resolve(
          c,
          null,
          null,
          const MaterialLook(set: 'atelier', overrides: {}, tweaks: {}),
        );
        expect(memo.builds, 3, reason: 'the palette');
      },
    );
  });
}
