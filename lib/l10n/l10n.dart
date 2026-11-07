import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_bengali.dart';

/// One language the reader can choose for the app's words.
class LocaleChoice {
  const LocaleChoice(this.code, this.name);

  final String code;

  /// The language's own name for itself ("বাংলা").
  final String name;
}

/// Parses a Tippani locale file: `key = value` per line, `#` for comments, the first `=` splits, `_key` is
/// metadata, an empty value counts as absent. The same rules the server's parser keeps.
({Map<String, String> keys, Map<String, String> reserved}) parseLocale(
  String src,
) {
  final keys = <String, String>{};
  final reserved = <String, String>{};
  var text = src.startsWith('﻿') ? src.substring(1) : src;
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final line in text.split('\n')) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final eq = s.indexOf('=');
    if (eq <= 0) continue;
    final k = s.substring(0, eq).trim();
    final v = s.substring(eq + 1).trim();
    if (k.isEmpty || v.isEmpty) continue;
    if (k.startsWith('_')) {
      reserved[k] = v;
    } else {
      keys[k] = v;
    }
  }
  return (keys: keys, reserved: reserved);
}

/// The words of the app in the language the reader chose.
///
/// The app is written in English, and each English string is its own key: `tr('Settings')`. A Bengali string is
/// found in this order: the server's own text for the language (any file under its Locales folder, which the
/// server serves at `/locales`, so a correction made there reaches the phone), then the web app's Bengali (the
/// copy of its text bundled with the app, matched by the English line), then the app's own Bengali for what the
/// web has no line for. Anything not found is shown in English, never blank.
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

  Map<String, String>? _enToBn; // English line -> the web's Bengali line
  Map<String, String> _enToKey = const {};
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
    try {
      final en = parseLocale(await _bundle.loadString('assets/l10n/en.txt'));
      final bn = parseLocale(await _bundle.loadString('assets/l10n/bn.txt'));
      final toBn = <String, String>{};
      final toKey = <String, String>{};
      for (final e in en.keys.entries) {
        toKey.putIfAbsent(e.value, () => e.key);
        final b = bn.keys[e.key];
        if (b != null) toBn.putIfAbsent(e.value, () => b);
      }
      _enToBn = toBn;
      _enToKey = toKey;
      notifyListeners();
    } on Object {
      _enToBn = const {};
    }
  }

  String? _lookup(String english) {
    if (_code == 'en') {
      final key = _enToKey[english];
      return key == null ? null : _files['en']?[key];
    }
    final key = _enToKey[english];
    String? fromFile(String code) => key == null ? null : _files[code]?[key];
    final own = fromFile(_code);
    if (own != null) return own;
    if (_code == 'bn') return _enToBn?[english] ?? appBengali[english];
    // another language the server holds: its own lines, then the language it says to fall back to
    final back = _filesReserved[_code]?['_fallback'];
    if (back != null && back != _code) {
      final b = fromFile(back);
      if (b != null) return b;
      if (back == 'bn') return _enToBn?[english] ?? appBengali[english];
    }
    return null;
  }

  /// [english] in the chosen language; [args] fill `{name}` places.
  String tr(String english, [Map<String, Object?>? args]) {
    var out = _lookup(english) ?? english;
    if (args != null) {
      for (final e in args.entries) {
        out = out.replaceAll('{${e.key}}', '${e.value}');
      }
    }
    return out;
  }

  /// Whether the text is ready (a test waits on this).
  @visibleForTesting
  Future<void> get loaded async => _loading ?? Future<void>.value();
}

/// Gives the screens below it the [L10n], and rebuilds the ones that ask it for words when the language changes.
class L10nScope extends InheritedNotifier<L10n> {
  const L10nScope({super.key, required L10n? l10n, required super.child})
    : super(notifier: l10n);

  static L10n? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10nScope>()?.notifier;
}

extension TrContext on BuildContext {
  /// The words [english] in the language the reader chose; English when there is no translation.
  String tr(String english, [Map<String, Object?>? args]) {
    final l = L10nScope.of(this);
    if (l == null) {
      var out = english;
      if (args != null) {
        for (final e in args.entries) {
          out = out.replaceAll('{${e.key}}', '${e.value}');
        }
      }
      return out;
    }
    return l.tr(english, args);
  }
}
