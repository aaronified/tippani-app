import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'files.dart';

enum LogLevel { info, warn, error }

/// The app's own log: what it did and what went wrong, kept on the phone so a reader can look at it and,
/// when they choose, send it. A failed save is otherwise silent.
///
/// The lines of this run are held in memory and written to the app's own storage a moment after each
/// one. At the next start they move into the history, which keeps the newest [historyCap] characters.
///
/// WHAT IS NEVER IN IT: a credential, and anything the reader wrote. It records the app's own steps
/// (start, a server asked, an update checked, a backup made, a failure) and never a quote's words, a
/// header, or a body. [redact] is the last line of defence, not the first: callers pass what happened,
/// not what was said.
class AppLog {
  /// [writeDelay] is how long after a line the run is written to storage; null writes only when [flush] is
  /// called, which is what a test wants (a pending timer fails a widget test).
  AppLog({
    this._files,
    DateTime Function()? clock,
    this.writeDelay = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  final Duration? writeDelay;

  AppFiles? _files;
  final DateTime Function() _clock;

  final List<String> _lines = [];
  String _history = '';
  bool _started = false;
  Timer? _timer;
  DateTime _begin = DateTime.now();

  static const currentFile = 'current.log';
  static const historyFile = 'history.log';

  /// The most lines one run keeps (the oldest go first), and the most characters of earlier runs.
  static const maxLines = 4000;
  static const historyCap = 300000;

  DateTime get begin => _begin;
  int get length => _lines.length;

  /// The lines of this run, oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  /// Opens a run: what the last one wrote moves into the history, and this one starts. Lines added before
  /// this (the very first moments of a start) are kept. Safe to call again; it does nothing the second time.
  Future<void> start({required String version, AppFiles? files}) async {
    if (_started) return;
    _started = true;
    if (files != null) _files = files;
    _begin = _clock();
    final store = _files;
    if (store != null) {
      final old = await store.readLog(currentFile);
      final hist = await store.readLog(historyFile);
      var text =
          (hist == null ? '' : utf8.decode(hist, allowMalformed: true)) +
          (old == null ? '' : utf8.decode(old, allowMalformed: true));
      if (text.length > historyCap) {
        text = text.substring(text.length - historyCap);
        final nl = text.indexOf('\n');
        if (nl >= 0) text = text.substring(nl + 1);
      }
      _history = text;
      if (text.isNotEmpty) {
        await store.writeLog(
          historyFile,
          Uint8List.fromList(utf8.encode(text)),
        );
      }
    }
    add(LogLevel.info, 'start tippani-app $version');
  }

  void info(String message) => add(LogLevel.info, message);
  void warn(String message) => add(LogLevel.warn, message);
  void error(String message) => add(LogLevel.error, message);

  void add(LogLevel level, String message) {
    final at = _clock().toIso8601String().split('.').first;
    _lines.add('$at [${level.name}] ${redact(message)}');
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    _schedule();
  }

  void _schedule() {
    final delay = writeDelay;
    if (_files == null || !_started || delay == null) return;
    _timer ??= Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Writes this run now. Called on a timer after each line, and on demand before the log is shared.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await _files?.writeLog(
      currentFile,
      Uint8List.fromList(utf8.encode('${_lines.join('\n')}\n')),
    );
  }

  /// This run's text, or with earlier runs before it.
  String text({bool includeHistory = false}) {
    final run = _lines.isEmpty ? '' : '${_lines.join('\n')}\n';
    if (!includeHistory || _history.isEmpty) return run;
    return '$_history${_history.endsWith('\n') ? '' : '\n'}--- earlier runs above, this run below ---\n$run';
  }

  /// Empties the log, this run and the history.
  Future<void> clear() async {
    _lines.clear();
    _history = '';
    _timer?.cancel();
    _timer = null;
    final store = _files;
    if (store != null) {
      await store.writeLog(currentFile, Uint8List(0));
      await store.writeLog(historyFile, Uint8List(0));
    }
  }
}

/// Takes a credential out of a line before it is kept. `Authorization: Bearer ...`, `token=...` and a long
/// run of hex or base64 characters (what a device token looks like) become `[redacted]`.
String redact(String line) {
  return line
      .replaceAllMapped(
        RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
        (m) => '${m[1]}[redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'((?:token|password|secret|key)\s*[=:]\s*)\S+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}[redacted]',
      )
      .replaceAll(RegExp(r'\b[A-Fa-f0-9]{32,}\b'), '[redacted]')
      .replaceAll(
        RegExp(r'(?<![A-Za-z0-9_\-])[A-Za-z0-9_\-]{40,}(?![A-Za-z0-9_\-])'),
        '[redacted]',
      );
}

/// The one log the app writes to. Created in `main`; tests build their own.
final AppLog appLog = AppLog();
