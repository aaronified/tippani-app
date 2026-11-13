import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_controller.dart';
import '../settings/settings_store.dart';
import 'api_client.dart';

/// Small server writes that wait for the server when there is none (ADR-0022): a tag's name, colour or style, a
/// tag deleted, a context rule, an item restored from the bin. They are kept in the phone's own storage and
/// sent in the order they were made the next time the server answers, each one shown at once on the kept copy
/// of the screen it changes. What cannot be undone or has to be answered (merging tags, emptying the bin, a
/// password) is not queued, and says it needs the server.
///
/// A change the server refuses (a name that exists, an item already gone) is dropped and listed in [problems];
/// one it could not be asked about stays and is tried again. The queue goes when the pairing does, so a change
/// is never sent to another account.
class OfflineWrites {
  OfflineWrites(this._controller, this._store) {
    pending.value = _load().length;
    _controller.offline.whenCleared.add(() async {
      await _store.remove(_key);
      pending.value = 0;
      problems.value = const [];
    });
  }

  static const _key = 'outbox.writes';

  final AppController _controller;
  final SettingsStore _store;

  /// How many changes wait.
  final pending = ValueNotifier<int>(0);

  /// What the server refused, in plain words, since the list was last read.
  final problems = ValueNotifier<List<String>>(const []);

  bool _flushing = false;

  List<Map<String, Object?>> _load() {
    final raw = _store.read(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          Map<String, Object?>.from(e as Map),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> _save(List<Map<String, Object?>> ops) async {
    if (ops.isEmpty) {
      await _store.remove(_key);
    } else {
      await _store.write(_key, jsonEncode(ops));
    }
    pending.value = ops.length;
  }

  static bool _waits(ApiException e) =>
      e.failure == ApiFailure.network ||
      e.failure == ApiFailure.timeout ||
      e.failure == ApiFailure.rateLimited ||
      (e.failure == ApiFailure.server && (e.status ?? 0) >= 502);

  Future<Object?> _send(Map<String, Object?> op) async {
    final path = op['path'] as String;
    final body = op['body'] is Map
        ? Map<String, Object?>.from(op['body'] as Map)
        : <String, Object?>{};
    return _controller.withClient((c) async {
      switch (op['method']) {
        case 'PUT':
          return c.putJson(path, body);
        case 'POST':
          return c.postJson(path, body);
        default:
          return c.delete(path);
      }
    });
  }

  /// Makes [method] [path] with [body]: at once when the server answers, otherwise kept, with [local] applied to
  /// the screens' kept copy so the change shows. [sent] is true when it went (with the server's [answer]) and false
  /// when it waits. A refusal, or an error that is not a wait, is thrown as the [ApiException] it is.
  Future<({bool sent, Object? answer})> write(
    String method,
    String path,
    Map<String, Object?>? body, {
    required Future<void> Function() local,
  }) async {
    if (_load().isNotEmpty) await flush();
    if (_load().isEmpty && _controller.paired) {
      try {
        final answer = await _send({
          'method': method,
          'path': path,
          'body': body,
        });
        return (sent: true, answer: answer);
      } on ApiException catch (e) {
        if (!_waits(e)) rethrow;
      }
    }
    final ops = _load()..add({'method': method, 'path': path, 'body': ?body});
    await _save(ops);
    await local();
    return (sent: false, answer: null);
  }

  /// Sends what waits, in order. Stops at the first change the server cannot be asked about. Returns how many
  /// are left.
  Future<int> flush() async {
    if (_flushing || !_controller.paired) return _load().length;
    _flushing = true;
    try {
      final refused = <String>[];
      while (true) {
        final ops = _load();
        if (ops.isEmpty) break;
        final op = ops.first;
        try {
          await _send(op);
        } on ApiException catch (e) {
          if (_waits(e) || e.failure == ApiFailure.unauthorised) break;
          refused.add(
            e.detail.isEmpty
                ? '${op['method']} ${op['path']} was refused (${e.status ?? '?'})'
                : e.detail,
          );
        }
        // read again: a change made while this one was out is kept
        final now = _load();
        if (now.isNotEmpty && jsonEncode(now.first) == jsonEncode(op)) {
          now.removeAt(0);
        }
        await _save(now);
      }
      if (refused.isNotEmpty) problems.value = [...problems.value, ...refused];
      return _load().length;
    } finally {
      _flushing = false;
    }
  }

  /// Changes the kept answer to GET [path], if one is kept: [change] gets the decoded JSON and returns the new
  /// value. This is how a queued change shows on the screen it belongs to.
  Future<void> patchKept(
    String path,
    Object? Function(Object? json) change,
  ) async {
    final kept = _controller.offline.read(path);
    if (kept == null) return;
    try {
      final next = change(jsonDecode(kept.body));
      await _controller.offline.write(path, jsonEncode(next), at: kept.at);
    } on Object {
      // a copy that cannot be read is left as it is
    }
  }
}
