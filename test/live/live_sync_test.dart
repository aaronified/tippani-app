// Runs the real sync code against a real Tippani server. Skipped unless these are set:
//   TIPPANI_LIVE_URL    the server's address, like http://127.0.0.1:18080
//   TIPPANI_LIVE_CODE   a fresh pairing code from that server (valid for a few minutes, one use)
// See docs/wiki/Developing.md, "Testing against a real server".
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/pull_sync.dart';
import 'package:tippani/sync/push_sync.dart';
import 'package:tippani/tools/server_tools.dart';
import 'package:tippani/tools/work_lookup.dart';

import '../support/memory_library.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;

  late AppController controller;
  late String token;

  Future<Object?> raw(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$_url/api$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 400) {
      throw Exception('$method $path -> ${res.statusCode} ${res.body}');
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  setUpAll(() async {
    if (skip != null) return;
    SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
    final vault = MemoryTokenVault();
    controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), vault),
      log: AppLog(),
    );
    await controller.load();
    final result = await controller.pair(_code ?? '', 'live test');
    expect(result.ok, isTrue, reason: 'pairing against the real server');
    token = (await vault.read())!;
  });

  test('a phone library goes up, comes down on another phone, and edits travel both ways', () async {
    final log = AppLog();
    final lib = MemoryLibrary();
    final push = PushSync(lib, controller, log: log);
    final pull = PullSync(lib, controller, log: log);

    final book = await lib.addWork(
      const WorkDraft(
        title: 'Live Walden',
        creator: 'Henry David Thoreau',
        year: 1854,
        language: 'en',
      ),
    );
    final q = await lib.addQuote(
      QuoteDraft(
        text: 'Simplify, simplify. (live)',
        workId: book.id,
        translation: 'saral karo',
        speaker: 'Thoreau',
        chapter: 'Economy',
        location: 'p. 8',
        note: 'my margin',
        color: 'blue',
        favorite: true,
        tags: const ['life', 'Live-Test'],
      ),
    );
    final loose = await lib.addQuote(
      const QuoteDraft(text: 'A loose one (live).', speaker: 'Anon'),
    );

    // 1. up
    final up = await push.push();
    expect(up.stoppedBy, isNull);
    expect(up.refused, isEmpty, reason: 'the server refused: ${up.refused}');
    final sentQuote = await lib.quote(q.id);
    expect(sentQuote!.serverId, isNotNull);
    expect((await lib.quote(loose.id))!.serverId, isNotNull);

    // what the server holds is what the phone meant
    final books = (await raw('GET', '/books') as Map)['books'] as List;
    final serverBook = books.cast<Map>().firstWhere(
      (b) => b['title'] == 'Live Walden',
    );
    expect(serverBook['author'], 'Henry David Thoreau');
    final onServer =
        ((await raw('GET', '/annotations') as Map)['annotations'] as List)
            .cast<Map>()
            .firstWhere((a) => a['id'] == sentQuote.serverId);
    expect(onServer['quote'], 'Simplify, simplify. (live)');
    expect(onServer['color'], 'blue');
    expect(onServer['chapter'], 'Economy');
    expect(onServer['note'], 'my margin');
    expect(onServer['favorite'] ?? onServer['is_favorite'], isTrue);

    // 2. a second pull with nothing changed is quiet
    var r = await pull.sync();
    expect(r.stoppedBy, isNull);
    expect(r.conflicts, isEmpty);
    expect(r.brought, 0, reason: 'nothing changed, nothing should come down');
    expect(r.sent, 0);

    // 3. an edit on the server (as the web app would) comes down
    final serverQuoteId = sentQuote.serverId!;
    final current = Map<String, Object?>.from(onServer);
    current['note'] = 'edited on the web';
    await raw('PUT', '/annotations/$serverQuoteId', current);
    r = await pull.sync();
    expect(r.refused, isEmpty);
    expect(r.quotesUpdated, 1);
    expect((await lib.quote(q.id))!.note, 'edited on the web');

    // 4. an edit on the phone goes up through the pull
    final phone = (await lib.quote(q.id))!;
    await lib.updateQuote(
      q.id,
      QuoteDraft(
        text: phone.text,
        workId: phone.workId,
        translation: phone.translation,
        speaker: phone.speaker,
        chapter: 'Economy II',
        location: phone.location,
        note: phone.note,
        color: phone.color,
        favorite: phone.favorite,
        notedAt: phone.notedAt,
        source: phone.source,
        tags: phone.tags,
      ),
    );
    r = await pull.sync();
    expect(r.refused, isEmpty, reason: 'refused: ${r.refused}');
    expect(r.quotesSent, 1);
    final after =
        ((await raw('GET', '/annotations') as Map)['annotations'] as List)
            .cast<Map>()
            .firstWhere((a) => a['id'] == serverQuoteId);
    expect(after['chapter'], 'Economy II');
    expect(
      after['note'],
      'edited on the web',
      reason: 'the server\'s own fields survive',
    );

    // 5. both sides edit: a conflict, resolved by keeping the phone's
    final p2 = (await lib.quote(q.id))!;
    await lib.updateQuote(
      q.id,
      QuoteDraft(
        text: p2.text,
        workId: p2.workId,
        translation: p2.translation,
        speaker: p2.speaker,
        chapter: p2.chapter,
        location: 'p. 99',
        note: p2.note,
        color: p2.color,
        favorite: p2.favorite,
        notedAt: p2.notedAt,
        source: p2.source,
        tags: p2.tags,
      ),
    );
    final cur2 = Map<String, Object?>.from(after);
    cur2['location'] = 'p. 1';
    await raw('PUT', '/annotations/$serverQuoteId', cur2);
    r = await pull.sync();
    expect(r.conflicts, hasLength(1));
    expect(
      r.conflicts.single.diffs.map((d) => d.label),
      contains(anyOf('Place', 'Location', 'Page')),
    );
    final problem = await pull.resolve(r.conflicts.single, ConflictSide.phone);
    expect(problem, isNull);
    final settled =
        ((await raw('GET', '/annotations') as Map)['annotations'] as List)
            .cast<Map>()
            .firstWhere((a) => a['id'] == serverQuoteId);
    expect(settled['location'], 'p. 99');

    // 6. a different phone, nothing on it, gets all of it
    final other = MemoryLibrary();
    final otherPull = PullSync(other, controller, log: log);
    final down = await otherPull.sync();
    expect(down.stoppedBy, isNull);
    expect(down.skipped, 0, reason: 'nothing should be skipped');
    final titles = (await other.works()).map((w) => w.title);
    expect(titles, contains('Live Walden'));
    final got = (await other.quotes()).map((x) => x.text);
    expect(
      got,
      containsAll(['Simplify, simplify. (live)', 'A loose one (live).']),
    );
    final tags = (await other.quotes())
        .firstWhere((x) => x.text.startsWith('Simplify'))
        .tags;
    expect(tags, containsAll(['life', 'Live-Test']));
  }, skip: skip);

  test(
    'a film and its dialogue go up, and edits to it travel both ways',
    () async {
      final log = AppLog();
      final lib = MemoryLibrary();
      final push = PushSync(lib, controller, log: log);
      final pull = PullSync(lib, controller, log: log);
      final film = await lib.addWork(
        const WorkDraft(
          title: 'Live Casablanca',
          kind: WorkKind.film,
          creator: 'Michael Curtiz',
          year: 1942,
        ),
      );
      final q = await lib.addQuote(
        QuoteDraft(
          text: 'Here is looking at you, kid. (live)',
          workId: film.id,
          speaker: 'Rick',
          chapter: '01:32:10',
          color: 'pink',
          tags: const ['film-live'],
        ),
      );
      final up = await push.push();
      expect(up.stoppedBy, isNull);
      expect(up.refused, isEmpty, reason: 'refused: ${up.refused}');
      final sent = (await lib.quote(q.id))!;
      expect(sent.serverId, isNotNull);

      final movies = ((await raw('GET', '/movies') as Map)['movies'] as List)
          .cast<Map>();
      expect(movies.any((m) => m['title'] == 'Live Casablanca'), isTrue);
      final dialogues =
          ((await raw('GET', '/dialogues') as Map)['dialogues'] as List)
              .cast<Map>();
      final d = dialogues.firstWhere((x) => x['id'] == sent.serverId);
      expect(d['quote'], 'Here is looking at you, kid. (live)');

      // the first pull also brings down what the other test left on the shared server; the second is quiet
      var r = await pull.sync();
      expect(r.conflicts, isEmpty);
      r = await pull.sync();
      expect(r.brought, 0);
      expect(r.sent, 0);

      final phone = (await lib.quote(q.id))!;
      await lib.updateQuote(
        q.id,
        QuoteDraft(
          text: phone.text,
          workId: phone.workId,
          speaker: phone.speaker,
          chapter: phone.chapter,
          note: 'phone note',
          color: phone.color,
          notedAt: phone.notedAt,
          source: phone.source,
          tags: phone.tags,
        ),
      );
      r = await pull.sync();
      expect(r.refused, isEmpty, reason: 'refused: ${r.refused}');
      expect(r.quotesSent, 1);
      final after =
          ((await raw('GET', '/dialogues') as Map)['dialogues'] as List)
              .cast<Map>()
              .firstWhere((x) => x['id'] == sent.serverId);
      expect(after['note'], 'phone note');

      final other = MemoryLibrary();
      final down = await PullSync(other, controller, log: log).sync();
      expect(down.skipped, 0);
      expect(
        (await other.works()).any(
          (w) => w.title == 'Live Casablanca' && w.kind == WorkKind.film,
        ),
        isTrue,
      );
      expect(
        (await other.quotes()).any((x) => x.text.startsWith('Here is looking')),
        isTrue,
      );
    },
    skip: skip,
  );

  test('anthologies: make, add a synced quote, edit without losing the switches, remove, delete', () async {
    final lib = MemoryLibrary();
    final push = PushSync(lib, controller, log: AppLog());
    final w = await lib.addWork(const WorkDraft(title: 'Anthology book'));
    final q = await lib.addQuote(
      QuoteDraft(text: 'For the anthology.', workId: w.id),
    );
    await push.push();
    final serverId = (await lib.quote(q.id))!.serverId!;

    final svc = ServerAnthologies(controller);
    expect(svc.available, isTrue);
    final made = await svc.create('Live anthology', 'an introduction');
    expect(made.title, 'Live anthology');

    expect(await svc.add(made.id, 'book', serverId), isTrue);
    expect(await svc.add(made.id, 'book', serverId), isFalse);

    // a switch this app does not show is set on the server, then the app edits the title
    final before = ((await raw('GET', '/anthologies/${made.id}')) as Map);
    final row = Map<String, Object?>.from(before['anthology'] as Map);
    row['hide_credit'] = true;
    await raw('PUT', '/anthologies/${made.id}', row);

    var detail = await svc.get(made.id);
    expect(detail.entries.single.quote, 'For the anthology.');
    expect(detail.entries.single.kind, 'book');
    await svc.edit(detail.anthology, title: 'Renamed', intro: 'new intro');
    detail = await svc.get(made.id);
    expect(detail.anthology.title, 'Renamed');
    expect(detail.anthology.intro, 'new intro');
    expect(
      detail.anthology.raw['hide_credit'],
      isTrue,
      reason: 'the edit kept the switch it does not show',
    );

    expect(
      (await svc.list()).any((a) => a.id == made.id && a.entries == 1),
      isTrue,
    );

    await svc.removeEntry(made.id, 'book', serverId);
    expect((await svc.get(made.id)).entries, isEmpty);
    await svc.delete(made.id);
    expect((await svc.list()).any((a) => a.id == made.id), isFalse);
  }, skip: skip);

  test('bin and statistics: a deleted quote is in the bin, restores, and the numbers read', () async {
    final lib = MemoryLibrary();
    final push = PushSync(lib, controller, log: AppLog());
    final w = await lib.addWork(const WorkDraft(title: 'Bin book'));
    final q = await lib.addQuote(
      QuoteDraft(text: 'Into the bin (live).', workId: w.id),
    );
    await push.push();
    final serverId = (await lib.quote(q.id))!.serverId!;

    final tools = PairedServerTools(controller);
    final stats = await tools.stats();
    expect(stats.quotes, greaterThan(0));
    expect(stats.books, greaterThan(0));

    await raw('DELETE', '/annotations/$serverId');
    var bin = await tools.bin();
    final entry = bin.entries.firstWhere(
      (e) => e.label == 'Into the bin (live).',
    );
    expect(entry.kind, 'annotation');
    expect(bin.keptDays, greaterThan(0));

    await tools.restore(entry.id);
    bin = await tools.bin();
    expect(bin.entries.any((e) => e.label == 'Into the bin (live).'), isFalse);
    final back =
        ((await raw('GET', '/annotations')) as Map)['annotations'] as List;
    expect(
      back.any((a) => (a as Map)['quote'] == 'Into the bin (live).'),
      isTrue,
    );

    await raw('DELETE', '/annotations/$serverId');
    await tools.deleteForever(
      (await tools.bin()).entries
          .firstWhere((e) => e.label == 'Into the bin (live).')
          .id,
    );
    await raw('DELETE', '/annotations/9999').then((_) {}, onError: (_) {});
    await tools.emptyBin();
    expect((await tools.bin()).entries, isEmpty);
  }, skip: skip);

  test(
    'lookup: a book title comes back as matches through the server',
    () async {
      final found = await PairedWorkLookup(controller)
          .find(WorkKind.book, 'Walden', creator: 'Thoreau');
      expect(found, isNotEmpty);
      expect(found.first.title, contains('Walden'));
      expect(found.first.creator, contains('Thoreau'));
    },
    skip: skip,
  );
}
