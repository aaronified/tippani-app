import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/pull_sync.dart';
import 'package:tippani/sync/push_sync.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class Rig {
  Rig(this.server, this.lib, this.controller, this.log)
    : push = PushSync(lib, controller, log: log),
      pull = PullSync(lib, controller, log: log);
  final FakeServer server;
  final MemoryLibrary lib;
  final AppController controller;
  final AppLog log;
  final PushSync push;
  final PullSync pull;
}

Future<Rig> rig({bool paired = true}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final log = AppLog();
  final controller = AppController(
    store,
    clientFactory: server.factory,
    log: log,
  );
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My Android phone');
  return Rig(server, MemoryLibrary(), controller, log);
}

Map<String, Object?> annotation(int bookId, String quote, {String note = ''}) =>
    {
      'book_id': bookId,
      'quote': quote,
      'note': note,
      'translation': '',
      'language': 'English',
      'color': 'blue',
      'favorite': false,
      'tags': ['life'],
      'chapter': 'One',
      'location': 'p. 1',
      'character': 'Thoreau',
      'noted_at': '2026-11-01 10:00:00',
    };

/// A book and one quote on the phone, pushed, so both sides have agreed on them.
Future<({Work work, Quote quote, int bookId, int noteId})> agreed(Rig r) async {
  final w = await r.lib.addWork(
    const WorkDraft(title: 'Walden', creator: 'Thoreau', year: 1854),
  );
  final q = await r.lib.addQuote(
    QuoteDraft(
      text: 'Simplify.',
      workId: w.id,
      speaker: 'Thoreau',
      chapter: 'Economy',
      location: 'p. 8',
      tags: const ['life'],
    ),
  );
  final pushed = await r.push.push();
  expect(pushed.complete, isTrue);
  return (
    work: (await r.lib.work(w.id))!,
    quote: (await r.lib.quote(q.id))!,
    bookId: (await r.lib.work(w.id))!.serverId!,
    noteId: (await r.lib.quote(q.id))!.serverId!,
  );
}

