import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../settings/settings_store.dart';
import 'prefs_effects.dart';

/// The reader's account preferences as the server keeps them (`preferences` in `GET /auth/me`). The map is the
/// server's own, kept whole, so a setting this app does not draw is never lost when one is saved.
class ServerPrefs {
  ServerPrefs([Map<String, Object?>? raw])
    : raw = Map.unmodifiable(raw ?? const {});

  static final empty = ServerPrefs();

  final Map<String, Object?> raw;

  /// Whether the server has said anything yet (a phone that has never reached it holds none).
  bool get known => raw.isNotEmpty;

  String str(String key, [String fallback = '']) {
    final v = raw[key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  int integer(String key, int fallback) {
    final v = raw[key];
    return v is num && v != 0 ? v.toInt() : fallback;
  }

  double number(String key, double fallback) {
    final v = raw[key];
    return v is num && v != 0 ? v.toDouble() : fallback;
  }

  bool flag(String key) => raw[key] == true;

  /// The interface language code ('' when none was chosen).
  String get locale => str('locale');

  /// How big the app's own text is, as a percentage: 75, 100, 125, 150, 175 or 200.
  int get sizeUi => integer('sizeUi', 100);

  /// How big a quote's words are, as a percentage.
  int get sizeDisplay => integer('sizeDisplay', 100);

  /// A quote's line height as a percentage (130 to 190), or 0 for the app's own.
  int get quoteLeading => integer('quoteLeading', 0);

  /// A quote's line length in characters (45, 55, 66 or 80), or 0 for the full width.
  int get quoteMeasure => integer('quoteMeasure', 0);

  /// Which separators split a credit like "Pratchett & Gaiman": any of comma, semicolon, amp, and; or none.
  List<String> get creditSeparators {
    final s = str('creditSeparators', 'comma,semicolon,amp,and');
    if (s == 'none') return const [];
    return [
      for (final t in s.split(','))
        if (t.trim().isNotEmpty) t.trim(),
    ];
  }

  /// The six colour slots in the server's order: yellow, blue, pink, orange, green, purple.
  static const colourSlots = [
    'yellow',
    'blue',
    'pink',
    'orange',
    'green',
    'purple',
  ];

  /// The name the reader gave colour [token] ('' for the built-in name).
  String colourName(String token) {
    final i = colourSlots.indexOf(token);
    return i <= 0 ? '' : str('catName${i + 1}');
  }

  /// The colour the reader chose for [token] as `#rrggbb`, or '' for the built-in one.
  String colourHex(String token) {
    final i = colourSlots.indexOf(token);
    return i < 0 ? '' : str('catColor${i + 1}');
  }

  /// Whether the reader hid colour [token] from the pickers (never the first).
  bool colourHidden(String token) {
    final i = colourSlots.indexOf(token);
    return i > 0 && flag('catHidden${i + 1}');
  }

  bool get hideLibrary => flag('hideLibrary');
  bool get hideCatalogue => flag('hideCatalogue');
  bool get hideQuotes => flag('hideQuotes');
  bool get showAnthologies => flag('showAnthologies');

  int get srDaily => integer('srDaily', 8);
  String get srReviewScope => str('srReviewScope', 'both');
  double get srSeen => number('srSeen', 1.0);
  String get srTier => str('srTier', 'medium');
  String get srStart => str('srStart', 'unseen');
  bool get srSubmit => flag('srSubmit');
  bool get srLadder => flag('srLadder');
  bool get srPracticeCounts => flag('srPracticeCounts');

  /// Days the Bin keeps things: 7, 30, 90, or -1 for ever.
  int get trashDays => integer('trashDays', 30);

  /// The face the reader chose for quotes in each language (folded language name to a face token).
  Map<String, String> get fontsByLanguage {
    final s = raw['fontsByLanguage'];
    if (s is! String || s.isEmpty) return const {};
    try {
      final j = jsonDecode(s);
      if (j is! Map) return const {};
      return {
        for (final e in j.entries)
          if (e.value is String && (e.value as String).isNotEmpty)
            '${e.key}'.trim().toLowerCase(): e.value as String,
      };
    } on FormatException {
      return const {};
    }
  }
}

/// The preferences, kept on the phone and in step with the server's. An interface so a test can stand in.
abstract class PreferencesSource implements Listenable {
  ServerPrefs get prefs;

  /// Reads them again from the server; the server's answer replaces what the phone holds.
  Future<void> refresh();

  /// Changes some of them. Applied here at once and sent to the server when there is one; returns the server's
  /// reason when it refused (and puts things back), or null.
  Future<String?> save(Map<String, Object?> patch);

  /// Puts everything back to the server's defaults.
  Future<String?> reset();
}

/// The preferences read from and written to the paired server, with a copy in the phone's own storage so the
/// app looks the same offline, and so a phone that is not paired still keeps what its reader sets.
class PairedPreferences extends ChangeNotifier implements PreferencesSource {
  PairedPreferences(this._controller, this._store) {
    // what waited was made under one pairing: it goes when the pairing does
    // what waited was made under one pairing, and so is the copy of that account's settings: both go with it
    _controller.offline.whenCleared.add(() async {
      await _store.remove(_pendingKey);
      await _store.remove(_key);
      _prefs = ServerPrefs.empty;
      notifyListeners();
    });
    final cached = _store.read(_key);
    if (cached != null) {
      try {
        final j = jsonDecode(cached);
        if (j is Map) {
          _prefs = ServerPrefs(j.cast<String, Object?>());
          PrefsEffects.apply(_prefs);
        }
      } on FormatException {
        // a damaged copy is read again from the server
      }
    }
  }

  static const _key = 'server_prefs';

  /// The settings the app's own pages control: what "back to the defaults" puts back. The web's look (theme,
  /// materials, fonts) is not here, so a reset on the phone does not change how the web looks.
  static const resettable = [
    'locale',
    'sizeUi',
    'sizeDisplay',
    'quoteLeading',
    'quoteMeasure',
    'creditSeparators',
    'fontsByLanguage',
    'catName2',
    'catName3',
    'catName4',
    'catName5',
    'catName6',
    'catColor1',
    'catColor2',
    'catColor3',
    'catColor4',
    'catColor5',
    'catColor6',
    'catHidden2',
    'catHidden3',
    'catHidden4',
    'catHidden5',
    'catHidden6',
    'hideLibrary',
    'hideCatalogue',
    'hideQuotes',
    'showAnthologies',
    'trashDays',
    'srDaily',
    'srReviewScope',
    'srSeen',
    'srTier',
    'srStart',
    'srSubmit',
    'srLadder',
    'srPracticeCounts',
  ];

  final AppController _controller;
  final SettingsStore _store;
  ServerPrefs _prefs = ServerPrefs.empty;

  @override
  ServerPrefs get prefs => _prefs;

  Future<void> _keep(Map<String, Object?> raw) async {
    _prefs = ServerPrefs(raw);
    PrefsEffects.apply(_prefs);
    await _store.write(_key, jsonEncode(raw));
    notifyListeners();
  }

  static const _pendingKey = 'outbox.preferences';

  /// The changes made while the server could not be reached, by setting: the value the reader chose (`v`) and
  /// the value the phone held for it when the change was made (`b`), which is what the server held as far as
  /// the phone knew. The base is how a change made on the web in the meantime wins: it is sent only while the
  /// server still holds the base.
  Map<String, Map<String, Object?>> get _pending {
    final raw = _store.read(_pendingKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          '${e.key}': Map<String, Object?>.from(e.value as Map),
      };
    } on Object {
      return {};
    }
  }

  /// Whether a change made with no server is waiting to go up.
  bool get hasPending => _pending.isNotEmpty;

  Future<void> _setPending(Map<String, Map<String, Object?>> p) => p.isEmpty
      ? _store.remove(_pendingKey)
      : _store.write(_pendingKey, jsonEncode(p));

  /// The server's own copy of the preferences, or null when it could not be asked.
  Future<Map<String, Object?>?> _serverCopy() async {
    try {
      final me = await _controller.withClient((c) => c.getJson('/auth/me'));
      final p = me is Map ? me['preferences'] : null;
      return p is Map ? p.cast<String, Object?>() : null;
    } on ApiException {
      return null;
    }
  }

  /// Sends the changes that waited for the server. A change goes only if the server still holds what the
  /// phone held when it was made; one the server has moved on from (changed on the web meanwhile) is dropped,
  /// and the server's value stands. True when nothing is left waiting.
  Future<bool> flush() async {
    final waiting = _pending;
    if (waiting.isEmpty) return true;
    if (!_controller.paired) return false;
    final server = await _serverCopy();
    if (server == null) return false;
    final send = <String, Object?>{
      for (final e in waiting.entries)
        if (jsonEncode(server[e.key]) == jsonEncode(e.value['b']))
          e.key: e.value['v'],
    };
    if (send.isNotEmpty) {
      try {
        await _controller.withClient(
          (c) => c.putJson('/auth/me/preferences', send),
        );
      } on ApiException catch (e) {
        // a value the server will not take is not kept for ever; anything else is tried again later
        if (e.status != 400) return false;
      }
    }
    await _setPending({});
    return true;
  }

  @override
  Future<void> refresh() async {
    if (!_controller.paired) return;
    await flush();
    final server = await _serverCopy();
    if (server == null) return; // keep what the phone holds
    // what could not be sent yet still shows, over the server's copy
    await _keep({
      ...server,
      for (final e in _pending.entries) e.key: e.value['v'],
    });
  }

  @override
  Future<String?> save(Map<String, Object?> patch) async {
    final before = Map<String, Object?>.of(_prefs.raw);
    await _keep({...before, ...patch});
    if (!_controller.paired) return null;
    try {
      await _controller.withClient(
        (c) => c.putJson('/auth/me/preferences', patch),
      );
      // sent: whatever waited for these settings is out of date
      final p = _pending..removeWhere((k, _) => patch.containsKey(k));
      await _setPending(p);
      return null;
    } on ApiException catch (e) {
      if (e.status == 400) {
        await _keep(before);
        return e.detail;
      }
      // the server could not be reached: the change stays on the phone and goes up with the next run
      final p = _pending;
      for (final e in patch.entries) {
        p[e.key] = {'v': e.value, 'b': p[e.key]?['b'] ?? before[e.key]};
      }
      await _setPending(p);
      return null;
    }
  }

  @override
  Future<String?> reset() async {
    final without = {..._prefs.raw}
      ..removeWhere((k, _) => resettable.contains(k));
    if (!_controller.paired) {
      await _keep(without);
      return null;
    }
    try {
      await _controller.withClient(
        (c) => c.postJson('/auth/me/preferences/reset', {'keys': resettable}),
      );
      await refresh();
      return null;
    } on ApiException catch (e) {
      return e.detail;
    }
  }
}

/// Gives the screens below it the [PreferencesSource], and rebuilds the ones that read it when it changes.
class PrefsScope extends InheritedNotifier<Listenable> {
  const PrefsScope({super.key, required this.source, required super.child})
    : super(notifier: source);

  final PreferencesSource? source;

  static PreferencesSource? sourceOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PrefsScope>()?.source;

  /// The preferences, reading them registers [context] for a rebuild when they change.
  static ServerPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrefsScope>()?.source?.prefs ??
      ServerPrefs.empty;
}
