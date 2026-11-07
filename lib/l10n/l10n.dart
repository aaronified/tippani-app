import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'english.g.dart';
import 'locale_file.dart';

export 'locale_file.dart' show parseLocale;

/// One language the reader can choose for the app's words.
class LocaleChoice {
  const LocaleChoice(this.code, this.name);

  final String code;

  /// The language's own name for itself ("বাংলা").
  final String name;
}

/// The words of the app in the language the reader chose, found by TOKEN, never by the English words:
/// `tr('nav.tab.settings.label')`. The tokens are the server's own (its `en.txt` and `bn.txt`, bundled with the
/// app), plus the app's `app.*` tokens for what the web has no line for (`app.en.txt`, `app.bn.txt`).
///
/// A token is found in this order: the server's text for the chosen language (any file under its Locales folder,
/// which it serves at `/locales`, so a correction made there reaches the phone), then the bundled text for that
/// language, then the language the file names as its `_fallback`, then English. English is compiled in
/// (`english.g.dart`), so it is there the moment the app starts and a token with no Bengali shows its English
/// words, never blank. A token that is nowhere shows as itself, which a test makes impossible to ship.
class L10n extends ChangeNotifier {
  L10n({AssetBundle? bundle, String? deviceLanguage})
    : _bundle = bundle ?? rootBundle,
      _device =
          deviceLanguage ?? ui.PlatformDispatcher.instance.locale.languageCode;

  final AssetBundle _bundle;
  final String _device;

  String _code = 'en';

  /// The language in use ('en', 'bn', or the code of a file the server holds).
  String get code => _code;

  Map<String, String>? _bn; // the bundled Bengali: the web's, then the app's
  // the server's files: code -> keys, and code -> reserved
  final Map<String, Map<String, String>> _files = {};
  final Map<String, Map<String, String>> _filesReserved = {};
  Future<void>? _loading;

  /// The languages on offer: the two the app ships, then any the server holds.
  List<LocaleChoice> get choices => [
    const LocaleChoice('en', 'English'),
    const LocaleChoice('bn', 'বাংলা'),
    for (final e in _filesReserved.entries)
      if (e.key != 'en' && e.key != 'bn')
        LocaleChoice(e.key, e.value['_name'] ?? e.key),
  ];

  /// Chooses the language. '' means the phone's own (Bengali if the phone is set to it, else English).
  void use(String chosen) {
    final want = chosen.isEmpty ? (_device == 'bn' ? 'bn' : 'en') : chosen;
    if (want == _code) return;
    _code = want;
    notifyListeners();
    if (want != 'en') _ensureLoaded();
  }

  /// Takes the files the server serves at `/locales` (`{"files": {"fr": {"keys": {...}, "reserved": {...}}}}`).
  void useServerFiles(Object? payload) {
    if (payload is! Map || payload['files'] is! Map) return;
    _files.clear();
    _filesReserved.clear();
    for (final e in (payload['files'] as Map).entries) {
      final f = e.value;
      if (f is! Map) continue;
      final keys = f['keys'];
      final reserved = f['reserved'];
      _files['${e.key}'] = {
        if (keys is Map)
          for (final k in keys.entries) '${k.key}': '${k.value}',
      };
      _filesReserved['${e.key}'] = {
        if (reserved is Map)
          for (final k in reserved.entries) '${k.key}': '${k.value}',
      };
    }
    if (_code != 'en') _ensureLoaded();
    notifyListeners();
  }

  void _ensureLoaded() {
    _loading ??= _load();
  }

  Future<void> _load() async {
    final bn = <String, String>{};
    for (final f in ['assets/l10n/bn.txt', 'assets/l10n/app.bn.txt']) {
      try {
        final keys = parseLocale(await _bundle.loadString(f)).keys;
        // the app's own file writes a line break as a backslash and n
        bn.addAll(
          f.contains('app.bn')
              ? {for (final e in keys.entries) e.key: unescapeApp(e.value)}
              : keys,
        );
      } on Object {
        // a missing file costs only its lines
      }
    }
    _bn = bn;
    notifyListeners();
  }

  String? _in(String code, String token) =>
      _files[code]?[token] ??
      switch (code) {
        'en' => englishTokens[token],
        'bn' => _bn?[token],
        _ => null,
      };

