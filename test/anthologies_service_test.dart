import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';

/// The fake server plus the anthology routes, answering what the real server answers.
class _Server extends FakeServer {
  final seen = <String>[];
  int? failWith;

  @override
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst(RegExp(r'^.*?/api'), '');
    if (!path.startsWith('/anthologies')) return super.handle(r);
    seen.add('${r.method} $path ${r.body}');
    if (failWith != null) {
      return http.Response(jsonEncode({'error': 'nope'}), failWith!);
    }
    if (r.method == 'DELETE') return http.Response('', 204);
    if (r.method == 'PUT') return http.Response(jsonEncode({'ok': true}), 200);
    if (r.method == 'POST' && path.endsWith('/entries')) {
      return http.Response(
        jsonEncode({'added': 1, 'skipped': 0, 'entries': 1}),
        200,
      );
    }
    if (r.method == 'POST') {
      return http.Response(
        jsonEncode({'id': 5, 'title': 'T', 'intro': '', 'entries': 0}),
        201,
      );
    }
    return http.Response(jsonEncode({'anthologies': []}), 200);
  }
}

Future<(AppController, _Server)> rig({bool paired = true}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = _Server();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My phone');
  return (controller, server);
}

void main() {
  test('with no pairing, every call says so instead of trying', () async {
    final (c, s) = await rig(paired: false);
    final svc = ServerAnthologies(c);
    expect(svc.available, isFalse);
    await expectLater(
      svc.list(),
      throwsA(
        isA<AnthologyException>().having(
          (e) => e.message,
          'message',
          contains('not paired'),
        ),
      ),
    );
    expect(s.seen, isEmpty);
  });

  test('a call that returns nothing, like a delete, is not mistaken for "not paired"', () async {
    final (c, s) = await rig();
    final svc = ServerAnthologies(c);
    await svc.delete(7);
    await svc.removeEntry(7, 'book', 3);
    expect(s.seen, [
      'DELETE /anthologies/7 ',
      'DELETE /anthologies/7/entries/book/3 ',
    ]);
  });

  test('an edit sends back what the server held, with only the title and introduction changed', () async {
    final (c, s) = await rig();
    final a = Anthology.fromJson({
      'id': 2,
      'title': 'Old',
      'intro': 'i',
      'hide_credit': true,
    });
    await ServerAnthologies(c).edit(a, title: 'New', intro: 'j');
    final sent = jsonDecode(s.seen.single.split(' ').skip(2).join(' ')) as Map;
    expect(sent['title'], 'New');
    expect(sent['intro'], 'j');
    expect(sent['hide_credit'], true);
  });

  test(
    'adding sends the kind and the id, and reports whether it was new',
    () async {
      final (c, s) = await rig();
      expect(await ServerAnthologies(c).add(2, 'screen', 9), isTrue);
      expect(s.seen.single, startsWith('POST /anthologies/2/entries '));
      expect(jsonDecode(s.seen.single.split(' ').skip(2).join(' ')), {
        'items': [
          {'kind': 'screen', 'item_id': 9},
        ],
      });
    },
  );

  test('a refusal comes back in words', () async {
    final (c, s) = await rig();
    s.failWith = 500;
    await expectLater(
      ServerAnthologies(c).create('T', ''),
      throwsA(isA<AnthologyException>()),
    );
  });
}
