import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/screens/materials_screen.dart';
import 'package:tippani/theme/material_surface.dart';
import 'package:tippani/theme/materials.dart';

import '../account/account_test.dart' show Rig, rig;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the materials', () {
    test('every material a set or a pick can name has its tile, its dials and a name', () {
      for (final e in textiles.entries) {
        expect(factoryPhys.containsKey(e.key), isTrue, reason: e.key);
        if (e.value.isFlat) continue;
        expect(
          File('assets/textures/${e.value.file}').existsSync(),
          isTrue,
          reason: '${e.key} needs ${e.value.file} in the app',
        );
      }
      for (final set in materialSets.entries) {
        expect(set.value, hasLength(slots.length), reason: set.key);
        for (final n in set.value) {
          expect(textiles.containsKey(n), isTrue, reason: '${set.key}: $n');
        }
      }
    });

    test('a phone that has not heard from the server has no material', () {
      final look = MaterialLook.fromPrefs(ServerPrefs.empty);
      expect(look.hasMaterial, isFalse);
    });

    test('the account\'s set is worn, and a slot the reader changed wins', () {
      final look = MaterialLook.fromPrefs(
        ServerPrefs({'materialSet': 'quarry', 'tileCard': 'walnut'}),
      );
      expect(look.tileFor('ground'), 'sandstone');
      expect(look.tileFor('card'), 'walnut');
    });

    test('an account with no set wears Manuscript, and an unknown tile is the set\'s own', () {
      final look = MaterialLook.fromPrefs(
        ServerPrefs({'sizeUi': 100, 'tileCover': 'unobtainium'}),
      );
      expect(look.set, 'manuscript');
      expect(look.tileFor('cover'), 'wood');
    });

    test(
      'the reader\'s dial edits sit over the factory\'s, material by material',
      () {
        final look = MaterialLook.fromPrefs(
          ServerPrefs({
            'materialSet': 'manuscript',
            'texTweak': '{"paper":{"hard":90}}',
          }),
        );
        expect(look.physFor('paper').hard, 90);
        expect(look.physFor('paper').sss, factoryPhys['paper']!.sss);
        expect(look.physFor('wood'), factoryPhys['wood']);
      },
    );

    test('a malformed edit is the factory\'s, not an error', () {
      expect(parseTweaks('not json'), isEmpty);
      expect(parseTweaks('{"paper":{"hard":900}}'), isEmpty);
    });

    test('saving an edit keeps the web\'s glass dials and writes only what differs', () {
      const raw = '{"glass":{"clarity":250},"paper":{"hard":90}}';
      final next = editedTweaks(raw, 'wood', {'hard': 10, 'sss': 22});
      expect(next, contains('"clarity":250'));
      expect(next, contains('"paper":{"hard":90}'));
      // sss 22 is wood's own, so only hard is stored
      expect(next, contains('"wood":{"hard":10}'));
    });

    test('putting a material back removes its edits and nothing else', () {
      const raw = '{"glass":{"clarity":250},"paper":{"hard":90}}';
      expect(editedTweaks(raw, 'paper', null), '{"glass":{"clarity":250}}');
      expect(editedTweaks('{"paper":{"hard":90}}', 'paper', null), '');
    });
  });

  group('a surface', () {
    Future<List<int>> sample(
      WidgetTester tester,
      MaterialLook look, {
      Brightness brightness = Brightness.light,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 300,
                height: 300,
                child: MaterialSurface(
                  slot: 'card',
                  color: const Color(0xFF808080),
                  look: look,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final t in textiles.values) {
          await TileCache.load(t.file, _FileBundle());
        }
      });
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 300,
                height: 300,
                child: MaterialSurface(
                  slot: 'card',
                  color: const Color(0xFF808080),
                  look: look,
                ),
              ),
            ),
          ),
        ),
      );
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage();
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      });
      return [for (var i = 0; i < bytes!.length; i += 4) bytes[i]];
    }

    int spread(List<int> reds) {
      var lo = 255, hi = 0;
      for (final r in reds) {
        if (r < lo) lo = r;
        if (r > hi) hi = r;
      }
      return hi - lo;
    }

    testWidgets('with no material is one flat colour', (tester) async {
      final reds = await sample(
        tester,
        const MaterialLook(set: 'atrium', overrides: {}, tweaks: {}),
      );
      expect(spread(reds), 0);
    });

    // A highlight is a smooth ramp and never differs by more than a level between neighbours; grain does.
    int jumps(List<int> reds) {
      var n = 0;
      for (var i = 1; i < reds.length; i++) {
        if ((reds[i] - reds[i - 1]).abs() >= 2) n++;
      }
      return n;
    }

    testWidgets('on a material shows its grain', (tester) async {
      final reds = await sample(
        tester,
        const MaterialLook(
          set: 'quarry',
          overrides: {'card': 'granite'},
          tweaks: {},
        ),
      );
      expect(jumps(reds), greaterThan(500));
    });

    testWidgets('draws every material, in light and dark, without error', (
      tester,
    ) async {
      for (final name in pickableTextiles) {
        for (final b in Brightness.values) {
          await sample(
            tester,
            MaterialLook(
              set: 'atrium',
              overrides: {'card': name},
              tweaks: const {},
            ),
            brightness: b,
          );
        }
      }
    });
  });

  group('the materials screen', () {
    Future<(Rig, Widget)> app(
      WidgetTester tester, [
      Map<String, Object?>? prefs,
    ]) async {
      final r = (await tester.runAsync(rig))!;
      r.server.prefs.addAll(prefs ?? {'materialSet': 'manuscript'});
      await tester.runAsync(r.prefs.refresh);
      return (
        r,
        PrefsScope(
          source: r.prefs,
          child: const MaterialApp(home: MaterialsScreen()),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('choosing a set saves it to the account', (tester) async {
      final (r, widget) = await app(tester);
      await tester.pumpWidget(widget);
      await tester.tap(find.byKey(const ValueKey('material-set')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bindery'));
      await settle(tester);
      expect(r.server.prefWrites.last, {'materialSet': 'bindery'});
    });

    testWidgets('changing one surface saves only that slot', (tester) async {
      final (r, widget) = await app(tester);
      await tester.pumpWidget(widget);
      await tester.ensureVisible(find.byKey(const ValueKey('slot-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-card')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Marble'),
        find.byType(SingleChildScrollView).last,
        const Offset(0, -200),
      );
      await tester.tap(find.text('Marble'));
      await settle(tester);
      expect(r.server.prefWrites.last, {'tileCard': 'marble'});
    });

    testWidgets('taking the set\'s own back saves an empty slot', (
      tester,
    ) async {
      final (r, widget) = await app(tester, {
        'materialSet': 'manuscript',
        'tileCard': 'marble',
      });
      await tester.pumpWidget(widget);
      await tester.ensureVisible(find.byKey(const ValueKey('slot-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-card')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(RadioListTile<String>),
          matching: find.textContaining('The set\'s own'),
        ),
      );
      await settle(tester);
      expect(r.server.prefWrites.last, {'tileCard': ''});
    });

    testWidgets('moving a dial saves it, and the glass dials survive', (
      tester,
    ) async {
      final (r, widget) = await app(tester, {
        'materialSet': 'manuscript',
        'texTweak': '{"glass":{"clarity":250}}',
      });
      await tester.pumpWidget(widget);
      final slider = find.byKey(const ValueKey('dial-paper-hard'));
      await tester.scrollUntilVisible(slider, 200);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(60, 0));
      await settle(tester);
      final saved = r.server.prefWrites.last['texTweak']! as String;
      expect(saved, contains('"clarity":250'));
      expect(saved, contains('"paper":{"hard":'));
    });

    testWidgets('a material offers its reset only after it was edited', (
      tester,
    ) async {
      final (r, widget) = await app(tester, {
        'materialSet': 'manuscript',
        'texTweak': '{"paper":{"hard":90}}',
      });
      await tester.pumpWidget(widget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reset-paper')),
        200,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('reset-paper')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reset-wood')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reset-paper')));
      await settle(tester);
      expect(r.server.prefWrites.last, {'texTweak': ''});
    });

    testWidgets('Atrium has no dials to offer', (tester) async {
      final (_, widget) = await app(tester, {'materialSet': 'atrium'});
      await tester.pumpWidget(widget);
      await tester.scrollUntilVisible(
        find.textContaining('nothing here to change'),
        200,
      );
      expect(find.byType(Slider), findsNothing);
    });
  });
}

/// Reads the real tiles from the project folder, since a test has no asset bundle of its own.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final f = File(key);
    if (!f.existsSync()) throw FlutterError('no $key');
    return ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()));
  }
}
