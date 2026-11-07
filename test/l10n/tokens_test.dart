import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/l10n/l10n.dart';
import 'package:tippani/l10n/locale_file.dart';

/// The app's words are tokens, in English and Bengali. These tests keep it that way: every token a screen asks for
/// exists in both languages, the generated English table is current, and no screen carries English of its own.
void main() {
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  final serverEn = parseLocale(read('assets/l10n/en.txt')).keys;
  final serverBn = parseLocale(read('assets/l10n/bn.txt')).keys;
  final appEn = parseLocale(read('assets/l10n/app.en.txt')).keys;
  final appBn = parseLocale(read('assets/l10n/app.bn.txt')).keys;

  const one = r"""(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""";
  // tr('token' ...), context.tr('token' ...), tx('token' ...)
  final call = RegExp('\\b(?:tr|tx|tok)\\(\\s*($one)');
  // trn('base' ...) is the tokens base.one and base.other; countWords('noun' ...) is app.count.noun.one / .other
  final plural = RegExp('\\btrn\\(\\s*($one)');
  final counted = RegExp('\\bcountWords\\(\\s*($one)');
  String unquote(String lit) => lit
      .substring(1, lit.length - 1)
      .replaceAll("\\'", "'")
      .replaceAll('\\"', '"');

  List<File> sources() => [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.replaceAll('\\', '/').contains('lib/l10n/'))
        f,
  ];

  test(
    'a token can travel as a string with its values, and a screen opens it',
    () {
      final l = L10n(deviceLanguage: 'en');
      final msg = tok('settings.changed.count', {'n': 4});
      expect(l.tr(msg), '4 changed');
      // words that are not a token (the server's own) come back as they are
      expect(l.tr('The server said no.'), 'The server said no.');
      expect(tok('common.action.copy.label'), 'common.action.copy.label');
    },
  );

  test('the generated English table is current', () {
    final fresh = englishTable(
      read('assets/l10n/en.txt'),
      read('assets/l10n/app.en.txt'),
    );
    expect(
      read('lib/l10n/english.g.dart'),
      fresh,
      reason: 'run: dart run tool/gen_l10n.dart',
    );
  });

  test('every token a screen asks for has English and Bengali', () {
    final asked = <String, String>{};
    for (final f in sources()) {
      final text = f.readAsStringSync();
      for (final m in call.allMatches(text)) {
        asked.putIfAbsent(unquote(m.group(1)!), () => f.path);
      }
      for (final m in plural.allMatches(text)) {
        final base = unquote(m.group(1)!);
        asked.putIfAbsent('$base.one', () => f.path);
        asked.putIfAbsent('$base.other', () => f.path);
      }
      for (final m in counted.allMatches(text)) {
        final noun = unquote(m.group(1)!).replaceAll(' ', '_');
        asked.putIfAbsent('app.count.$noun.one', () => f.path);
        asked.putIfAbsent('app.count.$noun.other', () => f.path);
      }
    }
    expect(asked.length, greaterThan(300), reason: 'the scan found the calls');

    final english = {...serverEn, ...appEn};
    final bengali = {...serverBn, ...appBn};
    final notTokens = [
      for (final e in asked.entries)
        if (e.key.contains(' ') || !e.key.contains('.'))
          '${e.key} (${e.value})',
    ]..sort();
    expect(
      notTokens,
      isEmpty,
      reason: 'English where a token belongs: $notTokens',
    );
    final noEnglish = [
      for (final t in asked.keys)
        if (!english.containsKey(t)) t,
    ]..sort();
    expect(noEnglish, isEmpty, reason: 'no English for: $noEnglish');
    final noBengali = [
      for (final t in asked.keys)
        if (!bengali.containsKey(t)) t,
    ]..sort();
    expect(noBengali, isEmpty, reason: 'no Bengali for: $noBengali');
  });

  test('the app\'s own files agree token for token', () {
    final onlyEn = [
      for (final t in appEn.keys)
        if (!appBn.containsKey(t)) t,
    ];
    // app.bn.txt may also carry Bengali for web tokens whose own bn.txt has no line
    final onlyBn = [
      for (final t in appBn.keys)
        if (!appEn.containsKey(t) && !serverEn.containsKey(t)) t,
    ];
    expect(onlyEn, isEmpty, reason: 'English with no Bengali: $onlyEn');
    expect(onlyBn, isEmpty, reason: 'Bengali with no English: $onlyBn');
    expect(
      appEn.keys.where((k) => !k.startsWith('app.')),
      isEmpty,
      reason: 'the app\'s tokens start with app.',
    );
    final clash = appEn.keys.where(serverEn.containsKey).toList();
    expect(clash, isEmpty, reason: 'the web already has: $clash');
  });

  test('a {place} in the English is in the Bengali too', () {
    final places = RegExp(r'\{[a-z_0-9]+\}');
    final bad = <String>[];
    final english = {...serverEn, ...appEn};
    final bengali = {...serverBn, ...appBn};
    for (final e in english.entries) {
      final b = bengali[e.key];
      if (b == null) continue;
      final want = places.allMatches(e.value).map((m) => m.group(0)).toSet();
      final got = places.allMatches(b).map((m) => m.group(0)).toSet();
      if (want.difference(got).isNotEmpty) bad.add(e.key);
    }
    expect(bad, isEmpty, reason: 'places missing in Bengali for: $bad');
  });

  test('no screen carries English of its own', () {
    // A string literal handed straight to a widget as words. Symbols, numbers and brand names are fine.
    final words = RegExp(r'[A-Za-z]{3,}');
    final widgetWords = RegExp(
      "(?:\\bText\\(\\s*|\\b(?:labelText|hintText|helperText|errorText|tooltip|semanticLabel|semanticsLabel|counterText|title|hint|label|subtitle|message|description)\\s*:\\s*)(?:const\\s+)?($one)",
    );
    const allowed = {'Tippani'};
    final found = <String>[];
    for (final f in sources()) {
      final text = f.readAsStringSync();
      for (final m in widgetWords.allMatches(text)) {
        final v = unquote(m.group(1)!);
        if (allowed.contains(v) || !words.hasMatch(v)) continue;
        if (v.contains(r'$')) continue; // built from variables: checked by hand
        found.add('${f.path}: $v');
      }
    }
    expect(found, isEmpty, reason: 'English in a widget:\n${found.join('\n')}');
  });
}
