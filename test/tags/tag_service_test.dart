import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tags/tag_service.dart';

import '../support/fake_server.dart';

void main() {
  late FakeServer server;
  late PairedTagService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    server = FakeServer();
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
      clientFactory: server.factory,
    );
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    svc = PairedTagService(controller);
    server.tags.addAll([
      {
        'id': 1,
        'name': 'life',
        'color': 'blue',
        'style': 'tape',
        'annotations': 2,
        'dialogues': 1,
      },
      {
        'id': 2,
        'name': 'craft',
        'color': 'pink',
        'style': 'sticker',
        'annotations': 0,
        'dialogues': 0,
      },
    ]);
  });

  test('lists the tags with colour, style and how many quotes', () async {
    final all = await svc.list();
    expect(all.map((t) => t.name), ['life', 'craft']);
    expect(all.first.color, 'blue');
    expect(all.first.style, 'tape');
    expect(all.first.quotes, 3);
  });

  test('a tag counts the standalone quotes that wear it', () async {
    server.tags.add({
      'id': 3,
      'name': 'proverbs',
      'color': 'green',
      'style': 'sticker',
      'annotations': 0,
      'dialogues': 0,
      'utterances': 4,
    });
    final all = await svc.list();
    expect(all.firstWhere((t) => t.name == 'proverbs').quotes, 4);
  });

  test(
    'saving sends the whole tag, so an unchanged colour is not reset',
    () async {
      final life = (await svc.list()).first;
      final got = await svc.save(life, name: 'living');
      expect(got.name, 'living');
      expect(got.color, 'blue');
      expect(got.style, 'tape');
      expect(server.tagWrites, ['PUT 1']);
    },
  );

  test('a name that is taken is refused, in any capitals', () async {
    final life = (await svc.list()).first;
    expect(
      () => svc.save(life, name: 'CRAFT'),
      throwsA(
        isA<ServerException>().having(
          (e) => e.message,
          'message',
          'tag already exists',
        ),
      ),
    );
    expect(() => svc.create('Craft'), throwsA(isA<ServerException>()));
  });

  test('creates, merges and deletes', () async {
    final made = await svc.create('fresh', color: 'green');
    expect(made.color, 'green');
    final all = await svc.list();
    await svc.merge(all[0], [all[1]]);
    await svc.delete(all[0]);
    expect(server.tagWrites, ['POST fresh', 'MERGE 1<-2', 'DELETE 1']);
    expect((await svc.list()).map((t) => t.name), ['fresh']);
  });
}
