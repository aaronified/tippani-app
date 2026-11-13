import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';

/// The fake server plus the anthology routes the screens use, recording what came in.
class _Server extends FakeServer {
  final seen = <String>[];

  /// When set, every anthology call is answered with this status.
  int? answerWith;

  @override
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst(RegExp(r'^.*?/api'), '');
    final isMine =
        path.startsWith('/anthologies') || path == '/search/vocabulary';
    if (!isMine) return super.handle(r);
    seen.add(
      '${r.method} $path${r.url.hasQuery ? '?${r.url.query}' : ''} ${r.body}',
    );
    if (answerWith != null) return http.Response('', answerWith!);
    if (path == '/search/vocabulary') {
      return http.Response(
        jsonEncode({
          'tags': ['stoicism'],
          'authors': ['Seneca'],
          'shelves': ['read'],
          'books': [
            {'key': '4', 'name': 'Walden'},
          ],
          'movies': [],
          'colours': [
            {'key': 'blue', 'name': 'Wisdom'},
          ],
        }),
        200,
      );
    }
    if (r.method == 'GET' && path == '/anthologies/3') {
      return http.Response(
        jsonEncode({
          'anthology': {
            'id': 3,
            'title': 'Openings',
            'intro': 'First lines.',
            'entries': 2,
            'group_by': 'work',
            'cover_path': '0123456789abcdef.png',
            'poster_path': '1111222233334444.png',
            'description': 'Typed by hand.',
            'epigraph': 'E',
            'dedication': 'D',
            'rule': 'scope=all&tag=x',
            'rule_auto': true,
            'show_locator': true,
          },
          'entries': [
            {
              'kind': 'book',
              'item_id': 9,
              'position': 2,
              'quote': 'b',
              'work_id': 4,
              'source': 'Walden',
            },
            {'kind': 'utterance', 'item_id': 1, 'position': 1, 'quote': 'a'},
          ],
          'sections': [
            {'id': 6, 'position': 1.5, 'title': 'Part', 'prose': 'p'},
          ],
        }),
        200,
      );
    }
    if (r.method == 'GET' && path == '/anthologies/3/removed') {
      return http.Response(
        jsonEncode({
          'removed': [
            {'kind': 'book', 'item_id': 9, 'quote': 'q', 'source': 'S'},
          ],
        }),
        200,
      );
    }
    if (r.method == 'GET' && path.contains('/export')) {
      return http.Response.bytes([1, 2, 3], 200);
    }
    if (r.method == 'POST' && path.endsWith('/fill')) {
      return http.Response(
        jsonEncode({
          'added': 0,
          'matched': 3,
          'skipped': 1,
          'capped': false,
          'items': [
            {'kind': 'book', 'item_id': 9, 'quote': 'q'},
          ],
        }),
        200,
      );
    }
    if (r.method == 'POST' && path.endsWith('/sections')) {
      return http.Response(
        jsonEncode({'id': 7, 'position': 3, 'title': 'T', 'prose': ''}),
        201,
      );
    }
    if (r.method == 'POST' && path.endsWith('/poster')) {
      return http.Response(
        jsonEncode({'id': 3, 'poster_path': '5555666677778888.png'}),
        200,
      );
    }
    if (r.method == 'POST' && path.endsWith('/cover')) {
      return http.Response(
        jsonEncode({
          'id': 3,
          'cover_path': 'fedcba9876543210.png',
          'path': 'fedcba9876543210.png',
        }),
        200,
      );
    }
    if (r.method == 'POST' || r.method == 'PUT' || r.method == 'DELETE') {
      return http.Response('', 204);
    }
    return http.Response(jsonEncode({'anthologies': []}), 200);
  }
}

Future<(ServerAnthologies, _Server)> rig() async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = _Server();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  await controller.pair('ABCD2345', 'My phone');
  return (ServerAnthologies(controller), server);
}

Object? bodyOf(String seen) => jsonDecode(seen.split(' ').skip(2).join(' '));

