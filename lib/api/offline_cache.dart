import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings/settings_store.dart';

/// What the server last said, kept on the phone so a screen that only reads still has something to show when
/// the server cannot be reached (ADR-0022).
///
/// WHAT IS KEPT. The answer to a GET, by its path and query, for the paths [isCacheablePath] allows: the screens
/// that display what the server holds (anthologies, contexts, statistics, tags, the people records, Checks, the
/// bin, the metadata console). Not the routes sync reads, because sync treats "the server answered" as fact and an
/// old answer served in its place would look like a server that had lost everything; and not `/auth/me`, whose
/// failure is how the app learns it was unpaired.
///
/// WHERE. [SettingsStore]'s own text storage, one entry per path, so a test needs nothing but mocked preferences.
/// The total is bounded: past [maxBytes] or [maxEntries] the least recently used entries go, except the pinned
/// ones (anthologies), which are the reader's own work.
class OfflineCache {
  OfflineCache(this._store, {this.maxBytes = 3000000, this.maxEntries = 400});

  final SettingsStore _store;
  final int maxBytes;
  final int maxEntries;

  static const _prefix = 'offline.';
  static const _indexKey = 'offline.index';

  /// When the last answer served from the phone was saved, or null while the last read came from the server.
  /// A screen can say "from this phone, as of …" while it holds a date.
  final ValueNotifier<DateTime?> servedFrom = ValueNotifier(null);

  List<List<Object?>>? _index;

  List<List<Object?>> get _entries {
    final cached = _index;
    if (cached != null) return cached;
    final raw = _store.read(_indexKey);
    var parsed = <List<Object?>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is List) {
          parsed = [
            for (final e in j)
              if (e is List && e.length == 2 && e[0] is String && e[1] is int)
                [e[0], e[1]],
          ];
        }
      } on FormatException {
        parsed = [];
      }
    }
    return _index = parsed;
  }

  /// Whether the answer to a GET of [path] is worth keeping.
  static bool isCacheablePath(String path) {
    final p = Uri.parse(path).path;
    for (final prefix in _prefixes) {
      if (p == prefix || p.startsWith('$prefix/')) return true;
    }
    return _context.hasMatch(p);
  }

  static final _context = RegExp(
    r'^/quotes/(annotation|dialogue|utterance)/\d+/context$',
  );

  static const _prefixes = [
    '/anthologies',
    '/stats',
    '/tags',
    '/stickers',
    '/trash',
    '/search/vocabulary',
    '/people',
    '/characters',
    '/cleanup',
    '/corrections',
    '/locators/proposals',
    '/metadata/library',
    '/metadata/duplicates',
    '/metadata/status',
    '/context-rules',
    '/sources/all',
    '/sources/mounts',
    '/admin/users',
    '/admin/mounts',
    '/admin/metadata-keys',
    '/admin/update/check',
    '/admin/backup',
    '/jobs/common',
  ];

  static bool _pinned(String key) => key.startsWith('/anthologies');

  /// The saved answer for [key] and when it was saved, or null.
  ({String body, DateTime at})? read(String key) {
    final raw = _store.read('$_prefix$key');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['b'] is String && j['t'] is int) {
        return (
          body: j['b'] as String,
          at: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
        );
      }
    } on FormatException {
      // fall through: a damaged entry is a missing one
    }
    return null;
  }

  /// Keeps [body] as the answer for [key], and drops the oldest entries if the cache is over its bounds.
  Future<void> write(String key, String body, {DateTime? at}) async {
    final entry = jsonEncode({
      'b': body,
      't': (at ?? DateTime.now()).millisecondsSinceEpoch,
    });
    final entries = _entries;
    final i = entries.indexWhere((e) => e[0] == key);
    if (i >= 0) entries.removeAt(i);
    entries.add([key, entry.length]);
    await _store.write('$_prefix$key', entry);
    await _trim(entries);
    await _store.write(_indexKey, jsonEncode(entries));
  }

  Future<void> _trim(List<List<Object?>> entries) async {
    int total() => entries.fold<int>(0, (n, e) => n + (e[1] as int));
    while (entries.length > maxEntries || total() > maxBytes) {
      final victim = entries.indexWhere((e) => !_pinned(e[0] as String));
      if (victim < 0) return;
      final key = entries.removeAt(victim)[0] as String;
      await _store.remove('$_prefix$key');
    }
  }

  /// Forgets one answer.
  Future<void> remove(String key) async {
    final entries = _entries;
    entries.removeWhere((e) => e[0] == key);
    await _store.remove('$_prefix$key');
    await _store.write(_indexKey, jsonEncode(entries));
  }

  /// Forgets everything kept (the phone was unpaired from this server: another account's answers must not
  /// show under the next one).
  Future<void> clear() async {
    for (final e in List.of(_entries)) {
      await _store.remove('$_prefix${e[0]}');
    }
    _index = [];
    await _store.remove(_indexKey);
    servedFrom.value = null;
  }
}
