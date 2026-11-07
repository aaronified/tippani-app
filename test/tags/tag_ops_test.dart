import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/tags/tag_ops.dart';

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

  Future<Quote> quote(String text, List<String> tags) =>
      store.addQuote(QuoteDraft(text: text, tags: tags));

  Future<Map<String, List<String>>> tagged() async => {
    for (final q in await store.quotes()) q.text: q.tags..sort(),
  };

  test('counts how many quotes wear each tag', () async {
    await quote('a', ['life', 'Craft']);
    await quote('b', ['life']);
    expect(await localTagCounts(store), {'life': 2, 'Craft': 1});
  });

  test(
    'renaming puts the new name on every quote and retires the old',
    () async {
      await quote('a', ['life', 'craft']);
      await quote('b', ['life']);
      final changed = await renameTagLocal(store, 'life', 'living');
      expect(changed, 2);
      expect(await tagged(), {
        'a': ['craft', 'living'],
        'b': ['living'],
      });
      expect(await store.tags(), ['craft', 'living']);
    },
  );

  test('a renamed quote counts as edited, so it syncs', () async {
    final q = await quote('a', ['life']);
    await renameTagLocal(store, 'life', 'living');
    final after = (await store.quote(q.id))!;
    expect(after.updatedAt.isAfter(q.updatedAt), isTrue);
    expect(after.text, q.text);
  });

  test(
    'renaming into a tag that exists merges, and nothing is doubled',
    () async {
      await quote('a', ['life', 'living']);
      await quote('b', ['life']);
      await renameTagLocal(store, 'life', 'Living');
      final got = await tagged();
      expect(got['a'], hasLength(1));
      expect(got['a']!.single.toLowerCase(), 'living');
      expect(got['b']!.single.toLowerCase(), 'living');
      expect((await store.tags()), hasLength(1));
    },
  );

  test('only the capitals can change, and the new spelling is kept', () async {
    await quote('a', ['Life']);
    await quote('b', ['Life']);
    await renameTagLocal(store, 'Life', 'life');
    expect(await store.tags(), ['life']);
    expect(await tagged(), {
      'a': ['life'],
      'b': ['life'],
    });
  });

  test('merging folds several tags into the one kept', () async {
    await quote('a', ['translation']);
    await quote('b', ['on translation', 'craft']);
    await quote('c', ['translations', 'translation']);
    final changed = await mergeTagsLocal(store, 'translation', [
      'on translation',
      'translations',
    ]);
    expect(changed, 2);
    expect(await tagged(), {
      'a': ['translation'],
      'b': ['craft', 'translation'],
      'c': ['translation'],
    });
    expect(await store.tags(), ['craft', 'translation']);
  });

  test('deleting takes the tag off and leaves the quotes', () async {
    await quote('a', ['life', 'craft']);
    await quote('b', ['life']);
    expect(await deleteTagLocal(store, 'life'), 2);
    expect(await tagged(), {
      'a': ['craft'],
      'b': <String>[],
    });
    expect(await store.tags(), ['craft']);
    expect((await store.counts()).quotes, 2);
  });

  test('a tag no quote wears changes nothing', () async {
    await quote('a', ['life']);
    expect(await deleteTagLocal(store, 'nope'), 0);
    expect(await renameTagLocal(store, 'nope', 'x'), 0);
  });
}