void main() {
  test(
    'the detail carries the passages, headings, front matter and rule',
    () async {
      final (svc, _) = await rig();
      final d = await svc.get(3);
      final a = d.anthology;
      expect(a.groupBy, 'work');
      expect(a.coverPath, '0123456789abcdef.png');
      expect(a.posterPath, '1111222233334444.png');
      expect(a.description, 'Typed by hand.');
      expect(a.epigraph, 'E');
      expect(a.dedication, 'D');
      expect(a.rule, 'scope=all&tag=x');
      expect(a.ruleAuto, isTrue);
      expect(a.flag('show_locator'), isTrue);
      // read in position order: the utterance (1), the heading (1.5), the book quote (2)
      expect(
        [for (final s in d.slots) '${s.ref.kind}/${s.ref.itemId}'],
        ['utterance/1', 'section/6', 'book/9'],
      );
    },
  );

  test(
    'a note, a move and a heading go to the routes the server has',
    () async {
      final (svc, s) = await rig();
      await svc.setNote(3, 'book', 9, 'mine');
      expect(s.seen.last, startsWith('PUT /anthologies/3/entries '));
      expect(bodyOf(s.seen.last), {
        'kind': 'book',
        'item_id': 9,
        'note': 'mine',
      });

      await svc.move(3, 'section', 6, after: (kind: 'book', itemId: 9));
      expect(s.seen.last, startsWith('POST /anthologies/3/order '));
      expect(bodyOf(s.seen.last), {
        'kind': 'section',
        'item_id': 6,
        'after': {'kind': 'book', 'item_id': 9},
      });
      await svc.move(3, 'book', 9);
      expect((bodyOf(s.seen.last)! as Map).containsKey('after'), isFalse);

      final made = await svc.addSection(3, 'T', '');
      expect(made.id, 7);
      expect(s.seen.last, startsWith('POST /anthologies/3/sections '));
      await svc.editSection(3, 7, 'U', 'words');
      expect(s.seen.last, startsWith('PUT /anthologies/3/sections/7 '));
      await svc.deleteSection(3, 7);
      expect(s.seen.last, startsWith('DELETE /anthologies/3/sections/7'));
    },
  );

  test('grouping, front matter and the display switches', () async {
    final (svc, s) = await rig();
    await svc.setGrouping(3, 'person');
    expect(bodyOf(s.seen.last), {'group_by': 'person'});
    await svc.setFront(3, 'E', 'D');
    expect(s.seen.last, startsWith('PUT /anthologies/3/front '));
    expect(bodyOf(s.seen.last), {'epigraph': 'E', 'dedication': 'D'});
    final a = (await svc.get(3)).anthology;
    await svc.setSwitches(a, {'hide_credit': true, 'show_date': true});
    final sent = bodyOf(s.seen.last)! as Map;
    expect(s.seen.last, startsWith('PUT /anthologies/3 '));
    expect(sent['hide_credit'], true);
    expect(sent['show_date'], true);
    expect(sent['show_locator'], true, reason: 'what the server held stays');
    expect(sent['title'], 'Openings');
  });

  test(
    'the description goes only when it is given, and the poster is a file',
    () async {
      final (svc, s) = await rig();
      await svc.setFront(3, 'E', 'D', description: 'About it.');
      expect(bodyOf(s.seen.last), {
        'epigraph': 'E',
        'dedication': 'D',
        'description': 'About it.',
      });
      expect(
        await svc.setPoster(3, Uint8List.fromList([1]), 'p.png'),
        '5555666677778888.png',
      );
      await svc.removePoster(3);
      expect(s.seen.last, startsWith('DELETE /anthologies/3/poster'));
    },
  );

  test(
    'a proxy answering 502, 503 or 429 is a wait, and a 400 is a refusal',
    () async {
      final (svc, s) = await rig();
      for (final status in [502, 503, 504, 429]) {
        s.answerWith = status;
        await expectLater(
          svc.setGrouping(3, 'work'),
          throwsA(
            isA<AnthologyException>().having(
              (e) => e.unreachable,
              'unreachable ($status)',
              true,
            ),
          ),
        );
      }
      s.answerWith = 400;
      await expectLater(
        svc.setGrouping(3, 'work'),
        throwsA(
          isA<AnthologyException>().having(
            (e) => e.unreachable,
            'unreachable (400)',
            false,
          ),
        ),
      );
    },
  );

  test('the cover goes up as a file and comes back as a name', () async {
    final (svc, s) = await rig();
    final name = await svc.setCover(3, Uint8List.fromList([1]), 'c.png');
    expect(name, 'fedcba9876543210.png');
    await svc.removeCover(3);
    expect(s.seen.last, startsWith('DELETE /anthologies/3/cover'));
  });

  test('a fill sends the rule, can preview, and reads the counts', () async {
    final (svc, s) = await rig();
    final r = await svc.fill(
      3,
      fillRule(FillSource.tag, value: 'stoicism'),
      preview: true,
      auto: true,
    );
    expect(bodyOf(s.seen.last), {
      'rule': 'scope=all&tag=stoicism',
      'preview': true,
      'auto': true,
    });
    expect((r.matched, r.skipped, r.added), (3, 1, 0));
    expect(r.items.single.itemId, 9);
    final v = await svc.vocabulary();
    expect(v.tags, ['stoicism']);
    expect(v.books.single, (key: '4', name: 'Walden'));
  });

  test('the fill rule is the web\'s search string', () {
    expect(fillRule(FillSource.all), 'scope=all');
    expect(fillRule(FillSource.favourite), 'scope=all&favourite=yes');
    expect(fillRule(FillSource.book, value: '4'), 'scope=all&book=4');
    expect(fillRule(FillSource.tag), '', reason: 'a tag must be chosen');
    expect(
      fillRule(FillSource.author, value: 'Marcus Aurelius'),
      'scope=all&author=Marcus+Aurelius',
    );
    expect(fillRule(FillSource.dates), '');
    expect(
      fillRule(FillSource.dates, from: '2026-01-01', to: '2026-02-01'),
      'scope=all&added_from=2026-01-01&added_to=2026-02-01',
    );
    expect(
      fillRule(FillSource.dates, from: '2026-01-01'),
      'scope=all&added_from=2026-01-01',
    );
  });

  test(
    'taken-out passages can be listed and put back; files are fetched',
    () async {
      final (svc, s) = await rig();
      final gone = await svc.removed(3);
      expect(gone.single.source, 'S');
      await svc.restore(3, 'book', 9);
      expect(s.seen.last, startsWith('POST /anthologies/3/removed/book/9'));
      final md = await svc.export(3);
      expect(md.name, 'Openings.md');
      expect(md.bytes, [1, 2, 3]);
      final epub = await svc.export(3, epub: true);
      expect(epub.name, 'Openings.epub');
      expect(
        s.seen.any((x) => x.startsWith('GET /anthologies/3/export.epub')),
        isTrue,
      );
    },
  );
}
