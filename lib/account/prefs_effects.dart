import 'preferences.dart';

/// The preferences that plain functions (not widgets) read: how a credit is split into names, and what the
/// colours are called. [PairedPreferences] sets this each time the preferences change.
class PrefsEffects {
  PrefsEffects._();

  static ServerPrefs current = ServerPrefs.empty;

  static void apply(ServerPrefs p) => current = p;

  /// The pattern that splits a credit ("Pratchett & Gaiman") into names, as the reader chose which
  /// separators count. [slash] adds "/" for a speaker field.
  static RegExp creditPattern({bool slash = false}) {
    final parts = <String>[];
    for (final t in current.creditSeparators) {
      switch (t) {
        case 'comma':
          parts.add(',');
        case 'semicolon':
          parts.add(';');
        case 'amp':
          parts.add('&');
        case 'and':
          parts.add(r'\band\b');
      }
    }
    if (slash) parts.add('/');
    // "none" with no slash: a pattern that never matches, so the credit stays whole
    if (parts.isEmpty) return RegExp(r'(?!)');
    return RegExp('\\s*(?:${parts.join('|')})\\s*', caseSensitive: false);
  }
}
