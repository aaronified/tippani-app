import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/screens/read_aloud_settings_screen.dart';
import 'package:tippani/speech/speaker.dart';
import 'package:tippani/speech/speech_settings.dart';

SpeechVoice v(
  String name,
  String locale, {
  int quality = 2,
  bool net = false,
  bool installed = true,
}) => SpeechVoice(
  name: name,
  locale: locale,
  quality: quality,
  networkRequired: net,
  installed: installed,
);

class _Speaker implements Speaker {
  _Speaker(this.all);
  final List<SpeechVoice> all;
  final said = <(String, String)>[];
  int stops = 0;

  @override
  Future<List<SpeechVoice>> voices() async => all;

  @override
  Future<bool> speak(String text, String language) async {
    said.add((text, language));
    return true;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('choosing a voice', () {
    final all = [
      v('en-local', 'en-US', quality: 2),
      v('en-best-local', 'en-US', quality: 3),
      v('en-net', 'en-US', quality: 3, net: true),
      v('en-gb', 'en-GB', quality: 4),
      v('en-missing', 'en-US', quality: 4, installed: false),
      v('hi-1', 'hi-IN', quality: 2),
    ];

    test('automatic takes the highest quality installed for the language', () {
      expect(chooseVoice(all, 'en', const SpeechPrefs())!.name, 'en-gb');
    });

    test('at equal quality an online voice beats one on the phone', () {
      final two = [
        v('local', 'en-US', quality: 3),
        v('net', 'en-US', quality: 3, net: true),
      ];
      expect(chooseVoice(two, 'en', const SpeechPrefs())!.name, 'net');
    });

    test('a voice that is not installed is never chosen', () {
      expect(
        chooseVoice(
          [v('gone', 'en-US', quality: 4, installed: false)],
          'en',
          const SpeechPrefs(),
        ),
        isNull,
      );
    });

    test('the language is matched by its first part, in either spelling', () {
      expect(chooseVoice(all, 'hi', const SpeechPrefs())!.name, 'hi-1');
      expect(chooseVoice(all, 'hi_IN', const SpeechPrefs())!.name, 'hi-1');
    });

    test(
      'no voice for the language, or no language asked for, leaves the default',
      () {
        expect(chooseVoice(all, 'fr', const SpeechPrefs()), isNull);
        expect(chooseVoice(all, '', const SpeechPrefs()), isNull);
      },
    );

    test('the reader\'s pick is used for its own language, and only that', () {
      const prefs = SpeechPrefs(voiceName: 'en-local', voiceLocale: 'en-US');
      expect(chooseVoice(all, 'en', prefs)!.name, 'en-local');
      expect(chooseVoice(all, '', prefs)!.name, 'en-local');
      expect(chooseVoice(all, 'hi', prefs)!.name, 'hi-1');
    });

    test('a pick that has since gone falls back to the best', () {
      const prefs = SpeechPrefs(voiceName: 'removed', voiceLocale: 'en-US');
      expect(chooseVoice(all, 'en', prefs)!.name, 'en-gb');
    });

    test(
      'Android\'s voice map is read: quality, online, and not installed',
      () {
        final s = SpeechVoice.fromMap({
          'name': 'x',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '1',
          'features': 'a\tnotInstalled',
        });
        expect(s.quality, 4);
        expect(s.networkRequired, isTrue);
        expect(s.installed, isFalse);
        expect(s.description, 'very high quality · online');
      },
    );
  });

  group('the Read aloud settings', () {
    late _Speaker speaker;
    late SpeechSettings settings;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      speaker = _Speaker([
        v('en-net', 'en-US', quality: 3, net: true),
        v('en-local', 'en-US'),
        v('hi-1', 'hi-IN'),
      ]);
      SharedPreferences.setMockInitialValues({});
      settings = SpeechSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadAloudSettingsScreen(speaker: speaker, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the voices of one language, the best first', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('en-US · en-net'), findsOneWidget);
      expect(find.textContaining('hi-IN'), findsNothing);
      expect(
        tester.getTopLeft(find.textContaining('en-net')).dy,
        lessThan(tester.getTopLeft(find.textContaining('en-local')).dy),
      );
      expect(find.text('high quality · online'), findsOneWidget);
    });

    testWidgets('choosing a voice keeps it, and Automatic clears it', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.textContaining('en-local'));
      await tester.pumpAndSettle();
      expect(settings.prefs.voiceName, 'en-local');
      expect(settings.prefs.voiceLocale, 'en-US');
      await tester.tap(find.text('Automatic'));
      await tester.pumpAndSettle();
      expect(settings.prefs.voiceName, isNull);
    });

    testWidgets('speed and pitch are kept', (tester) async {
      await open(tester);
      await tester.drag(find.byType(Slider).first, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(settings.prefs.rate, greaterThan(0.5));
    });

    testWidgets('Try this voice speaks a sample in the shown language', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Try this voice'));
      await tester.pumpAndSettle();
      expect(speaker.said.single.$2, 'en');
    });
  });
}
