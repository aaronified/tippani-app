import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/l10n/l10n.dart';

/// Every English line the app asks `tr()` for must have Bengali, from the web's bundled text or the app's own table.
/// Adding a `context.tr('...')` without translating it fails here, which is the point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const one = r"""(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""";
  final call = RegExp('\\btr\\(\\s*($one(?:\\s*$one)*)', dotAll: true);
  final part = RegExp(one);

  String unquote(String lit) => lit
      .substring(1, lit.length - 1)
      .replaceAll("\\'", "'")
      .replaceAll('\\"', '"')
      .replaceAll('\\n', '\n')
      .replaceAll('\\\\', '\\');

  test('every line the app asks for has Bengali', () async {
    final strings = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in call.allMatches(text)) {
        strings.add(
          part.allMatches(m.group(1)!).map((p) => unquote(p.group(0)!)).join(),
        );
      }
    }
    expect(
      strings.length,
      greaterThan(200),
      reason: 'the scan found the calls',
    );

    final l = L10n(deviceLanguage: 'en')..use('bn');
    await l.loaded;
    final untranslated = [
      for (final s in strings)
        if (l.tr(s) == s) s,
    ]..sort();
    expect(untranslated, isEmpty, reason: 'no Bengali for: $untranslated');

    // a {place} in the English must be in the Bengali too, or the value would be dropped
    final places = RegExp(r'\{[a-z]+\}');
    for (final s in strings) {
      final want = places.allMatches(s).map((m) => m.group(0)).toSet();
      final got = places.allMatches(l.tr(s)).map((m) => m.group(0)).toSet();
      expect(got, want, reason: 'places in "$s"');
    }
  });
}
