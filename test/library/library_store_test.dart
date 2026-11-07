import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  var tick = 0;
  DateTime clock() => DateTime.utc(2026, 11, 6, 8, 0, tick++);

  late SqliteLibraryStore store;

  setUp(() async {
    tick = 0;
    store = await SqliteLibraryStore.open(
      inMemoryDatabasePath,
      clock: clock,
      singleInstance: false,
    );
  });

  tearDown(() => store.close());

  Future<Work> walden() => store.addWork(
    const WorkDraft(
      title: 'Walden',
      creator: 'Henry David Thoreau',
      year: 1854,
    ),
  );

  group('works', () {
    test('a work is kept with its title, creator, year and kind', () async {
      final w = await store.addWork(
        const WorkDraft(
          title: '  Casablanca ',
          kind: WorkKind.film,
          creator: 'Michael Curtiz',
          year: 1942,
        ),
      );
      expect(w.title, 'Casablanca');
      expect(w.kind, WorkKind.film);
      expect(w.creator, 'Michael Curtiz');
      expect(w.year, 1942);
      expect((await store.work(w.id))?.title, 'Casablanca');
    });

    test('a work needs a title, and not a huge one', () async {
      await expectLater(
        store.addWork(const WorkDraft(title: '   ')),
        throwsA(isA<LibraryException>()),
      );
      await expectLater(
        store.addWork(WorkDraft(title: 'x' * 501)),
        throwsA(isA<LibraryException>()),
      );
    });

    test('works are listed by title, filtered by kind, and searched by title or creator', () async {
      await store.addWork(const WorkDraft(title: 'walden', creator: 'Thoreau'));
      await store.addWork(
        const WorkDraft(title: 'Anna Karenina', creator: 'Tolstoy'),
      );
      await store.addWork(
        const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
      );
      expect((await store.works()).map((w) => w.title), [
        'Anna Karenina',
        'Casablanca',
        'walden',
      ]);
      expect((await store.works(kind: WorkKind.film)).map((w) => w.title), [
        'Casablanca',
      ]);
      expect((await store.works(query: 'tolst')).map((w) => w.title), [
        'Anna Karenina',
      ]);
      expect((await store.works(query: 'WALD')).map((w) => w.title), [
        'walden',
      ]);
    });

    test('a % or _ in a search is the character, not a wildcard', () async {
      await store.addWork(const WorkDraft(title: '100% True'));
      await store.addWork(const WorkDraft(title: 'Plain'));
      expect((await store.works(query: '%')).map((w) => w.title), [
        '100% True',
      ]);
      expect((await store.works(query: '_')), isEmpty);
    });

    test('updating a work changes it and says when', () async {
      final w = await walden();
      final u = await store.updateWork(
        w.id,
        const WorkDraft(
          title: 'Walden; or, Life in the Woods',
          creator: 'H. D. Thoreau',
          year: 1854,
        ),
      );
      expect(u.title, 'Walden; or, Life in the Woods');
      expect(u.updatedAt.isAfter(w.updatedAt), isTrue);
      expect(u.createdAt, w.createdAt);
      await expectLater(
        store.updateWork(9999, const WorkDraft(title: 'x')),
        throwsA(isA<LibraryException>()),
      );
    });

    test(
      'deleting a work deletes its quotes and the tags only they used',
      () async {
        final w = await walden();
        await store.addQuote(
          QuoteDraft(
            text: 'I went to the woods',
            workId: w.id,
            tags: const ['nature'],
          ),
        );
        final keep = await store.addQuote(
          const QuoteDraft(text: 'A standalone', tags: ['nature', 'proverb']),
        );
        await store.deleteWork(w.id);
        expect(await store.work(w.id), isNull);
        expect((await store.quotes()).map((q) => q.id), [keep.id]);
        expect(await store.tags(), ['nature', 'proverb']);
      },
    );
  });

  group('quotes', () {
    test('a quote is kept with everything the reader gave it', () async {
      final w = await walden();
      final q = await store.addQuote(
        QuoteDraft(
          text: '  I went to the woods because I wished to live deliberately. ',
          workId: w.id,
          translation: 'a translation',
          language: 'English',
          speaker: 'Thoreau',
          chapter: 'Where I Lived',
          location: 'p. 90',
          note: 'reread in winter',
          color: 'green',
          favorite: true,
          source: 'capture',
          tags: const ['nature', 'Deliberate', 'nature'],
        ),
      );
      expect(
        q.text,
        'I went to the woods because I wished to live deliberately.',
      );
      expect(q.workId, w.id);
      expect(q.translation, 'a translation');
      expect(q.chapter, 'Where I Lived');
      expect(q.location, 'p. 90');
      expect(q.color, 'green');
      expect(q.favorite, isTrue);
      expect(q.source, 'capture');
      expect(q.tags, [
        'Deliberate',
        'nature',
      ], reason: 'a repeated tag is kept once');
    });

    test(
      'a quote needs its words, and must point at a work that exists',
      () async {
        await expectLater(
          store.addQuote(const QuoteDraft(text: '   ')),
          throwsA(isA<LibraryException>()),
        );
        await expectLater(
          store.addQuote(const QuoteDraft(text: 'x', workId: 42)),
          throwsA(isA<LibraryException>()),
        );
        expect(
          (await store.counts()).quotes,
          0,
          reason: 'a refused quote leaves nothing behind',
        );
      },
    );

    test('an unknown colour becomes the default, and an empty source becomes manual', () async {
      final q = await store.addQuote(
        const QuoteDraft(text: 'x', color: 'chartreuse', source: ' '),
      );
      expect(q.color, 'yellow');
      expect(q.source, 'manual');
    });

    test(
      'quotes come newest met first, and noted_at defaults to now',
      () async {
        final a = await store.addQuote(
          QuoteDraft(text: 'older', notedAt: DateTime.utc(2025, 1, 1)),
        );
        final b = await store.addQuote(const QuoteDraft(text: 'newest'));
        final c = await store.addQuote(
          QuoteDraft(text: 'middle', notedAt: DateTime.utc(2026, 1, 1)),
        );
        expect((await store.quotes()).map((q) => q.id), [b.id, c.id, a.id]);
      },
    );

    test('updating a quote replaces its fields and its tags, and drops tags nothing uses', () async {
      final q = await store.addQuote(
        const QuoteDraft(text: 'first', tags: ['a', 'b']),
      );
      final u = await store.updateQuote(
        q.id,
        const QuoteDraft(text: 'second', tags: ['b', 'c'], note: 'n'),
      );
      expect(u.text, 'second');
      expect(u.note, 'n');
      expect(u.tags, ['b', 'c']);
      expect(await store.tags(), [
        'b',
        'c',
      ], reason: 'a is used by nothing now');
      await expectLater(
        store.updateQuote(9999, const QuoteDraft(text: 'x')),
        throwsA(isA<LibraryException>()),
      );
    });

    test('a refused update changes nothing', () async {
      final q = await store.addQuote(
        const QuoteDraft(text: 'keep me', tags: ['t']),
      );
      await expectLater(
        store.updateQuote(q.id, const QuoteDraft(text: 'x', workId: 77)),
        throwsA(isA<LibraryException>()),
      );
      final same = (await store.quote(q.id))!;
      expect(same.text, 'keep me');
      expect(same.tags, ['t']);
    });

    test('favourite is a toggle and is a filter', () async {
      final a = await store.addQuote(const QuoteDraft(text: 'a'));
      await store.addQuote(const QuoteDraft(text: 'b'));
      await store.setFavorite(a.id, true);
      expect((await store.quotes(favouritesOnly: true)).map((q) => q.id), [
        a.id,
      ]);
      await store.setFavorite(a.id, false);
      expect(await store.quotes(favouritesOnly: true), isEmpty);
    });

    test('deleting a quote removes it and the tags only it used', () async {
      final q = await store.addQuote(
        const QuoteDraft(text: 'gone', tags: ['solo']),
      );
      await store.addQuote(const QuoteDraft(text: 'stays', tags: ['shared']));
      await store.deleteQuote(q.id);
      expect(await store.quote(q.id), isNull);
      expect(await store.tags(), ['shared']);
    });

    test('paging walks the list in order', () async {
      for (var i = 0; i < 5; i++) {
        await store.addQuote(QuoteDraft(text: 'q$i'));
      }
      final first = await store.quotes(limit: 2);
      final second = await store.quotes(limit: 2, offset: 2);
      final third = await store.quotes(limit: 2, offset: 4);
      expect([...first, ...second, ...third].map((q) => q.text), [
        'q4',
        'q3',
        'q2',
        'q1',
        'q0',
      ]);
    });
  });

  group('search and filters', () {
    late Work w;
    setUp(() async {
      w = await store.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      await store.addQuote(
        QuoteDraft(
          text: 'I went to the woods',
          workId: w.id,
          tags: const ['nature'],
        ),
      );
      await store.addQuote(
        const QuoteDraft(
          text: 'Never put off till tomorrow',
          speaker: 'Franklin',
          note: 'procrastination',
          tags: ['proverb'],
        ),
      );
      await store.addQuote(
        const QuoteDraft(
          text: 'A stitch in time',
          translation: 'bhalo kajer deri noy',
        ),
      );
    });

    test('matches the words, translation, note, speaker, the work\'s title and creator, and tags', () async {
      Future<List<String>> find(String q) async => [
        for (final x in await store.quotes(query: q)) x.text,
      ];
      expect(await find('woods'), ['I went to the woods']);
      expect(await find('deri'), ['A stitch in time']);
      expect(await find('procrastin'), ['Never put off till tomorrow']);
      expect(await find('franklin'), ['Never put off till tomorrow']);
      expect(await find('walden'), [
        'I went to the woods',
      ], reason: 'by the work it came from');
      expect(await find('thoreau'), ['I went to the woods']);
      expect(await find('PROVERB'), [
        'Never put off till tomorrow',
      ], reason: 'by tag, case-insensitive');
      expect(await find('zzz'), isEmpty);
    });

    test('filters by work, by tag, and combines with a query', () async {
      expect((await store.quotes(workId: w.id)).length, 1);
      expect((await store.quotes(tag: 'NATURE')).length, 1);
      expect((await store.quotes(tag: 'nature', query: 'woods')).length, 1);
      expect((await store.quotes(tag: 'nature', query: 'stitch')).length, 0);
    });

    test('a % in a search is the character', () async {
      await store.addQuote(const QuoteDraft(text: 'Half of it, 50% of it'));
      expect((await store.quotes(query: '%')).map((q) => q.text), [
        'Half of it, 50% of it',
      ]);
    });
  });

  test('counts say how much the library holds', () async {
    final w = await walden();
    final q = await store.addQuote(
      QuoteDraft(text: 'a', workId: w.id, tags: const ['x', 'y']),
    );
    await store.addQuote(const QuoteDraft(text: 'b'));
    await store.setFavorite(q.id, true);
    final c = await store.counts();
    expect((c.works, c.quotes, c.favourites, c.tags), (1, 2, 1, 2));
  });

  group('export and replace', () {
    test(
      'a library exported and replaced into another is the same library',
      () async {
        final w = await walden();
        await store.addQuote(
          QuoteDraft(
            text: 'with a work',
            workId: w.id,
            tags: const ['nature'],
            favorite: true,
            note: 'n',
            color: 'blue',
          ),
        );
        await store.addQuote(
          const QuoteDraft(text: 'standalone', tags: ['proverb', 'nature']),
        );
        final data = await store.exportAll();

        final other = await SqliteLibraryStore.open(
          inMemoryDatabasePath,
          clock: clock,
        );
        await other.addQuote(const QuoteDraft(text: 'will be replaced'));
        await other.replaceAll(data);
        expect(await other.exportAll(), data);
        expect((await other.quotes()).map((q) => q.text).toSet(), {
          'with a work',
          'standalone',
        });
        expect((await other.quotes(query: 'with a work')).single.tags, [
          'nature',
        ]);
        await other.close();
      },
    );

    test('a damaged file changes nothing', () async {
      final w = await walden();
      await store.addQuote(QuoteDraft(text: 'keep', workId: w.id));
      final before = await store.exportAll();
      for (final bad in <Map<String, Object?>>[
        {'version': 1, 'works': 'x', 'quotes': []},
        {
          'version': 1,
          'works': [],
          'quotes': [
            {'id': 1, 'text': '   '},
          ],
        },
        {
          'version': 1,
          'works': [
            {'id': 1, 'title': ''},
          ],
          'quotes': [],
        },
        {
          'version': 1,
          'works': [],
          'quotes': [
            {'id': 1, 'text': 'x', 'work_id': 5},
          ],
        },
        {'version': 99, 'works': [], 'quotes': []},
        {'works': [], 'quotes': []},
      ]) {
        await expectLater(
          store.replaceAll(bad),
          throwsA(isA<LibraryException>()),
          reason: '$bad',
        );
        expect(await store.exportAll(), before, reason: 'untouched after $bad');
      }
    });

    test('odd values in a file are cleaned, not trusted', () async {
      await store.replaceAll({
        'version': 1,
        'works': [
          {
            'id': 3,
            'kind': 'spaceship',
            'title': '  T ',
            'creator': 5,
            'year': 'x',
          },
        ],
        'quotes': [
          {
            'id': 8,
            'work_id': 3,
            'text': ' hello ',
            'color': 'ultraviolet',
            'favorite': 'yes',
            'tags': ['a', 7, ' a ', ''],
            'noted_at': 'not a date',
          },
        ],
      });
      final w = (await store.work(3))!;
      expect(w.kind, WorkKind.other);
      expect(w.title, 'T');
      expect(w.creator, '');
      expect(w.year, isNull);
      final q = (await store.quote(8))!;
      expect(q.text, 'hello');
      expect(q.color, 'yellow');
      expect(q.favorite, isFalse);
      expect(q.tags, ['a']);
    });
  });
  group('what the server has not been given', () {
    test('only items with no server id are unsynced, oldest first', () async {
      final a = await walden();
      final b = await store.addWork(const WorkDraft(title: 'B'));
      final q1 = await store.addQuote(QuoteDraft(text: 'one', workId: a.id));
      final q2 = await store.addQuote(const QuoteDraft(text: 'two'));
      await store.setWorkServerId(a.id, 41);
      await store.setQuoteServerId(q1.id, 77);
      expect((await store.unsyncedWorks()).map((w) => w.id), [b.id]);
      expect((await store.unsyncedQuotes()).map((q) => q.id), [q2.id]);
      expect((await store.work(a.id))!.serverId, 41);
      expect((await store.quote(q1.id))!.serverId, 77);
    });

    test('being on the server is not an edit: updated_at does not move, and nothing else changes', () async {
      final w = await walden();
      final q = await store.addQuote(
        QuoteDraft(
          text: 'kept',
          workId: w.id,
          tags: const ['t'],
          favorite: true,
        ),
      );
      await store.setWorkServerId(w.id, 5);
      await store.setQuoteServerId(q.id, 6);
      final w2 = (await store.work(w.id))!;
      final q2 = (await store.quote(q.id))!;
      expect(w2.updatedAt, w.updatedAt);
      expect(q2.updatedAt, q.updatedAt);
      expect(q2.text, 'kept');
      expect(q2.tags, ['t']);
      expect(q2.favorite, isTrue);
    });

    test(
      'an unsynced quote comes back with its tags, as any other quote does',
      () async {
        await store.addQuote(const QuoteDraft(text: 'x', tags: ['b', 'a']));
        expect((await store.unsyncedQuotes()).single.tags, ['a', 'b']);
      },
    );

    test('a server id survives a backup and restore', () async {
      final w = await walden();
      await store.setWorkServerId(w.id, 9);
      final data = await store.exportAll();
      await store.replaceAll(data);
      expect((await store.work(w.id))!.serverId, 9);
      expect(await store.unsyncedWorks(), isEmpty);
    });
  });

  group('what the server and the phone last agreed', () {
    test(
      'it is kept, is not an edit, and survives a real edit and a backup',
      () async {
        final w = await walden();
        final q = await store.addQuote(QuoteDraft(text: 'kept', workId: w.id));
        expect(w.syncedHash, isNull);
        await store.markWorkSynced(w.id, 'aaaa');
        await store.markQuoteSynced(q.id, 'bbbb');
        expect((await store.work(w.id))!.syncedHash, 'aaaa');
        expect((await store.work(w.id))!.updatedAt, w.updatedAt);
        expect((await store.quote(q.id))!.syncedHash, 'bbbb');
        expect((await store.quote(q.id))!.updatedAt, q.updatedAt);

        await store.updateQuote(q.id, QuoteDraft(text: 'edited', workId: w.id));
        await store.updateWork(w.id, const WorkDraft(title: 'Walden 2'));
        expect((await store.quote(q.id))!.syncedHash, 'bbbb');
        expect((await store.work(w.id))!.syncedHash, 'aaaa');

        await store.replaceAll(await store.exportAll());
        expect((await store.quote(q.id))!.syncedHash, 'bbbb');
        expect((await store.work(w.id))!.syncedHash, 'aaaa');
      },
    );

    test('adopting a work and a quote from the server links and agrees them in one write, with tags', () async {
      final w = await store.adoptWork(
        const WorkDraft(title: 'Dune', creator: 'Herbert'),
        12,
        'h1',
      );
      final q = await store.adoptQuote(
        QuoteDraft(
          text: 'Fear.',
          workId: w.id,
          tags: const ['b', 'a'],
          source: 'import',
        ),
        34,
        'h2',
      );
      expect(w.serverId, 12);
      expect(w.syncedHash, 'h1');
      expect(q.serverId, 34);
      expect(q.syncedHash, 'h2');
      expect(q.tags, ['a', 'b']);
      expect(await store.unsyncedWorks(), isEmpty);
      expect(await store.unsyncedQuotes(), isEmpty);
    });

    test(
      'adopting a quote for a work that is not here changes nothing',
      () async {
        await expectLater(
          store.adoptQuote(const QuoteDraft(text: 'x', workId: 999), 1, 'h'),
          throwsA(isA<LibraryException>()),
        );
        expect((await store.counts()).quotes, 0);
      },
    );

    test(
      'a library made before this existed is upgraded and keeps everything',
      () async {
        final dir = await Directory.systemTemp.createTemp('tippani_upgrade');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/library.db';
        final old = await openDatabase(
          path,
          version: 1,
          singleInstance: false,
          onCreate: (db, v) async {
            await db.execute(
              'CREATE TABLE works (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, title TEXT NOT NULL, creator TEXT NOT NULL DEFAULT \'\', year INTEGER, language TEXT NOT NULL DEFAULT \'\', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, server_id INTEGER)',
            );
            await db.execute(
              'CREATE TABLE quotes (id INTEGER PRIMARY KEY AUTOINCREMENT, work_id INTEGER REFERENCES works(id) ON DELETE CASCADE, text TEXT NOT NULL, translation TEXT NOT NULL DEFAULT \'\', language TEXT NOT NULL DEFAULT \'\', speaker TEXT NOT NULL DEFAULT \'\', chapter TEXT NOT NULL DEFAULT \'\', location TEXT NOT NULL DEFAULT \'\', note TEXT NOT NULL DEFAULT \'\', color TEXT NOT NULL DEFAULT \'yellow\', favorite INTEGER NOT NULL DEFAULT 0, noted_at TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'manual\', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, server_id INTEGER)',
            );
            await db.execute(
              'CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
            );
            await db.execute(
              'CREATE TABLE quote_tags (quote_id INTEGER NOT NULL, tag_id INTEGER NOT NULL, PRIMARY KEY (quote_id, tag_id))',
            );
            await db.insert('works', {
              'kind': 'book',
              'title': 'Old',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
              'server_id': 3,
            });
            await db.insert('quotes', {
              'work_id': 1,
              'text': 'still here',
              'noted_at': '2026-01-01T00:00:00.000Z',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            });
          },
        );
        await old.close();

        final upgraded = await SqliteLibraryStore.open(
          path,
          singleInstance: false,
        );
        addTearDown(upgraded.close);
        final w = (await upgraded.works()).single;
        expect(w.title, 'Old');
        expect(w.serverId, 3);
        expect(w.syncedHash, isNull);
        expect((await upgraded.quotes()).single.text, 'still here');
        await upgraded.markWorkSynced(w.id, 'now works');
        expect((await upgraded.work(w.id))!.syncedHash, 'now works');
      },
    );
  });

  group('deleting what the server holds', () {
    test(
      'a linked quote leaves a note for the server, in the right table',
      () async {
        final w = await walden();
        await store.setWorkServerId(w.id, 4);
        final q = await store.addQuote(QuoteDraft(text: 'One.', workId: w.id));
        await store.setQuoteServerId(q.id, 9);
        await store.deleteQuote(q.id);
        final p = (await store.pendingDeletions()).single;
        expect(p.route, '/annotations');
        expect(p.serverId, 9);
      },
    );

    test('a film quote and a loose quote use their own tables', () async {
      final f = await store.addWork(
        const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
      );
      final fq = await store.addQuote(QuoteDraft(text: 'Kid.', workId: f.id));
      final lq = await store.addQuote(const QuoteDraft(text: 'Loose.'));
      await store.setQuoteServerId(fq.id, 1);
      await store.setQuoteServerId(lq.id, 2);
      await store.deleteQuote(fq.id);
      await store.deleteQuote(lq.id);
      expect(
        [for (final d in await store.pendingDeletions()) d.route],
        ['/dialogues', '/quotes'],
      );
    });

    test(
      'deleting a linked work notes the work and each linked quote under it',
      () async {
        final w = await walden();
        await store.setWorkServerId(w.id, 4);
        final a = await store.addQuote(QuoteDraft(text: 'A.', workId: w.id));
        await store.addQuote(QuoteDraft(text: 'Only here.', workId: w.id));
        await store.setQuoteServerId(a.id, 11);
        await store.deleteWork(w.id);
        final notes = [
          for (final d in await store.pendingDeletions())
            '${d.route}/${d.serverId}',
        ];
        expect(notes, ['/books/4', '/annotations/11']);
        expect(await store.quotes(), isEmpty);
      },
    );

    test('nothing is noted for what was never on the server', () async {
      final w = await walden();
      final q = await store.addQuote(QuoteDraft(text: 'One.', workId: w.id));
      await store.deleteQuote(q.id);
      await store.deleteWork(w.id);
      expect(await store.pendingDeletions(), isEmpty);
    });

    test('dropping, for what the server deleted, notes nothing; clearing removes a note', () async {
      final w = await walden();
      await store.setWorkServerId(w.id, 4);
      final q = await store.addQuote(QuoteDraft(text: 'One.', workId: w.id));
      await store.setQuoteServerId(q.id, 9);
      await store.dropQuote(q.id);
      await store.dropWork(w.id);
      expect(await store.pendingDeletions(), isEmpty);

      final w2 = await walden();
      await store.setWorkServerId(w2.id, 5);
      await store.deleteWork(w2.id);
      final p = (await store.pendingDeletions()).single;
      await store.clearDeletion(p.id);
      expect(await store.pendingDeletions(), isEmpty);
    });

    test(
      'unlinking forgets the server id and the agreement, so it is sent as new',
      () async {
        final w = await walden();
        await store.setWorkServerId(w.id, 4);
        await store.markWorkSynced(w.id, 'h');
        final q = await store.addQuote(QuoteDraft(text: 'One.', workId: w.id));
        await store.setQuoteServerId(q.id, 9);
        await store.markQuoteSynced(q.id, 'h');
        await store.unlinkWork(w.id);
        await store.unlinkQuote(q.id);
        final w2 = (await store.work(w.id))!;
        final q2 = (await store.quote(q.id))!;
        expect(
          [w2.serverId, w2.syncedHash, q2.serverId, q2.syncedHash],
          [null, null, null, null],
        );
        expect(await store.unsyncedWorks(), hasLength(1));
        expect(await store.unsyncedQuotes(), hasLength(1));
      },
    );

    test(
      'a library from before this is upgraded and can note deletes',
      () async {
        final dir = await Directory.systemTemp.createTemp('tippani_upgrade3');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/lib.db';
        final old = await openDatabase(
          path,
          version: 2,
          singleInstance: false,
          onCreate: (db, v) async {
            await db.execute(
              'CREATE TABLE works (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, title TEXT NOT NULL, creator TEXT NOT NULL DEFAULT "", year INTEGER, language TEXT NOT NULL DEFAULT "", created_at TEXT NOT NULL, updated_at TEXT NOT NULL, server_id INTEGER, synced_hash TEXT)',
            );
            await db.execute(
              'CREATE TABLE quotes (id INTEGER PRIMARY KEY AUTOINCREMENT, work_id INTEGER REFERENCES works(id) ON DELETE CASCADE, text TEXT NOT NULL, translation TEXT NOT NULL DEFAULT "", language TEXT NOT NULL DEFAULT "", speaker TEXT NOT NULL DEFAULT "", chapter TEXT NOT NULL DEFAULT "", location TEXT NOT NULL DEFAULT "", note TEXT NOT NULL DEFAULT "", color TEXT NOT NULL DEFAULT "yellow", favorite INTEGER NOT NULL DEFAULT 0, noted_at TEXT NOT NULL, source TEXT NOT NULL DEFAULT "manual", created_at TEXT NOT NULL, updated_at TEXT NOT NULL, server_id INTEGER, synced_hash TEXT)',
            );
            await db.execute(
              'CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
            );
            await db.execute(
              'CREATE TABLE quote_tags (quote_id INTEGER NOT NULL REFERENCES quotes(id) ON DELETE CASCADE, tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY (quote_id, tag_id))',
            );
            await db.insert('works', {
              'kind': 'book',
              'title': 'Old',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
              'server_id': 3,
            });
          },
        );
        await old.close();
        final upgraded = await SqliteLibraryStore.open(
          path,
          singleInstance: false,
        );
        addTearDown(upgraded.close);
        final w = (await upgraded.works()).single;
        expect(w.title, 'Old');
        await upgraded.deleteWork(w.id);
        expect((await upgraded.pendingDeletions()).single.route, '/books');
      },
    );
  });

  group('the change stream', () {
    test('fires for what the reader does', () async {
      var n = 0;
      final sub = store.changes.listen((_) => n++);
      addTearDown(sub.cancel);
      final w = await walden();
      expect(n, 1);
      final q = await store.addQuote(QuoteDraft(text: 'One.', workId: w.id));
      expect(n, 2);
      await store.updateQuote(q.id, QuoteDraft(text: 'One!', workId: w.id));
      expect(n, 3);
      await store.setFavorite(q.id, true);
      expect(n, 4);
      await store.updateWork(w.id, const WorkDraft(title: 'Walden II'));
      expect(n, 5);
      await store.deleteQuote(q.id);
      expect(n, 6);
      await store.deleteWork(w.id);
      expect(n, 7);
    });

    test('is silent for what a sync writes', () async {
      var n = 0;
      final sub = store.changes.listen((_) => n++);
      addTearDown(sub.cancel);
      final w = await store.adoptWork(const WorkDraft(title: 'Dune'), 1, 'h');
      final q = await store.adoptQuote(
        QuoteDraft(text: 'Fear.', workId: w.id),
        2,
        'h',
      );
      await store.setWorkServerId(w.id, 3);
      await store.setQuoteServerId(q.id, 4);
      await store.markWorkSynced(w.id, 'x');
      await store.markQuoteSynced(q.id, 'x');
      await store.unlinkQuote(q.id);
      await store.unlinkWork(w.id);
      await store.dropQuote(q.id);
      await store.dropWork(w.id);
      expect(n, 0);
    });
  });

  group('what the server knows about a work', () {
    const details = WorkDetails(
      description: 'About living simply.',
      genres: ['Essay'],
      pages: 352,
      cast: [CastMember(character: 'Thoreau')],
    );

    test('is kept with the work, and changes nothing else about it', () async {
      final w = await walden();
      await store.setWorkDetails(w.id, details);
      final back = (await store.work(w.id))!;
      expect(back.details.description, 'About living simply.');
      expect(back.details.genres, ['Essay']);
      expect(back.details.cast.single.character, 'Thoreau');
      expect(back.updatedAt, w.updatedAt);
      expect(back.title, w.title);
    });

    test('an empty record clears it', () async {
      final w = await walden();
      await store.setWorkDetails(w.id, details);
      await store.setWorkDetails(w.id, const WorkDetails());
      expect((await store.work(w.id))!.details.isEmpty, isTrue);
    });

    test('an edit of the work keeps it', () async {
      final w = await walden();
      await store.setWorkDetails(w.id, details);
      await store.updateWork(w.id, const WorkDraft(title: 'Walden II'));
      expect(
        (await store.work(w.id))!.details.description,
        'About living simply.',
      );
    });

    test('goes into a backup and comes back out of it', () async {
      final w = await walden();
      await store.setWorkDetails(w.id, details);
      await store.setWorkCover(w.id, '0123456789abcdef.png');
      final data = await store.exportAll();
      await store.replaceAll(data);
      final back = (await store.works()).single;
      expect(back.details.description, 'About living simply.');
      expect(back.cover, '0123456789abcdef.png');
    });
  });
}
