import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/account_service.dart';
import 'package:tippani/api/offline_writes.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tags/tag_service.dart';
import 'package:tippani/tools/server_tools.dart';

import '../support/fake_server.dart';

void main() {
  late FakeServer server;
  late AppController controller;
  late OfflineWrites writes;
  late PairedTagService tags;
  late SharedPreferences prefs;

  Map<String, Object?> tag(int id, String name) => {
    'id': id,
    'name': name,
    'color': 'blue',
    'style': 'sticker',
    'annotations': 1,
    'dialogues': 0,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    prefs = await SharedPreferences.getInstance();
    server = FakeServer();
    final settings = SettingsStore(prefs, MemoryTokenVault());
    controller = AppController(settings, clientFactory: server.factory);
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    writes = OfflineWrites(controller, settings);
    tags = PairedTagService(controller, writes: writes);
    server.tags.addAll([tag(1, 'life'), tag(2, 'craft')]);
    // the Tags page has been opened once with a server: its answer is kept
    await controller.authedClient()!.getJson('/tags');
  });

  List<String> keptNames() => [
    for (final t
        in (controller.offline.read('/tags') == null
            ? const []
            : _tagsOf(controller)))
      t['name']! as String,
  ];

  test('a tag renamed with no server shows at once and goes up when the server answers', () async {
    server.unreachable = true;
    final shown = await tags.save(
      ServerTag.fromJson(tag(1, 'life')),
      name: 'living',
    );
    expect(shown.name, 'living');
    expect(writes.pending.value, 1);
    expect(
      keptNames(),
      contains('living'),
      reason: 'the Tags page reads the kept copy',
    );

    server.unreachable = false;
    expect(await writes.flush(), 0);
    expect(server.tags.first['name'], 'living');
    expect(writes.pending.value, 0);
  });

  test('changes go up in the order they were made, and a delete waits like a rename', () async {
    server.unreachable = true;
    await tags.save(ServerTag.fromJson(tag(2, 'craft')), name: 'making');
    await tags.delete(ServerTag.fromJson(tag(1, 'life')));
    expect(keptNames(), ['making']);
    expect(writes.pending.value, 2);
    server.unreachable = false;
    await writes.flush();
    expect(server.tags.map((t) => t['name']), ['making']);
  });

  test('a change the server refuses is dropped and listed, and the ones behind it still go', () async {
    server.unreachable = true;
    await tags.save(ServerTag.fromJson(tag(1, 'life')), name: 'CRAFT');
    await tags.save(ServerTag.fromJson(tag(2, 'craft')), color: 'pink');
    server.unreachable = false;
    expect(await writes.flush(), 0);
    expect(writes.problems.value, hasLength(1));
    expect(server.tags.first['name'], 'life', reason: 'the clash was refused');
    expect(server.tags.last['color'], 'pink', reason: 'the next change went');
  });

  test('a change made when the server is back goes after the ones that waited, not before them', () async {
    server.unreachable = true;
    await tags.save(ServerTag.fromJson(tag(1, 'life')), name: 'first');
    server.unreachable = false;
    await tags.save(ServerTag.fromJson(tag(1, 'first')), name: 'second');
    expect(server.tags.first['name'], 'second');
    expect(
      writes.pending.value,
      0,
      reason: 'the waiting change was sent first',
    );
  });

  test(
    'with the server answering a change is made at once and nothing waits',
    () async {
      await tags.save(ServerTag.fromJson(tag(1, 'life')), name: 'now');
      expect(writes.pending.value, 0);
      expect(server.tags.first['name'], 'now');
    },
  );

  test('what waits goes when the phone is unpaired, so it is never sent to another account', () async {
    server.unreachable = true;
    await tags.delete(ServerTag.fromJson(tag(1, 'life')));
    expect(prefs.getString('outbox.writes'), isNotNull);
    server.unreachable = false;
    await controller.unpair();
    expect(prefs.getString('outbox.writes'), isNull);
    expect(writes.pending.value, 0);
  });

  test('a restore from the bin waits and shows the bin without it', () async {
    server.trash.add({'id': 5, 'kind': 'annotation', 'title': 'A quote'});
    final tools = PairedServerTools(controller, writes: writes);
    await tools.bin();
    server.unreachable = true;
    await tools.restore(5);
    expect(writes.pending.value, 1);
    final kept = controller.offline.read('/trash')!.body;
    expect(kept, isNot(contains('"id":5')));
    server.unreachable = false;
    await writes.flush();
    expect(server.trash, isEmpty);
  });

  test(
    'a context rule saved with no server waits and the screen shows it',
    () async {
      final rules = PairedContextRules(controller, writes: writes);
      await controller.authedClient()!.getJson('/context-rules/global');
      server.unreachable = true;
      final saved = await rules.setGlobal(
        const ContextRule(before: 3, after: 4),
      );
      expect(saved.ok, isTrue);
      expect(writes.pending.value, 1);
      expect(
        controller.offline.read('/context-rules/global')!.body,
        contains('"before":3'),
      );
      server.unreachable = false;
      await writes.flush();
      expect(server.contextRules['global'], {'before': 3, 'after': 4});
    },
  );
}

List<Map<String, Object?>> _tagsOf(AppController c) {
  final body = c.offline.read('/tags')!.body;
  final j = (jsonDecode(body) as Map)['tags'] as List;
  return [for (final t in j) Map<String, Object?>.from(t as Map)];
}
