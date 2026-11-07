import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/push_sync.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class Rig {
  Rig(this.server, this.lib, this.controller, this.log, this.sync);
  final FakeServer server;
  final MemoryLibrary lib;
  final AppController controller;
  final AppLog log;
  final PushSync sync;
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
  final lib = MemoryLibrary();
  return Rig(server, lib, controller, log, PushSync(lib, controller, log: log));
}

void main() {
  test('what goes up is recorded as agreed, so the first pull has nothing to argue about; an adopted duplicate is not', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'Walden'));
    final q1 = await r.lib.addQuote(QuoteDraft(text: 'One.', workId: w.id));
    final q2 = await r.lib.addQuote(QuoteDraft(text: 'Two.', workId: w.id));
    // the server already has "Two." under this book once the book exists
    await r.sync.push();
    expect((await r.lib.work(w.id))!.syncedHash, isNotNull);
    expect((await r.lib.quote(q1.id))!.syncedHash, isNotNull);
    expect((await r.lib.quote(q2.id))!.syncedHash, isNotNull);

    final w2 = await r.lib.addWork(const WorkDraft(title: 'Other'));
    final a = await r.lib.addQuote(
      QuoteDraft(text: 'Same words', workId: w2.id),
    );
    await r.sync.push();
    // a copy made by hand on the server, then the phone's twin is pushed again as a new, unlinked quote
    final twin = await r.lib.addQuote(
      QuoteDraft(text: 'Same words', workId: w2.id),
    );
    await r.sync.push();
    expect((await r.lib.quote(a.id))!.syncedHash, isNotNull);
    expect((await r.lib.quote(twin.id))!.serverId, isNotNull);
    expect((await r.lib.quote(twin.id))!.syncedHash, isNull);
  });

  test('a book and its quote go to /books and /annotations, in the server\'s names, and the ids are kept', () async {
    final r = await rig();
    final w = await r.lib.addWork(
      const WorkDraft(
        title: 'Walden',
        creator: 'Thoreau',
        year: 1854,
        language: 'English',
      ),
    );
    final q = await r.lib.addQuote(
      QuoteDraft(
        text: 'Simplify.',
        workId: w.id,
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'twice',
        translation: 'saral',
        color: 'blue',
        favorite: true,
        tags: const ['life', 'simple'],
      ),
    );
    final result = await r.sync.push();

    expect(result.worksSent, 1);
    expect(result.quotesSent, 1);
    expect(result.complete, isTrue);
    final book = r.server.created['/books']!.single;
    expect(book['title'], 'Walden');
    expect(book['author'], 'Thoreau');
    expect(book['published_year'], 1854);
    expect(book['language'], 'English');
    final a = r.server.created['/annotations']!.single;
    expect(a['book_id'], book['id']);
    expect(a['quote'], 'Simplify.');
    expect(a['character'], 'Thoreau');
    expect(a['chapter'], 'Economy');
    expect(a['location'], 'p. 8');
    expect(a['note'], 'twice');
    expect(a['translation'], 'saral');
    expect(a['color'], 'blue');
    expect(a['favorite'], true);
    expect(a['tags'], ['life', 'simple']);
    expect(a['source'], 'manual');
    expect(a['noted_at'], q.notedAt.toUtc().toIso8601String());
    expect((await r.lib.work(w.id))!.serverId, book['id']);
    expect((await r.lib.quote(q.id))!.serverId, a['id']);
  });

  test('a film goes to /movies with its director, and its quote to /dialogues with a timestamp', () async {
    final r = await rig();
    final w = await r.lib.addWork(
      const WorkDraft(
        title: 'Casablanca',
        kind: WorkKind.film,
        creator: 'Curtiz',
        year: 1942,
      ),
    );
    await r.lib.addQuote(
      QuoteDraft(
        text: 'Here is looking at you.',
        workId: w.id,
        speaker: 'Rick',
        location: '01:32:10',
      ),
    );
    await r.sync.push();
    final m = r.server.created['/movies']!.single;
    expect(m['director'], 'Curtiz');
    expect(m['release_year'], 1942);
    expect(m['media_type'], 'movie');
    final d = r.server.created['/dialogues']!.single;
    expect(d['movie_id'], m['id']);
    expect(d['character'], 'Rick');
    expect(d['timestamp'], '01:32:10');
    expect(r.server.created['/books'], isNull);
  });

  test('a show and a game keep their media type', () async {
    final r = await rig();
    await r.lib.addWork(const WorkDraft(title: 'Dark', kind: WorkKind.show));
    await r.lib.addWork(const WorkDraft(title: 'Hades', kind: WorkKind.game));
    await r.sync.push();
    expect(r.server.created['/movies']!.map((m) => m['media_type']), [
      'show',
      'game',
    ]);
  });

  test('a work of kind other is a book', () async {
    final r = await rig();
    await r.lib.addWork(const WorkDraft(title: 'A zine', kind: WorkKind.other));
    await r.sync.push();
    expect(r.server.created['/books'], hasLength(1));
  });

  test('a quote with no work is a standalone quote, its chapter the occasion and its location the place', () async {
    final r = await rig();
    final q = await r.lib.addQuote(
      const QuoteDraft(
        text: 'We shall fight on the beaches.',
        speaker: 'Churchill',
        chapter: 'House of Commons',
        location: 'London',
      ),
    );
    await r.sync.push();
    final u = r.server.created['/quotes']!.single;
    expect(u['speaker'], 'Churchill');
    expect(u['occasion'], 'House of Commons');
    expect(u['place'], 'London');
    expect(u.containsKey('book_id'), isFalse);
    expect((await r.lib.quote(q.id))!.serverId, u['id']);
  });

  test(
    'a quote the camera made goes up as ocr, and anything else as manual',
    () async {
      final r = await rig();
      await r.lib.addQuote(const QuoteDraft(text: 'seen', source: 'capture'));
      await r.lib.addQuote(
        const QuoteDraft(text: 'brought in', source: 'import'),
      );
      await r.sync.push();
      expect(r.server.created['/quotes']!.map((q) => q['source']), [
        'ocr',
        'manual',
      ]);
    },
  );

  test('pushing again sends nothing, and a new item goes up alone', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'Walden'));
    await r.lib.addQuote(QuoteDraft(text: 'one', workId: w.id));
    await r.sync.push();
    final before = r.server.requests.length;
    final again = await r.sync.push();
    expect(again.sent, 0);
    expect(r.server.requests.length, before);

    await r.lib.addQuote(QuoteDraft(text: 'two', workId: w.id));
    final next = await r.sync.push();
    expect(next.quotesSent, 1);
    expect(next.worksSent, 0);
    expect(r.server.created['/annotations'], hasLength(2));
    expect(
      r.server.created['/annotations']!.last['book_id'],
      r.server.created['/books']!.single['id'],
    );
  });

  test(
    'pending says how much is waiting, and it drops to nothing after a push',
    () async {
      final r = await rig();
      final w = await r.lib.addWork(const WorkDraft(title: 'W'));
      await r.lib.addQuote(QuoteDraft(text: 'a', workId: w.id));
      await r.lib.addQuote(const QuoteDraft(text: 'b'));
      expect(await r.sync.pending(), (works: 1, quotes: 2));
      await r.sync.push();
      expect(await r.sync.pending(), (works: 0, quotes: 0));
    },
  );

  test('a quote the server already holds (409) is adopted, not sent twice or counted as sent', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'W'));
    final first = await r.lib.addQuote(QuoteDraft(text: 'same', workId: w.id));
    final second = await r.lib.addQuote(QuoteDraft(text: 'same', workId: w.id));
    final result = await r.sync.push();
    expect(result.quotesSent, 1);
    expect(result.alreadyThere, 1);
    expect(r.server.created['/annotations'], hasLength(1));
    final id = r.server.created['/annotations']!.single['id'];
    expect((await r.lib.quote(first.id))!.serverId, id);
    expect((await r.lib.quote(second.id))!.serverId, id);
    expect(result.complete, isTrue);
  });

  test('a work the server refuses is reported, its quotes wait, and the rest still goes up', () async {
    final r = await rig();
    r.server.refuseTitle = 'Bad';
    final bad = await r.lib.addWork(const WorkDraft(title: 'Bad'));
    final good = await r.lib.addWork(const WorkDraft(title: 'Good'));
    await r.lib.addQuote(QuoteDraft(text: 'in bad', workId: bad.id));
    await r.lib.addQuote(QuoteDraft(text: 'in good', workId: good.id));
    final result = await r.sync.push();
    expect(result.worksSent, 1);
    expect(result.quotesSent, 1);
    expect(result.waiting, 1);
    expect(result.complete, isFalse);
    expect(result.refused.single.what, 'work ${bad.id}');
    expect(result.refused.single.reason, 'title is not acceptable');
    expect(r.server.created['/annotations']!.single['quote'], 'in good');
    expect((await r.lib.work(bad.id))!.serverId, isNull);
  });

  test('when the network drops the push stops, says so, keeps what went up, and the next push finishes the rest', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'W'));
    for (final t in ['a', 'b', 'c', 'd']) {
      await r.lib.addQuote(QuoteDraft(text: t, workId: w.id));
    }
    r.server.dropAfter = 3; // the work and two quotes
    final first = await r.sync.push();
    expect(first.stoppedBy, ApiFailure.network);
    expect(first.worksSent, 1);
    expect(first.quotesSent, 2);
    expect(first.waiting, 2);
    expect(first.complete, isFalse);

    r.server.dropAfter = null;
    final second = await r.sync.push();
    expect(second.complete, isTrue);
    expect(second.worksSent, 0);
    expect(second.quotesSent, 2);
    expect(r.server.created['/books'], hasLength(1));
    expect(r.server.created['/annotations']!.map((a) => a['quote']), [
      'a',
      'b',
      'c',
      'd',
    ]);
  });

  test('a drop before the first work leaves every quote waiting', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'W'));
    await r.lib.addQuote(QuoteDraft(text: 'a', workId: w.id));
    await r.lib.addQuote(const QuoteDraft(text: 'b'));
    r.server.dropAfter = 0;
    final result = await r.sync.push();
    expect(result.stoppedBy, ApiFailure.network);
    expect(result.sent, 0);
    expect(result.waiting, 2);
  });

  test(
    'being rate limited stops the push rather than hammering the server',
    () async {
      final r = await rig();
      await r.lib.addQuote(const QuoteDraft(text: 'a'));
      await r.lib.addQuote(const QuoteDraft(text: 'b'));
      r.server.failCreatesWith = 429;
      final result = await r.sync.push();
      expect(result.stoppedBy, ApiFailure.rateLimited);
      expect(
        r.server.requests.where((q) => q.url.path.endsWith('/quotes')),
        hasLength(1),
      );
    },
  );

  test('a phone that is not paired sends nothing and says it cannot', () async {
    final r = await rig(paired: false);
    await r.lib.addQuote(const QuoteDraft(text: 'a'));
    final result = await r.sync.push();
    expect(result.stoppedBy, ApiFailure.unauthorised);
    expect(r.server.created, isEmpty);
  });

  test(
    'a token the server has revoked stops the push and unpairs the phone',
    () async {
      final r = await rig();
      await r.lib.addQuote(const QuoteDraft(text: 'a'));
      r.server.tokenValid = false;
      final result = await r.sync.push();
      expect(result.stoppedBy, ApiFailure.unauthorised);
      expect(r.controller.paired, isFalse);
      expect((await r.lib.unsyncedQuotes()), hasLength(1));
    },
  );

  test(
    'an answer with no id is a stop, not a guess: nothing is marked as sent',
    () async {
      final r = await rig();
      r.server.omitId = true;
      final q = await r.lib.addQuote(const QuoteDraft(text: 'a'));
      final result = await r.sync.push();
      expect(result.stoppedBy, ApiFailure.badResponse);
      expect(result.sent, 0);
      expect((await r.lib.quote(q.id))!.serverId, isNull);
    },
  );

  test('progress is reported once per item, out of the total', () async {
    final r = await rig();
    final w = await r.lib.addWork(const WorkDraft(title: 'W'));
    await r.lib.addQuote(QuoteDraft(text: 'a', workId: w.id));
    await r.lib.addQuote(const QuoteDraft(text: 'b'));
    final seen = <(int, int)>[];
    await r.sync.push(onProgress: (d, t) => seen.add((d, t)));
    expect(seen, [(1, 3), (2, 3), (3, 3)]);
  });

  test(
    'a second push while one runs joins it: nothing is sent twice',
    () async {
      final r = await rig();
      await r.lib.addWork(const WorkDraft(title: 'Dune'));

      final first = r.sync.push();
      final second = r.sync.push();
      expect(r.sync.running, isTrue);

      final a = await first;
      final b = await second;
      expect(identical(a, b), isTrue);
      expect(a.worksSent, 1);
      expect(r.server.created['/books'], hasLength(1));
      expect(r.sync.running, isFalse);
    },
  );

  test('the log says how many went and which items were refused, never what anything said', () async {
    final r = await rig();
    r.server.refuseTitle = 'A secret title';
    await r.lib.addWork(const WorkDraft(title: 'A secret title'));
    await r.lib.addQuote(const QuoteDraft(text: 'A private thought'));
    await r.sync.push();
    final text = r.log.text();
    expect(text, contains('push: 0 works and 1 quotes sent'));
    expect(text, contains('push: work 1 refused: title is not acceptable'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('private')));
  });

  test('a work the server already has under that title is linked, not sent a second time', () async {
    final r = await rig();
    final id = r.server.seed('/books', {
      'title': 'Walden',
      'author': 'Thoreau',
    });
    final w = await r.lib.addWork(
      const WorkDraft(title: ' WALDEN', creator: 'Thoreau'),
    );
    final q = await r.lib.addQuote(QuoteDraft(text: 'Simplify.', workId: w.id));

    final res = await r.sync.push();

    expect(r.server.created['/books'], hasLength(1));
    expect(res.worksSent, 0);
    expect((await r.lib.work(w.id))!.serverId, id);
    expect(res.quotesSent, 1);
    expect((await r.lib.quote(q.id))!.serverId, isNotNull);
    expect(r.server.created['/annotations']!.single['book_id'], id);
  });

  test('a work with no twin on the server is sent as before', () async {
    final r = await rig();
    r.server.seed('/books', {'title': 'Other', 'author': 'Someone'});
    await r.lib.addWork(const WorkDraft(title: 'Walden', creator: 'Thoreau'));

    final res = await r.sync.push();

    expect(res.worksSent, 1);
    expect(r.server.created['/books'], hasLength(2));
  });
}
