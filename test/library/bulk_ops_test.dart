import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tippani/library/bulk_ops.dart';
import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  var tick = 0;
  DateTime clock() => DateTime.utc(2026, 11, 6, 8, 0, tick++);

  late SqliteLibraryStore store;
  late BulkOps bulk;

  setUp(() async {
    tick = 0;
    store = await SqliteLibraryStore.open(
      inMemoryDatabasePath,
      clock: clock,
      singleInstance: false,
    );
    bulk = BulkOps(store);
  });

  tearDown(() => store.close());

  Future<List<Quote>> three() async {
    final w = await store.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau'),
    );
    for (final t in ['one', 'two', 'three']) {
      await store.addQuote(QuoteDraft(text: t, workId: w.id, tags: ['a']));
    }
    return store.quotes(workId: w.id);
  }

  test(
    'recolouring many is an edit of each: new updated_at, same words',
    () async {
      final qs = await three();
      final before = {for (final q in qs) q.id: q.updatedAt};
      final r = await bulk.recolour(qs, 'blue');
      expect(r.changed, 3);
      for (final q in await store.quotes()) {
        expect(q.color, 'blue');
        expect(
          q.updatedAt.isAfter(before[q.id]!),
          isTrue,
          reason: 'sync sees it',
        );
      }
      // doing it again changes nothing and touches nothing
      final again = await bulk.recolour(await store.quotes(), 'blue');
      expect(again.changed, 0);
      expect(again.skipped, 3);
    },
  );

  test('tags are added to each, once, and taken off again', () async {
    final qs = await three();
    await bulk.addTag(qs, '#Wisdom');
    expect(
      (await store.quotes()).every((q) => q.tags.contains('Wisdom')),
      isTrue,
    );
    final twice = await bulk.addTag(await store.quotes(), 'wisdom');
    expect(twice.changed, 0, reason: 'any letter case is the same tag');
    final off = await bulk.removeTag(await store.quotes(), 'WISDOM');
    expect(off.changed, 3);
    final left = await store.quotes();
    expect(
      left.every((q) => q.tags.length == 1 && q.tags.single == 'a'),
      isTrue,
    );
  });

  test('favourite and one field are set on all', () async {
    final qs = await three();
    await bulk.favourite(qs, true);
    expect((await store.quotes()).every((q) => q.favorite), isTrue);
    await bulk.setQuoteField(
      await store.quotes(),
      QuoteField.chapter,
      ' Economy ',
    );
    expect((await store.quotes()).every((q) => q.chapter == 'Economy'), isTrue);
    await bulk.setQuoteField(await store.quotes(), QuoteField.speaker, '');
    expect((await store.quotes()).every((q) => q.speaker.isEmpty), isTrue);
  });

  test(
    'works: a creator for several, and a year that is not a number is refused',
    () async {
      final a = await store.addWork(const WorkDraft(title: 'A'));
      final b = await store.addWork(const WorkDraft(title: 'B'));
      final r = await bulk.setWorkField([a, b], WorkField.creator, 'Anon');
      expect(r.changed, 2);
      expect((await store.work(a.id))!.creator, 'Anon');
      final bad = await bulk.setWorkField([a, b], WorkField.year, 'soon');
      expect(bad.changed, 0);
      expect(bad.note, isNotEmpty);
      await bulk.setWorkField([a, b], WorkField.year, '1999');
      expect((await store.work(b.id))!.year, 1999);
    },
  );

  test(
    'boards: standalone quotes are filed, quotes of a book are left alone',
    () async {
      final inBook = await three();
      final loose = await store.addQuote(const QuoteDraft(text: 'proverb'));
      final board = await store.addBoard('Proverbs');
      final r = await bulk.moveToBoard([...inBook, loose], board.id);
      expect(r.changed, 1);
      expect(r.skipped, 3);
      expect(r.note, isNotEmpty);
      expect((await store.quote(loose.id))!.boardId, board.id);
      final off = await bulk.moveToBoard([
        (await store.quote(loose.id))!,
      ], null);
      expect(off.changed, 1);
      expect((await store.quote(loose.id))!.boardId, isNull);
    },
  );

  test('delete can be undone, with everything the quotes said', () async {
    final qs = await three();
    await bulk.favourite([qs.first], true);
    final gone = await bulk.delete(await store.quotes());
    expect(await store.quotes(), isEmpty);
    await bulk.restore(gone);
    final back = await store.quotes();
    expect(back.map((q) => q.text).toSet(), {'one', 'two', 'three'});
    expect(back.every((q) => q.tags.contains('a')), isTrue);
    expect(back.where((q) => q.favorite), hasLength(1));
  });

  test(
    'merging works moves the quotes and removes the others; kinds do not mix',
    () async {
      final a = await store.addWork(const WorkDraft(title: 'Walden'));
      final b = await store.addWork(
        const WorkDraft(title: 'Walden (2nd copy)'),
      );
      final film = await store.addWork(
        const WorkDraft(title: 'Walden the film', kind: WorkKind.film),
      );
      await store.addQuote(QuoteDraft(text: 'from a', workId: a.id));
      await store.addQuote(QuoteDraft(text: 'from b', workId: b.id));
      await store.addQuote(QuoteDraft(text: 'from film', workId: film.id));
      expect(canMerge(a, film), isFalse);
      final r = await bulk.mergeWorks(a, [b, film]);
      expect(r.changed, 1);
      expect(r.skipped, 1);
      expect(await store.work(b.id), isNull);
      expect(await store.work(film.id), isNotNull);
      final onA = await store.quotes(workId: a.id);
      expect(onA.map((q) => q.text).toSet(), {'from a', 'from b'});
      expect(
        (await store.quotes(workId: film.id)).single.text,
        'from film',
        reason: 'the film keeps its own line',
      );
    },
  );
}