void main() {
  test(
    'a book and a quote made on the web come down, linked to each other',
    () async {
      final r = await rig();
      final bookId = r.server.seed('/books', {
        'title': 'Dune',
        'author': 'Herbert',
        'published_year': 1965,
        'description': 'sand',
      });
      final id = r.server.seed(
        '/annotations',
        annotation(bookId, 'Fear is the mind-killer.'),
      );

      final res = await r.pull.sync();

      expect(res.worksAdded, 1);
      expect(res.quotesAdded, 1);
      expect(res.conflicts, isEmpty);
      final w = (await r.lib.works()).single;
      expect(w.title, 'Dune');
      expect(w.creator, 'Herbert');
      expect(w.year, 1965);
      expect(w.kind, WorkKind.book);
      expect(w.serverId, bookId);
      final q = (await r.lib.quotes()).single;
      expect(q.text, 'Fear is the mind-killer.');
      expect(q.workId, w.id);
      expect(q.serverId, id);
      expect(q.speaker, 'Thoreau');
      expect(q.chapter, 'One');
      expect(q.location, 'p. 1');
      expect(q.color, 'blue');
      expect(q.tags, ['life']);
      expect(q.source, 'import');
      expect(q.notedAt, DateTime.utc(2026, 11, 1, 10));
    },
  );

  test(
    'a film, its dialogue and a loose quote come down in their own shapes',
    () async {
      final r = await rig();
      final movie = r.server.seed('/movies', {
        'title': 'Heat',
        'director': 'Mann',
        'release_year': 1995,
        'media_type': 'movie',
      });
      r.server.seed('/dialogues', {
        'movie_id': movie,
        'quote': 'A guy told me once',
        'character': 'Neil',
        'timestamp': '01:02:03',
        'note': '',
        'color': 'yellow',
        'favorite': true,
        'tags': <String>[],
      });
      r.server.seed('/quotes', {
        'quote': 'Be water.',
        'speaker': 'Lee',
        'occasion': 'a talk',
        'place': 'Hong Kong',
        'note': '',
        'color': 'green',
        'favorite': false,
        'tags': <String>[],
      });

      await r.pull.sync();

      final w = (await r.lib.works()).single;
      expect(w.kind, WorkKind.film);
      expect(w.creator, 'Mann');
      final quotes = await r.lib.quotes();
      final line = quotes.firstWhere((q) => q.workId != null);
      expect(line.speaker, 'Neil');
      expect(line.location, '01:02:03');
      expect(line.favorite, isTrue);
      final loose = quotes.firstWhere((q) => q.workId == null);
      expect(loose.speaker, 'Lee');
      expect(loose.chapter, 'a talk');
      expect(loose.location, 'Hong Kong');
    },
  );

  test(
    'a second sync with nothing new changes nothing and sends nothing',
    () async {
      final r = await rig();
      final bookId = r.server.seed('/books', {
        'title': 'Dune',
        'author': 'Herbert',
      });
      r.server.seed('/annotations', annotation(bookId, 'Fear.'));
      await r.pull.sync();
      final before = r.server.requests.length;

      final res = await r.pull.sync();

      expect(res.brought, 0);
      expect(res.sent, 0);
      expect(res.conflicts, isEmpty);
      expect((await r.lib.works()).length, 1);
      expect((await r.lib.quotes()).length, 1);
      expect(r.server.updated, isEmpty);
      expect(
        r.server.requests.length - before,
        5,
      ); // the five reads and nothing else
    },
  );

  test('what the phone just pushed is not a conflict, a change or anything: both sides agree', () async {
    final r = await rig();
    await agreed(r);
    final res = await r.pull.sync();
    expect(res.brought, 0);
    expect(res.sent, 0);
    expect(res.conflicts, isEmpty);
    expect(r.server.updated, isEmpty);
  });

  test(
    'changed only on the server: applied on the phone, nothing sent',
    () async {
      final r = await rig();
      final a = await agreed(r);
      r.server.edit('/annotations', a.noteId, {
        'note': 'from the web',
        'color': 'pink',
      });

      final res = await r.pull.sync();

      expect(res.quotesUpdated, 1);
      expect(res.sent, 0);
      final q = (await r.lib.quote(a.quote.id))!;
      expect(q.note, 'from the web');
      expect(q.color, 'pink');
      expect(q.text, 'Simplify.');
      expect(q.serverId, a.noteId);
      expect(r.server.updated, isEmpty);
      // and now they agree, so the next sync is quiet
      final again = await r.pull.sync();
      expect(again.brought + again.sent + again.conflicts.length, 0);
    },
  );

  test('changed only on the phone: sent up, over the server\'s own row so what the phone does not hold survives', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {
      'sticker_id': 7,
      'chapter_no': 3.0,
    });
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'my margin note',
        tags: const ['life'],
      ),
    );

    final res = await r.pull.sync();

    expect(res.quotesSent, 1);
    expect(res.quotesUpdated, 0);
    final put = r.server.updated.single;
    expect(put.path, '/annotations/${a.noteId}');
    expect(put.body['note'], 'my margin note');
    expect(put.body['sticker_id'], 7);
    expect(put.body['chapter_no'], 3.0);
    expect(put.body['book_id'], a.bookId);
    expect(r.server.row('/annotations', a.noteId)['note'], 'my margin note');
    final again = await r.pull.sync();
    expect(again.sent + again.brought + again.conflicts.length, 0);
  });

  test('changed on both sides: nothing is changed anywhere, and the clash is named field by field', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {'note': 'web note'});
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'phone note',
        tags: const ['life'],
      ),
    );

    final res = await r.pull.sync();

    expect(res.conflicts, hasLength(1));
    final c = res.conflicts.single;
    expect(c.isWork, isFalse);
    expect(c.diffs.map((d) => d.label), ['Note']);
    expect(c.diffs.single.phone, 'phone note');
    expect(c.diffs.single.server, 'web note');
    expect((await r.lib.quote(a.quote.id))!.note, 'phone note');
    expect(r.server.row('/annotations', a.noteId)['note'], 'web note');
    expect(r.server.updated, isEmpty);
    expect(res.brought + res.sent, 0);
    // an unresolved clash is found again, not forgotten
    expect((await r.pull.sync()).conflicts, hasLength(1));
  });

  test('keep the phone\'s: the server takes the phone\'s version, and the clash is gone', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {'note': 'web note'});
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'phone note',
        tags: const ['life'],
      ),
    );
    final c = (await r.pull.sync()).conflicts.single;

    final problem = await r.pull.resolve(c, ConflictSide.phone);

    expect(problem, isNull);
    expect(r.server.row('/annotations', a.noteId)['note'], 'phone note');
    expect((await r.lib.quote(a.quote.id))!.note, 'phone note');
    final again = await r.pull.sync();
    expect(again.conflicts, isEmpty);
    expect(again.brought + again.sent, 0);
  });

  test('keep the server\'s: the phone takes the server\'s version and nothing is sent', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {'note': 'web note'});
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'phone note',
        tags: const ['life'],
      ),
    );
    final c = (await r.pull.sync()).conflicts.single;

    final problem = await r.pull.resolve(c, ConflictSide.server);

    expect(problem, isNull);
    expect((await r.lib.quote(a.quote.id))!.note, 'web note');
    expect(r.server.updated, isEmpty);
    expect((await r.pull.sync()).conflicts, isEmpty);
  });

  test('a work changed on both sides is a conflict too; keeping the phone\'s sends the whole server record with the phone\'s fields over it', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/books', a.bookId, {
      'title': 'Walden; or, Life in the Woods',
      'description': 'kept',
    });
    await r.lib.updateWork(
      a.work.id,
      const WorkDraft(
        title: 'Walden (my copy)',
        creator: 'Thoreau',
        year: 1854,
      ),
    );

    final res = await r.pull.sync();
    final c = res.conflicts.single;
    expect(c.isWork, isTrue);
    expect(c.diffs.map((d) => d.label), ['Title']);

    expect(await r.pull.resolve(c, ConflictSide.phone), isNull);
    final put = r.server.updated.single;
    expect(put.path, '/books/${a.bookId}');
    expect(put.body['title'], 'Walden (my copy)');
    expect(put.body['description'], 'kept');
    expect((await r.pull.sync()).conflicts, isEmpty);
  });

  test('a work changed only on the server comes down; its language, which the server does not list, stays', () async {
    final r = await rig();
    final w = await r.lib.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau', language: 'English'),
    );
    await r.push.push();
    final bookId = (await r.lib.work(w.id))!.serverId!;
    r.server.edit('/books', bookId, {'author': 'H. D. Thoreau'});

    final res = await r.pull.sync();

    expect(res.worksUpdated, 1);
    final back = (await r.lib.work(w.id))!;
    expect(back.creator, 'H. D. Thoreau');
    expect(back.language, 'English');
  });

  test('a film quote\'s chapter, which the server has nowhere to keep, survives a change from the server', () async {
    final r = await rig();
    final w = await r.lib.addWork(
      const WorkDraft(title: 'Heat', kind: WorkKind.film, creator: 'Mann'),
    );
    final q = await r.lib.addQuote(
      QuoteDraft(
        text: 'A guy told me once',
        workId: w.id,
        chapter: 'Act 2',
        speaker: 'Neil',
      ),
    );
    expect((await r.push.push()).complete, isTrue);
    final id = (await r.lib.quote(q.id))!.serverId!;
    r.server.edit('/dialogues', id, {'note': 'from the web'});

    final res = await r.pull.sync();

    expect(res.conflicts, isEmpty);
    final back = (await r.lib.quote(q.id))!;
    expect(back.note, 'from the web');
    expect(back.chapter, 'Act 2');
  });

  test(
    'a book and a film with the same server id are two different things',
    () async {
      final r = await rig();
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'}, id: 5);
      r.server.seed('/movies', {
        'title': 'Heat',
        'director': 'Mann',
        'media_type': 'movie',
      }, id: 5);
      await r.pull.sync();
      expect((await r.lib.works()), hasLength(2));

      r.server.edit('/movies', 5, {'director': 'Michael Mann'});
      final res = await r.pull.sync();

      expect(res.worksUpdated, 1);
      expect(res.worksAdded, 0);
      expect(await r.lib.works(), hasLength(2));
      final works = {for (final w in await r.lib.works()) w.title: w};
      expect(works['Heat']!.creator, 'Michael Mann');
      expect(works['Dune']!.creator, 'Herbert');
    },
  );

  test('linked before the phone remembered what was agreed: the same words are quietly agreed, different words are a clash', () async {
    final r = await rig();
    final w = await r.lib.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau'),
    );
    final same = await r.lib.addQuote(QuoteDraft(text: 'Same.', workId: w.id));
    final differ = await r.lib.addQuote(
      QuoteDraft(text: 'Differ.', workId: w.id, note: 'mine'),
    );
    await r.lib.setWorkServerId(w.id, 1);
    r.server.seed('/books', {'title': 'Walden', 'author': 'Thoreau'}, id: 1);
    await r.lib.setQuoteServerId(same.id, 10);
    await r.lib.setQuoteServerId(differ.id, 11);
    r.server.seed('/annotations', {
      ...annotation(1, 'Same.'),
      'tags': <String>[],
      'chapter': '',
      'location': '',
      'character': '',
      'language': '',
      'color': 'yellow',
    }, id: 10);
    r.server.seed('/annotations', {
      ...annotation(1, 'Differ.', note: 'theirs'),
      'tags': <String>[],
      'chapter': '',
      'location': '',
      'character': '',
      'language': '',
      'color': 'yellow',
    }, id: 11);

    final res = await r.pull.sync();

    expect(res.conflicts, hasLength(1));
    expect(res.conflicts.single.title, 'Differ.');
    expect(res.brought + res.sent, 0);
    expect((await r.lib.quote(same.id))!.syncedHash, isNotNull);
  });

  test('after a change from the server is applied, the next edit on the phone is sent, not called a clash', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {'note': 'web note'});
    expect((await r.pull.sync()).quotesUpdated, 1);
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        note: 'phone note',
        chapter: 'Economy',
        location: 'p. 8',
        speaker: 'Thoreau',
        tags: const ['life'],
      ),
    );

    final res = await r.pull.sync();

    expect(res.conflicts, isEmpty);
    expect(res.quotesSent, 1);
    expect(r.server.row('/annotations', a.noteId)['note'], 'phone note');
  });

  test('after the phone\'s version is kept, a later change on the server comes down, not called a clash', () async {
    final r = await rig();
    final a = await agreed(r);
    r.server.edit('/annotations', a.noteId, {'note': 'web note'});
    await r.lib.updateQuote(
      a.quote.id,
      QuoteDraft(
        text: 'Simplify.',
        workId: a.work.id,
        note: 'phone note',
        chapter: 'Economy',
        location: 'p. 8',
        speaker: 'Thoreau',
        tags: const ['life'],
      ),
    );
    final c = (await r.pull.sync()).conflicts.single;
    expect(await r.pull.resolve(c, ConflictSide.phone), isNull);
    r.server.edit('/annotations', a.noteId, {'note': 'web again'});

    final res = await r.pull.sync();

    expect(res.conflicts, isEmpty);
    expect(res.quotesUpdated, 1);
    expect((await r.lib.quote(a.quote.id))!.note, 'web again');
  });

  group('deletes travel both ways', () {
    test(
      'deleted on the server and not changed here: removed here too',
      () async {
        final r = await rig();
        final a = await agreed(r);
        r.server.remove('/annotations', a.noteId);

        final res = await r.pull.sync();

        expect(res.deletedHere, 1);
        expect(await r.lib.quote(a.quote.id), isNull);
        expect(await r.lib.work(a.work.id), isNotNull);
        expect(await r.lib.pendingDeletions(), isEmpty);
      },
    );

    test(
      'deleted on the server but changed here: kept, and sent up again as new',
      () async {
        final r = await rig();
        final a = await agreed(r);
        await r.lib.updateQuote(
          a.quote.id,
          QuoteDraft(text: 'Simplify, simplify.', workId: a.work.id),
        );
        r.server.remove('/annotations', a.noteId);

        final res = await r.pull.sync();

        expect(res.relinked, 1);
        expect(res.deletedHere, 0);
        final kept = (await r.lib.quote(a.quote.id))!;
        expect(kept.text, 'Simplify, simplify.');
        expect(kept.serverId, isNull);
        final up = await r.push.push();
        expect(up.quotesSent, 1);
        expect((await r.lib.quote(a.quote.id))!.serverId, isNotNull);
      },
    );

    test('a work deleted on the server goes with its quotes when none is only here', () async {
      final r = await rig();
      final a = await agreed(r);
      r.server.remove('/books', a.bookId);
      r.server.remove('/annotations', a.noteId);

      final res = await r.pull.sync();

      expect(res.deletedHere, 2);
      expect(await r.lib.works(), isEmpty);
      expect(await r.lib.quotes(), isEmpty);
    });

    test('a work deleted on the server that still holds a quote only here is kept, unlinked', () async {
      final r = await rig();
      final a = await agreed(r);
      final mine = await r.lib.addQuote(
        QuoteDraft(text: 'Only on the phone.', workId: a.work.id),
      );
      r.server.remove('/books', a.bookId);
      r.server.remove('/annotations', a.noteId);

      final res = await r.pull.sync();

      expect(res.deletedHere, 1);
      expect(res.relinked, 1);
      expect(await r.lib.quote(a.quote.id), isNull);
      expect(await r.lib.quote(mine.id), isNotNull);
      expect((await r.lib.work(a.work.id))!.serverId, isNull);
      final up = await r.push.push();
      expect(up.worksSent, 1);
      expect(up.quotesSent, 1);
    });

    test(
      'deleted here: the server is told once, and it does not come back',
      () async {
        final r = await rig();
        final a = await agreed(r);
        await r.lib.deleteQuote(a.quote.id);
        expect(await r.lib.pendingDeletions(), hasLength(1));

        final res = await r.pull.sync();

        expect(r.server.deleted, ['/annotations/${a.noteId}']);
        expect(res.deletedThere, 1);
        expect(await r.lib.quotes(), isEmpty);
        expect(await r.lib.pendingDeletions(), isEmpty);
        final again = await r.pull.sync();
        expect(again.deletedThere, 0);
        expect(r.server.deleted, hasLength(1));
      },
    );

    test('a work deleted here is deleted on the server, and its quotes do not come back', () async {
      final r = await rig();
      final a = await agreed(r);
      await r.lib.deleteWork(a.work.id);

      final res = await r.pull.sync();

      expect(r.server.deleted, contains('/books/${a.bookId}'));
      expect(res.deletedThere, greaterThanOrEqualTo(1));
      expect(await r.lib.works(), isEmpty);
      expect(await r.lib.quotes(), isEmpty);
      expect(await r.lib.pendingDeletions(), isEmpty);
    });

    test('a delete the server already did is cleared, not an error', () async {
      final r = await rig();
      final a = await agreed(r);
      r.server.remove('/annotations', a.noteId);
      await r.lib.deleteQuote(a.quote.id);

      final res = await r.pull.sync();

      expect(res.deletedThere, 0);
      expect(res.refused, isEmpty);
      expect(await r.lib.pendingDeletions(), isEmpty);
    });

    test('a delete the server refuses is reported and cleared; the item comes back down', () async {
      final r = await rig();
      final a = await agreed(r);
      await r.lib.deleteQuote(a.quote.id);
      r.server.failDeletesWith = 409;

      final res = await r.pull.sync();

      expect(res.refused, hasLength(1));
      expect(await r.lib.pendingDeletions(), isEmpty);
      expect(res.quotesAdded, 1);
    });

    test(
      'a server that fails stops the sync and the deletes stay pending',
      () async {
        final r = await rig();
        final a = await agreed(r);
        await r.lib.deleteQuote(a.quote.id);
        r.server.failDeletesWith = 500;

        final res = await r.pull.sync();

        expect(res.stoppedBy, ApiFailure.server);
        expect(await r.lib.pendingDeletions(), hasLength(1));
        expect(r.server.row('/annotations', a.noteId), isNotNull);
      },
    );

    test('a server that has lost most of the library is not believed: nothing is removed', () async {
      final r = await rig();
      final ids = [
        for (var i = 0; i < 12; i++)
          r.server.seed('/books', {'title': 'Book $i', 'author': 'A'}),
      ];
      await r.pull.sync();
      expect(await r.lib.works(), hasLength(12));
      for (final id in ids) {
        r.server.remove('/books', id);
      }

      final res = await r.pull.sync();

      expect(res.heldBack, 12);
      expect(res.deletedHere, 0);
      expect(await r.lib.works(), hasLength(12));
    });

    test('a few missing out of many are real deletes', () async {
      final r = await rig();
      final ids = [
        for (var i = 0; i < 12; i++)
          r.server.seed('/books', {'title': 'Book $i', 'author': 'A'}),
      ];
      await r.pull.sync();
      r.server.remove('/books', ids.first);
      r.server.remove('/books', ids[1]);

      final res = await r.pull.sync();

      expect(res.deletedHere, 2);
      expect(res.heldBack, 0);
      expect(await r.lib.works(), hasLength(10));
    });
  });

  test('items that cannot come down are counted: a quote with no words, a quote whose work is not here', () async {
    final r = await rig();
    final bookId = r.server.seed('/books', {
      'title': 'Dune',
      'author': 'Herbert',
    });
    r.server.seed('/annotations', annotation(bookId, '', note: 'note only'));
    r.server.seed('/annotations', annotation(9999, 'orphan'));

    final res = await r.pull.sync();

    expect(res.skipped, 2);
    expect(res.quotesAdded, 0);
    expect(await r.lib.quotes(), isEmpty);
  });

  test(
    'if the server cannot be read, nothing is changed on the phone',
    () async {
      final r = await rig();
      r.server.seed('/books', {'title': 'Dune', 'author': 'Herbert'});
      r.server.failReadsWith = 500;

      final res = await r.pull.sync();

      expect(res.stoppedBy, ApiFailure.server);
      expect(await r.lib.works(), isEmpty);
    },
  );

  test('not paired: nothing is asked', () async {
    final r = await rig(paired: false);
    final res = await r.pull.sync();
    expect(res.stoppedBy, ApiFailure.unauthorised);
    expect(r.server.requests, isEmpty);
  });

  test(
    'a refused edit is reported and the sync goes on; a server error stops it',
    () async {
      final r = await rig();
      final a = await agreed(r);
      await r.lib.updateQuote(
        a.quote.id,
        QuoteDraft(
          text: 'Simplify.',
          workId: a.work.id,
          note: 'changed',
          chapter: 'Economy',
          location: 'p. 8',
          speaker: 'Thoreau',
          tags: const ['life'],
        ),
      );
      r.server.failUpdatesWith = 400;

      final refused = await r.pull.sync();
      expect(refused.refused.single.what, 'quote ${a.quote.id}');
      expect(refused.stoppedBy, isNull);
      expect(refused.quotesSent, 0);

      r.server.failUpdatesWith = 500;
      final stopped = await r.pull.sync();
      expect(stopped.stoppedBy, ApiFailure.server);
      // nothing was marked as agreed, so the edit is still waiting
      r.server.failUpdatesWith = null;
      expect((await r.pull.sync()).quotesSent, 1);
    },
  );

  test(
    'resolving says why when it cannot: the server is gone, or the item is',
    () async {
      final r = await rig();
      final a = await agreed(r);
      r.server.edit('/annotations', a.noteId, {'note': 'web'});
      await r.lib.updateQuote(
        a.quote.id,
        QuoteDraft(
          text: 'Simplify.',
          workId: a.work.id,
          note: 'phone',
          chapter: 'Economy',
          location: 'p. 8',
          speaker: 'Thoreau',
          tags: const ['life'],
        ),
      );
      final c = (await r.pull.sync()).conflicts.single;

      r.server.remove('/annotations', a.noteId);
      expect(
        await r.pull.resolve(c, ConflictSide.phone),
        'The server no longer has it.',
      );

      await r.lib.deleteQuote(a.quote.id);
      expect(
        await r.pull.resolve(c, ConflictSide.server),
        'That quote is no longer on this phone.',
      );
    },
  );

  test('the log has counts and never a title or a word of a quote', () async {
    final r = await rig();
    final bookId = r.server.seed('/books', {
      'title': 'Secret Title',
      'author': 'Someone',
    });
    r.server.seed(
      '/annotations',
      annotation(bookId, 'private words of the reader'),
    );
    await r.pull.sync();
    final text = r.log.lines.join('\n');
    expect(text, contains('sync:'));
    expect(text, isNot(contains('Secret Title')));
    expect(text, isNot(contains('private words')));
  });

  test('two syncs at once are refused', () async {
    final r = await rig();
    final first = r.pull.sync();
    expect(() => r.pull.sync(), throwsStateError);
    await first;
  });
}