  String? _lookup(String token) {
    var code = _code;
    final seen = <String>{};
    while (seen.add(code)) {
      final v = _in(code, token);
      if (v != null) return v;
      final back = _filesReserved[code]?['_fallback'];
      if (back == null) break;
      code = back;
    }
    return _in('en', token);
  }

  /// The words for [token] in the chosen language; [args] fill `{name}` places. A message made by [tok] (a token
  /// that travelled as a string, with its values) is opened first. Anything else that is not a token (the server's
  /// own words in an error) comes back as it is.
  String tr(String token, [Map<String, Object?>? args]) {
    final m = openMessage(token);
    if (m != null) return tr(m.$1, {...?m.$2, ...?args});
    return fill(_lookup(token) ?? token, args);
  }

  /// Whether the text is ready (a test waits on this).
  @visibleForTesting
  Future<void> get loaded async => _loading ?? Future<void>.value();
}

const _sep = '\u0001';

/// A token that has to travel as a plain string (an error message from a service, with no screen to translate it
/// yet), with the values for its `{places}`. The screen that shows it passes it through `context.tr`, which opens
/// it. Use this where the words are decided far from the widget; in a widget write `context.tr('token')`.
String tok(String token, [Map<String, Object?>? args]) {
  if (args == null || args.isEmpty) return token;
  final b = StringBuffer(token);
  for (final e in args.entries) {
    b.write('$_sep${e.key}=${e.value}');
  }
  return b.toString();
}

/// The token and values inside a message made by [tok], or null for a plain string.
(String, Map<String, Object?>?)? openMessage(String s) {
  if (!s.contains(_sep)) return null;
  final parts = s.split(_sep);
  final args = <String, Object?>{};
  for (final p in parts.skip(1)) {
    final eq = p.indexOf('=');
    if (eq > 0) args[p.substring(0, eq)] = p.substring(eq + 1);
  }
  return (parts.first, args);
}

/// The [L10n] the running app uses, for code that has no screen to ask (a service that words an error). The app
/// sets it when it starts; a test leaves it empty and gets English.
class Tr {
  static L10n? current;
}

/// The words for [token] in the language the app is in, made right where there is no [BuildContext]: a message a
/// service builds, a label in a function. In a widget write `context.tr('token')` instead, which also follows a
/// change of language while the screen is open. Never use it in a `const`.
String tx(String token, [Map<String, Object?>? args]) {
  final l = Tr.current;
  if (l != null) return l.tr(token, args);
  final m = openMessage(token);
  if (m != null) return tx(m.$1, {...?m.$2, ...?args});
  return fill(englishTokens[token] ?? token, args);
}

/// "1 quote" / "5 quotes": the noun's tokens `app.count.<noun>.one` and `.other`, each with `{n}`. A noun of two
/// words is written with an underscore (`new_work`).
String countWords(String noun, int n) => tx(
  'app.count.${noun.replaceAll(' ', '_')}.${n == 1 ? 'one' : 'other'}',
  {'n': n},
);

/// A sentence that reads differently for one and for many: the tokens `<base>.one` and `<base>.other`, with `{n}`.
String trn(String base, int n, [Map<String, Object?>? args]) =>
    tx('$base.${n == 1 ? 'one' : 'other'}', {'n': n, ...?args});

/// "a", "a and b", "a, b and c": the pieces of a list put together in the language of the app.
String andList(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return tx('app.list.and', {
    'a': items.sublist(0, items.length - 1).join(', '),
    'b': items.last,
  });
}

/// Puts [args] into the `{name}` places of [text].
String fill(String text, Map<String, Object?>? args) {
  if (args == null) return text;
  var out = text;
  for (final e in args.entries) {
    out = out.replaceAll('{${e.key}}', '${e.value}');
  }
  return out;
}

/// Gives the screens below it the [L10n], and rebuilds the ones that ask it for words when the language changes.
class L10nScope extends InheritedNotifier<L10n> {
  const L10nScope({super.key, required L10n? l10n, required super.child})
    : super(notifier: l10n);

  static L10n? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10nScope>()?.notifier;
}

extension TrContext on BuildContext {
  /// The words for [token] in the language the reader chose (English where there is no Bengali, or no [L10n] above).
  String tr(String token, [Map<String, Object?>? args]) {
    final l = L10nScope.of(this);
    if (l != null) return l.tr(token, args);
    final m = openMessage(token);
    if (m != null) return tr(m.$1, {...?m.$2, ...?args});
    return fill(englishTokens[token] ?? token, args);
  }
}
