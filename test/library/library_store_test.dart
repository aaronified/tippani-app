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
}
