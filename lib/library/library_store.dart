import 'package:sqflite/sqflite.dart';

import '../sync/fingerprint.dart';
import 'models.dart';

/// The app's own library of works and quotes, kept on the phone. It is what lets the app work with no
/// server: capture, browse, search, edit, tag and the quiz all read and write this and nothing else.
/// Pairing adds a push and a pull on top; it never replaces this.
abstract interface class LibraryStore {
  Future<Work> addWork(WorkDraft draft);
  Future<Work?> work(int id);
  Future<Work> updateWork(int id, WorkDraft draft);

  /// Deletes a work and every quote that came from it.
  Future<void> deleteWork(int id);

  /// Works, by title, optionally of one kind and matching a query on title or creator.
  Future<List<Work>> works({WorkKind? kind, String query = ''});

  Future<Quote> addQuote(QuoteDraft draft);
  Future<Quote?> quote(int id);
  Future<Quote> updateQuote(int id, QuoteDraft draft);
  Future<void> deleteQuote(int id);
  Future<void> setFavorite(int id, bool favorite);

  /// Quotes, newest met first. [query] matches the words, the translation, the note, who said it, the
  /// work's title and creator, and the tags; [tag] keeps only quotes with that tag.
  Future<List<Quote>> quotes({
    int? workId,
    String query = '',
    bool favouritesOnly = false,
    String? tag,
    int limit = 200,
    int offset = 0,
  });

  Future<List<String>> tags();
  Future<LibraryCounts> counts();

  /// What the paired server has never been given: works and quotes whose `server_id` is empty, oldest first.
  Future<List<Work>> unsyncedWorks();
  Future<List<Quote>> unsyncedQuotes();

  /// Records the server's id for a work or quote it now holds. Changes nothing else, not even `updated_at`:
  /// being on the server is not an edit.
  Future<void> setWorkServerId(int id, int serverId);
  Future<void> setQuoteServerId(int id, int serverId);

  /// Records what the phone and the server last agreed a work or quote said. Like the server id, it is not
  /// an edit and leaves `updated_at` alone.
  Future<void> markWorkSynced(int id, String hash);
  Future<void> markQuoteSynced(int id, String hash);

  /// Adds a work or quote that came from the server, already linked to it and already agreed. One write,
  /// so a crash cannot leave it without its server id (which would send it back up as a duplicate).
  Future<Work> adoptWork(WorkDraft draft, int serverId, String hash);
  Future<Quote> adoptQuote(QuoteDraft draft, int serverId, String hash);

  /// Everything, as JSON-encodable data, for a backup or an export.
  Future<Map<String, Object?>> exportAll();

  /// What the reader deleted here that the server still holds, to be deleted there too (its bin keeps it for
  /// a while). Written when a linked work or quote is deleted; cleared once the server has been told.
  Future<List<PendingDeletion>> pendingDeletions();
  Future<void> clearDeletion(int id);

  /// Forgets that a work or quote is on the server, so the next push sends it as new.
  Future<void> unlinkWork(int id);
  Future<void> unlinkQuote(int id);

  /// Removes a work or quote because the server no longer has it. Unlike [deleteWork] and [deleteQuote] it
  /// leaves no pending deletion behind, which would only tell the server what it already knows.
  Future<void> dropWork(int id);
  Future<void> dropQuote(int id);

  /// Replaces everything with what [exportAll] gave. Validated first and written in one transaction, so a
  /// damaged file changes nothing.
  Future<void> replaceAll(Map<String, Object?> data);
}

/// A delete the server has yet to hear of: [route] is the server's collection (`/books`, `/annotations`...).
class PendingDeletion {
  const PendingDeletion(this.id, this.route, this.serverId);
  final int id;
  final String route;
  final int serverId;
}

class LibraryException implements Exception {
  const LibraryException(this.message);
  final String message;

  @override
  String toString() => 'LibraryException($message)';
}

