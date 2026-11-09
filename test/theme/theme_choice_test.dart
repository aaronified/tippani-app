import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/screens/theme_colours_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/theme/theme_choice.dart';

Future<SettingsStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
}

void main() {
  final lightDyn = ColorScheme.fromSeed(seedColor: const Color(0xFF00AA55));
  final darkDyn = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00AA55),
    brightness: Brightness.dark,
  );

  test(
    'the phone\'s own colours are the start, and are used where it has them',
    () async {
      final c = ThemeChoice(await _store());
      expect(c.source, 'system');
      final (light, dark) = c.schemes(lightDyn, darkDyn);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(
        light.primary,
        isNot(ColorScheme.fromSeed(seedColor: tippaniSeed).primary),
      );
    },
  );

  test('without the phone\'s colours, Tippani\'s red stands in', () async {
    final c = ThemeChoice(await _store());
    final (light, _) = c.schemes(null, null);
    expect(light.primary, ColorScheme.fromSeed(seedColor: tippaniSeed).primary);
  });

  test('a palette replaces the phone\'s colours and is remembered', () async {
    final store = await _store();
    final c = ThemeChoice(store);
    await c.choose('teal');
    final (light, _) = c.schemes(lightDyn, darkDyn);
    expect(
      light.primary,
      ColorScheme.fromSeed(seedColor: ThemeChoice.palettes['teal']!).primary,
    );
    expect(ThemeChoice(store).source, 'teal');
  });

  test('the photo choice waits for a photo, then keeps its colour', () async {
    final store = await _store();
    final c = ThemeChoice(store);
    await c.choose('photo');
    expect(c.source, 'system', reason: 'there is no photo yet');
    await c.useSeed(const Color(0xFF123456));
    expect(c.source, 'photo');
    final again = ThemeChoice(store);
    expect(again.source, 'photo');
    expect(again.photoSeed, const Color(0xFF123456));
  });

  test('a name that is not a choice is ignored', () async {
    final c = ThemeChoice(await _store());
    await c.choose('neon');
    expect(c.source, 'system');
  });

  testWidgets('the screen lists the choices and a press changes the colours', (
    tester,
  ) async {
    final c = ThemeChoice(await _store());
    await tester.pumpWidget(MaterialApp(home: ThemeColoursScreen(choice: c)));
    expect(find.text('Material You'), findsOneWidget);
    expect(find.text('From a photo'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Forest'), 200);
    await tester.tap(find.text('Forest'));
    await tester.pump();
    expect(c.source, 'forest');
  });
}
