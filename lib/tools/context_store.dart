import 'dart:convert';
import 'dart:io';

/// The context of quotes, kept on the phone one file each, so every synced quote reads with no server
/// (ADR-0022). The small settings storage the rest of the offline copy uses would not hold thousands of them.
///
/// An entry is the widest answer the server gave for the quote, or the note that it has none (so a quote with no
/// stored context is not asked about again at every sync).
abstract interface class ContextStore {
  /// The kept answer for [key] (`annotation-12`), or null.
  Future<StoredContext?> read(String key);

  Future<void> write(String key, StoredContext entry);

  /// Forgets everything (the phone was unpaired, or the server forgotten).
  Future<void> clear();
}

class StoredContext {
  const StoredContext({required this.at, this.body});

  /// A note that the server has no context for the quote.
  const StoredContext.none(this.at) : body = null;

  final DateTime at;

  /// The server's JSON for the context, or null for "none".
  final String? body;

  bool get none => body == null;

  Map<String, Object?> toJson() => {
    't': at.millisecondsSinceEpoch,
    if (body != null) 'b': body,
  };

  static StoredContext? fromJson(Object? j) {
    if (j is! Map || j['t'] is! int) return null;
    return StoredContext(
      at: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      body: j['b'] is String ? j['b'] as String : null,
    );
  }
}

/// The real store: files in a folder the phone keeps for the app.
class FileContextStore implements ContextStore {
  FileContextStore(this._folder);

  /// Where the files go, asked for the first time one is needed (the folder is the platform's to name).
  final Future<Directory> Function() _folder;
  Directory? _dir;

  Future<Directory> _where() async {
    final d = _dir ??= await _folder();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String key) async => File(
    '${(await _where()).path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json',
  );

  @override
  Future<StoredContext?> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      return StoredContext.fromJson(jsonDecode(await f.readAsString()));
    } on Object {
      return null; // a damaged or unreadable file is a missing one
    }
  }

  @override
  Future<void> write(String key, StoredContext entry) async {
    try {
      final f = await _file(key);
      // written beside and moved over, so a file is never half written when the app is stopped
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(entry.toJson()), flush: true);
      await tmp.rename(f.path);
    } on Object {
      // a full or failing disk must not break the read that worked
    }
  }

  @override
  Future<void> clear() async {
    try {
      final d = await _where();
      await for (final e in d.list()) {
        if (e is File) await e.delete();
      }
    } on Object {
      // nothing to forget
    }
  }
}

/// A store that keeps its entries in memory, for a test.
class MemoryContextStore implements ContextStore {
  final entries = <String, StoredContext>{};

  @override
  Future<StoredContext?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, StoredContext entry) async =>
      entries[key] = entry;

  @override
  Future<void> clear() async => entries.clear();
}