/// SQLite on the phone (or in memory, in a test).
class SqliteLibraryStore implements LibraryStore {
  SqliteLibraryStore(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  static const schemaVersion = 3;

  /// The longest a quote's text or a title may be. A pasted book is not a quote.
  static const maxText = 20000;
  static const maxTitle = 500;

  /// Opens (and creates, or upgrades) the library at [path]. Use `inMemoryDatabasePath` for a test.
  ///
  /// [singleInstance] is sqflite's: true (the default) shares one connection per path, which is right for
  /// the app and wrong for two independent in-memory libraries in one test.
  static Future<SqliteLibraryStore> open(
    String path, {
    DateTime Function()? clock,
    bool singleInstance = true,
  }) async {
    final db = await openDatabase(
      path,
      version: schemaVersion,
      singleInstance: singleInstance,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async => _create(db),
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          await db.execute('ALTER TABLE works ADD COLUMN synced_hash TEXT');
          await db.execute('ALTER TABLE quotes ADD COLUMN synced_hash TEXT');
        }
        if (from < 3) await _createDeletions(db);
      },
    );
    return SqliteLibraryStore(db, clock: clock);
  }

  static Future<void> _createDeletions(Database db) => db.execute('''
      CREATE TABLE deletions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route TEXT NOT NULL,
        server_id INTEGER NOT NULL,
        deleted_at TEXT NOT NULL
      )''');

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE works (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        creator TEXT NOT NULL DEFAULT '',
        year INTEGER,
        language TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        server_id INTEGER,
        synced_hash TEXT
      )''');
    await db.execute('''
      CREATE TABLE quotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_id INTEGER REFERENCES works(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        translation TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL DEFAULT '',
        speaker TEXT NOT NULL DEFAULT '',
        chapter TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT 'yellow',
        favorite INTEGER NOT NULL DEFAULT 0,
        noted_at TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        server_id INTEGER,
        synced_hash TEXT
      )''');
    await db.execute('CREATE INDEX quotes_work ON quotes(work_id)');
    await db.execute('CREATE INDEX quotes_noted ON quotes(noted_at)');
    await _createDeletions(db);
    await db.execute(
      'CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
    );
    await db.execute('''
      CREATE TABLE quote_tags (
        quote_id INTEGER NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
        tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY (quote_id, tag_id)
      )''');
  }

  String _now() => _clock().toUtc().toIso8601String();

  // ---- works --------------------------------------------------------------------------------------

  Work _work(Map<String, Object?> r) => Work(
    id: r['id']! as int,
    kind: workKindOf(r['kind']),
    title: r['title']! as String,
    creator: r['creator']! as String,
    year: r['year'] as int?,
    language: r['language']! as String,
    createdAt: DateTime.parse(r['created_at']! as String),
    updatedAt: DateTime.parse(r['updated_at']! as String),
    serverId: r['server_id'] as int?,
    syncedHash: r['synced_hash'] as String?,
  );

  String _title(String raw) {
    final t = raw.trim();
    if (t.isEmpty) throw const LibraryException('a work needs a title');
    if (t.length > maxTitle) {
      throw const LibraryException('that title is too long');
    }
    return t;
  }

  @override
  Future<Work> addWork(WorkDraft d) async {
    final now = _now();
    final id = await _db.insert('works', {
      'kind': d.kind.name,
      'title': _title(d.title),
      'creator': d.creator.trim(),
      'year': d.year,
      'language': d.language.trim(),
      'created_at': now,
      'updated_at': now,
    });
    return (await work(id))!;
  }

  @override
  Future<Work?> work(int id) async {
    final rows = await _db.query('works', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _work(rows.single);
  }

  @override
  Future<Work> updateWork(int id, WorkDraft d) async {
    final n = await _db.update(
      'works',
      {
        'kind': d.kind.name,
        'title': _title(d.title),
        'creator': d.creator.trim(),
        'year': d.year,
        'language': d.language.trim(),
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (n == 0) throw const LibraryException('no such work');
    return (await work(id))!;
  }

  @override
  Future<void> deleteWork(int id) async {
    await _db.transaction((tx) async {
      final rows = await tx.query('works', where: 'id = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        final w = _work(rows.single);
        final realm = realmOfKind(w.kind);
        if (w.serverId != null) {
          await _note(tx, workRoute(realm), w.serverId!);
        }
        for (final q in await tx.query(
          'quotes',
          columns: ['server_id'],
          where: 'work_id = ? AND server_id IS NOT NULL',
          whereArgs: [id],
        )) {
          await _note(tx, quoteRoute(realm), q['server_id']! as int);
        }
      }
      await tx.delete('works', where: 'id = ?', whereArgs: [id]);
    });
    await _dropUnusedTags();
  }

  Future<void> _note(DatabaseExecutor tx, String route, int serverId) =>
      tx.insert('deletions', {
        'route': route,
        'server_id': serverId,
        'deleted_at': _now(),
      });

  @override
  Future<void> dropWork(int id) async {
    await _db.delete('works', where: 'id = ?', whereArgs: [id]);
    await _dropUnusedTags();
  }

  @override
  Future<void> dropQuote(int id) async {
    await _db.delete('quotes', where: 'id = ?', whereArgs: [id]);
    await _dropUnusedTags();
  }

  @override
  Future<List<PendingDeletion>> pendingDeletions() async => [
    for (final r in await _db.query('deletions', orderBy: 'id'))
      PendingDeletion(
        r['id']! as int,
        r['route']! as String,
        r['server_id']! as int,
      ),
  ];

  @override
  Future<void> clearDeletion(int id) async {
    await _db.delete('deletions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> unlinkWork(int id) async {
    await _db.update(
      'works',
      {'server_id': null, 'synced_hash': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> unlinkQuote(int id) async {
    await _db.update(
      'quotes',
      {'server_id': null, 'synced_hash': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// A LIKE pattern that matches [raw] literally: a `%` or `_` the reader types is the character they mean.
  static String like(String raw) =>
      '%${raw.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  @override
  Future<List<Work>> works({WorkKind? kind, String query = ''}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (query.trim().isNotEmpty) {
      where.add(r"(title LIKE ? ESCAPE '\' OR creator LIKE ? ESCAPE '\')");
      args.addAll([like(query), like(query)]);
    }
    final rows = await _db.query(
      'works',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'title COLLATE NOCASE, id',
    );
    return [for (final r in rows) _work(r)];
  }

  // ---- quotes -------------------------------------------------------------------------------------

  static const _quoteSelect = '''
    SELECT q.*, COALESCE((SELECT group_concat(t.name, char(31)) FROM quote_tags qt JOIN tags t ON t.id = qt.tag_id WHERE qt.quote_id = q.id), '') AS tag_list
    FROM quotes q
  ''';

  Quote _quote(Map<String, Object?> r) {
    final tagList = r['tag_list']! as String;
    final tags = tagList.isEmpty
        ? <String>[]
        : (tagList.split('\x1f')
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    return Quote(
      id: r['id']! as int,
      workId: r['work_id'] as int?,
      text: r['text']! as String,
      translation: r['translation']! as String,
      language: r['language']! as String,
      speaker: r['speaker']! as String,
      chapter: r['chapter']! as String,
      location: r['location']! as String,
      note: r['note']! as String,
      color: r['color']! as String,
      favorite: (r['favorite']! as int) != 0,
      notedAt: DateTime.parse(r['noted_at']! as String),
      source: r['source']! as String,
      createdAt: DateTime.parse(r['created_at']! as String),
      updatedAt: DateTime.parse(r['updated_at']! as String),
      tags: tags,
      serverId: r['server_id'] as int?,
      syncedHash: r['synced_hash'] as String?,
    );
  }

  String _text(String raw) {
    final t = raw.trim();
    if (t.isEmpty) throw const LibraryException('a quote needs its words');
    if (t.length > maxText) {
      throw const LibraryException('that is too long to be a quote');
    }
    return t;
  }

  List<String> _cleanTags(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in raw) {
      final name = t.trim();
      if (name.isEmpty || name.length > 80) continue;
      if (seen.add(name.toLowerCase())) out.add(name);
    }
    return out;
  }

  Map<String, Object?> _quoteRow(QuoteDraft d) => {
    'work_id': d.workId,
    'text': _text(d.text),
    'translation': d.translation.trim(),
    'language': d.language.trim(),
    'speaker': d.speaker.trim(),
    'chapter': d.chapter.trim(),
    'location': d.location.trim(),
    'note': d.note.trim(),
    'color': quoteColors.contains(d.color) ? d.color : 'yellow',
    'favorite': d.favorite ? 1 : 0,
    'noted_at': (d.notedAt ?? _clock()).toUtc().toIso8601String(),
    'source': d.source.trim().isEmpty ? 'manual' : d.source.trim(),
  };

  Future<void> _writeTags(
    DatabaseExecutor tx,
    int quoteId,
    List<String> tags,
  ) async {
    await tx.delete('quote_tags', where: 'quote_id = ?', whereArgs: [quoteId]);
    for (final name in _cleanTags(tags)) {
      await tx.rawInsert('INSERT OR IGNORE INTO tags (name) VALUES (?)', [
        name,
      ]);
      final id = Sqflite.firstIntValue(
        await tx.rawQuery('SELECT id FROM tags WHERE name = ? COLLATE NOCASE', [
          name,
        ]),
      )!;
      await tx.insert('quote_tags', {'quote_id': quoteId, 'tag_id': id});
    }
  }

  Future<void> _dropUnusedTags() => _db.execute(
    'DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM quote_tags)',
  );

  Future<void> _checkWork(DatabaseExecutor tx, int? workId) async {
    if (workId == null) return;
    final n = Sqflite.firstIntValue(
      await tx.rawQuery('SELECT COUNT(*) FROM works WHERE id = ?', [workId]),
    );
    if (n == 0) throw const LibraryException('no such work');
  }

  @override
  Future<Quote> addQuote(QuoteDraft d) async {
    final now = _now();
    final row = _quoteRow(d);
    final id = await _db.transaction((tx) async {
      await _checkWork(tx, d.workId);
      final id = await tx.insert('quotes', {
        ...row,
        'created_at': now,
        'updated_at': now,
      });
      await _writeTags(tx, id, d.tags);
      return id;
    });
    return (await quote(id))!;
  }

  @override
  Future<Quote?> quote(int id) async {
    final rows = await _db.rawQuery('$_quoteSelect WHERE q.id = ?', [id]);
    return rows.isEmpty ? null : _quote(rows.single);
  }

  @override
  Future<Quote> updateQuote(int id, QuoteDraft d) async {
    final row = _quoteRow(d);
    await _db.transaction((tx) async {
      await _checkWork(tx, d.workId);
      final n = await tx.update(
        'quotes',
        {...row, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (n == 0) throw const LibraryException('no such quote');
      await _writeTags(tx, id, d.tags);
    });
    await _dropUnusedTags();
    return (await quote(id))!;
  }

  @override
  Future<void> deleteQuote(int id) async {
    await _db.transaction((tx) async {
      final rows = await tx.rawQuery(
        'SELECT q.server_id AS sid, w.kind AS kind FROM quotes q LEFT JOIN works w ON w.id = q.work_id WHERE q.id = ?',
        [id],
      );
      if (rows.isNotEmpty && rows.single['sid'] != null) {
        final kind = rows.single['kind'];
        final realm = kind == null
            ? Realm.loose
            : realmOfKind(workKindOf(kind));
        await _note(tx, quoteRoute(realm), rows.single['sid']! as int);
      }
      await tx.delete('quotes', where: 'id = ?', whereArgs: [id]);
    });
    await _dropUnusedTags();
  }

  @override
  Future<void> setFavorite(int id, bool favorite) async {
    await _db.update(
      'quotes',
      {'favorite': favorite ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<Quote>> quotes({
    int? workId,
    String query = '',
    bool favouritesOnly = false,
    String? tag,
    int limit = 200,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (workId != null) {
      where.add('q.work_id = ?');
      args.add(workId);
    }
    if (favouritesOnly) where.add('q.favorite = 1');
    if (tag != null && tag.trim().isNotEmpty) {
      where.add(
        'q.id IN (SELECT qt.quote_id FROM quote_tags qt JOIN tags t ON t.id = qt.tag_id WHERE t.name = ? COLLATE NOCASE)',
      );
      args.add(tag.trim());
    }
    if (query.trim().isNotEmpty) {
      final p = like(query);
      where.add(
        r"""(q.text LIKE ? ESCAPE '\' OR q.translation LIKE ? ESCAPE '\' OR q.note LIKE ? ESCAPE '\' OR q.speaker LIKE ? ESCAPE '\'
          OR q.work_id IN (SELECT w.id FROM works w WHERE w.title LIKE ? ESCAPE '\' OR w.creator LIKE ? ESCAPE '\')
          OR q.id IN (SELECT qt.quote_id FROM quote_tags qt JOIN tags t ON t.id = qt.tag_id WHERE t.name LIKE ? ESCAPE '\'))""",
      );
      args.addAll([p, p, p, p, p, p, p]);
    }
    final rows = await _db.rawQuery(
      '$_quoteSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY q.noted_at DESC, q.id DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return [for (final r in rows) _quote(r)];
  }

  @override
  Future<List<String>> tags() async {
    final rows = await _db.rawQuery(
      'SELECT name FROM tags ORDER BY name COLLATE NOCASE',
    );
    return [for (final r in rows) r['name']! as String];
  }

  @override
  Future<LibraryCounts> counts() async {
    Future<int> n(String sql) async =>
        Sqflite.firstIntValue(await _db.rawQuery(sql)) ?? 0;
    return LibraryCounts(
      works: await n('SELECT COUNT(*) FROM works'),
      quotes: await n('SELECT COUNT(*) FROM quotes'),
      favourites: await n('SELECT COUNT(*) FROM quotes WHERE favorite = 1'),
      tags: await n('SELECT COUNT(*) FROM tags'),
    );
  }

  @override
  Future<List<Work>> unsyncedWorks() async {
    final rows = await _db.query(
      'works',
      where: 'server_id IS NULL',
      orderBy: 'id',
    );
    return [for (final r in rows) _work(r)];
  }

  @override
  Future<List<Quote>> unsyncedQuotes() async {
    final rows = await _db.rawQuery(
      '$_quoteSelect WHERE q.server_id IS NULL ORDER BY q.id',
    );
    return [for (final r in rows) _quote(r)];
  }

  @override
  Future<void> setWorkServerId(int id, int serverId) async {
    await _db.update(
      'works',
      {'server_id': serverId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setQuoteServerId(int id, int serverId) async {
    await _db.update(
      'quotes',
      {'server_id': serverId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markWorkSynced(int id, String hash) async {
    await _db.update(
      'works',
      {'synced_hash': hash},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markQuoteSynced(int id, String hash) async {
    await _db.update(
      'quotes',
      {'synced_hash': hash},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Work> adoptWork(WorkDraft d, int serverId, String hash) async {
    final now = _now();
    final id = await _db.insert('works', {
      'kind': d.kind.name,
      'title': _title(d.title),
      'creator': d.creator.trim(),
      'year': d.year,
      'language': d.language.trim(),
      'created_at': now,
      'updated_at': now,
      'server_id': serverId,
      'synced_hash': hash,
    });
    return (await work(id))!;
  }

  @override
  Future<Quote> adoptQuote(QuoteDraft d, int serverId, String hash) async {
    final now = _now();
    final row = _quoteRow(d);
    final id = await _db.transaction((tx) async {
      await _checkWork(tx, d.workId);
      final id = await tx.insert('quotes', {
        ...row,
        'created_at': now,
        'updated_at': now,
        'server_id': serverId,
        'synced_hash': hash,
      });
      await _writeTags(tx, id, d.tags);
      return id;
    });
    return (await quote(id))!;
  }

  // ---- everything, for backup and export -------------------------------------------------------------

  @override
  Future<Map<String, Object?>> exportAll() async {
    final ws = await works();
    final qs = await quotes(limit: 1 << 30);
    return {
      'version': schemaVersion,
      'works': [for (final w in ws) w.toJson()],
      'quotes': [for (final q in qs.reversed) q.toJson()],
    };
  }

  /// Throws [LibraryException] unless [data] is a library [replaceAll] could write. Nothing is changed.
  static void validate(Map<String, Object?> data) {
    final works = data['works'];
    final quotes = data['quotes'];
    if (works is! List || quotes is! List) {
      throw const LibraryException('not a library');
    }
    final version = data['version'];
    if (version is! int || version > schemaVersion) {
      throw const LibraryException('a library from a newer version of the app');
    }
    final workIds = <int>{};
    for (final w in works) {
      if (w is! Map ||
          w['id'] is! int ||
          w['title'] is! String ||
          (w['title'] as String).trim().isEmpty) {
        throw const LibraryException('a work in the file is damaged');
      }
      workIds.add(w['id'] as int);
    }
    for (final q in quotes) {
      if (q is! Map ||
          q['id'] is! int ||
          q['text'] is! String ||
          (q['text'] as String).trim().isEmpty) {
        throw const LibraryException('a quote in the file is damaged');
      }
      final wid = q['work_id'];
      if (wid != null && (wid is! int || !workIds.contains(wid))) {
        throw const LibraryException(
          'a quote points at a work that is not in the file',
        );
      }
    }
  }

  @override
  Future<void> replaceAll(Map<String, Object?> data) async {
    // Validate every row before anything is cleared, so a damaged file changes nothing.
    validate(data);
    final works = data['works']! as List;
    final quotes = data['quotes']! as List;
    await _db.transaction((tx) async {
      await tx.delete('quote_tags');
      await tx.delete('quotes');
      await tx.delete('works');
      await tx.delete('tags');
      for (final w in works) {
        final m = w as Map;
        await tx.insert('works', {
          'id': m['id'],
          'kind': workKindOf(m['kind']).name,
          'title': (m['title'] as String).trim(),
          'creator': _str(m['creator']),
          'year': m['year'] is int ? m['year'] : null,
          'language': _str(m['language']),
          'created_at': _time(m['created_at']),
          'updated_at': _time(m['updated_at']),
          'server_id': m['server_id'] is int ? m['server_id'] : null,
          'synced_hash': m['synced_hash'] is String ? m['synced_hash'] : null,
        });
      }
      for (final q in quotes) {
        final m = q as Map;
        await tx.insert('quotes', {
          'id': m['id'],
          'work_id': m['work_id'],
          'text': (m['text'] as String).trim(),
          'translation': _str(m['translation']),
          'language': _str(m['language']),
          'speaker': _str(m['speaker']),
          'chapter': _str(m['chapter']),
          'location': _str(m['location']),
          'note': _str(m['note']),
          'color': quoteColors.contains(m['color']) ? m['color'] : 'yellow',
          'favorite': m['favorite'] == true ? 1 : 0,
          'noted_at': _time(m['noted_at']),
          'source': _str(m['source']).isEmpty ? 'manual' : _str(m['source']),
          'created_at': _time(m['created_at']),
          'updated_at': _time(m['updated_at']),
          'server_id': m['server_id'] is int ? m['server_id'] : null,
          'synced_hash': m['synced_hash'] is String ? m['synced_hash'] : null,
        });
        final tags = m['tags'];
        await _writeTags(
          tx,
          m['id'] as int,
          tags is List
              ? [
                  for (final t in tags)
                    if (t is String) t,
                ]
              : const [],
        );
      }
    });
  }

  String _str(Object? v) => v is String ? v.trim() : '';

  String _time(Object? v) =>
      (v is String ? DateTime.tryParse(v) : null)?.toUtc().toIso8601String() ??
      _now();

  Future<void> close() => _db.close();
}
