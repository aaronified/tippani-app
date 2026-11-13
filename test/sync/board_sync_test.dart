import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';

import 'pull_sync_test.dart' show rig, Rig;

Map<String, Object?> board(int id, String name, {String color = 'yellow'}) => {
  'id': id,
  'name': name,
  'description': 'kept by the server',
  'color': color,
  'image_path': 'cover.png',
  'hidden': false,
  'pos': 0,
  'quotes': 0,
  'kind': 'speech',
  'languages': <String>[],
  'text_order': '',
};

Map<String, Object?> loose(String text, int? boardId) => {
  'quote': text,
  'speaker': '',
  'occasion': '',
  'place': '',
  'note': '',
  'color': 'yellow',
  'favorite': false,
  'tags': <String>[],
  'board_id': ?boardId,
};

Future<Board> boardNamed(Rig r, String name) async =>
    (await r.lib.boards()).firstWhere((b) => b.name == name);

void main() {
  test(
    'a board that is only on the server comes down with its colour',
    () async {
      final r = await rig();
      r.server.boards.add(board(7, 'Speeches', color: 'blue'));

      await r.pull.sync();

      final b = await boardNamed(r, 'Speeches');
      expect(b.serverId, 7);
      expect(b.color, 'blue');
    },
  );

  test(
    'a board that is only on the phone goes up once, and is not sent again',
    () async {
      final r = await rig();
      await r.lib.addBoard('Letters', color: 'green');

      await r.pull.sync();
      await r.pull.sync();

      expect(r.server.boards.map((b) => b['name']), ['Letters']);
      expect(r.server.boards.single['color'], 'green');
      expect(
        (await boardNamed(r, 'Letters')).serverId,
        r.server.boards.single['id'],
      );
    },
  );

  test(
    'boards with the same name on both sides are linked, not doubled',
    () async {
      final r = await rig();
      await r.lib.addBoard('speeches');
      r.server.boards.add(board(7, 'Speeches', color: 'pink'));

      await r.pull.sync();

      final all = await r.lib.boards();
      expect(all, hasLength(1));
      expect(all.single.serverId, 7);
      expect(r.server.boards, hasLength(1));
    },
  );

  test(
    'a rename on the phone is sent with what the server holds kept as it was',
    () async {
      final r = await rig();
      r.server.boards.add(board(7, 'Speeches'));
      await r.pull.sync();
      await r.lib.renameBoard((await boardNamed(r, 'Speeches')).id, 'Talks');

      await r.pull.sync();

      final row = r.server.boards.single;
      expect(row['name'], 'Talks');
      expect(row['description'], 'kept by the server');
      expect(row['kind'], 'speech');
      expect(row['image_path'], 'cover.png');
    },
  );

  test('a rename on the server comes down', () async {
    final r = await rig();
    r.server.boards.add(board(7, 'Speeches'));
    await r.pull.sync();
    r.server.boards.single['name'] = 'Talks';

    await r.pull.sync();

    expect((await r.lib.boards()).single.name, 'Talks');
  });

  test(
    'a board deleted on the phone is deleted there, its quotes moved',
    () async {
      final r = await rig();
      r.server.boards
        ..add(board(7, 'Speeches'))
        ..add(board(8, 'Others'));
      r.server.seed('/quotes', loose('Be water.', 7));
      await r.pull.sync();
      await r.lib.deleteBoard((await boardNamed(r, 'Speeches')).id);

      await r.pull.sync();

      expect(r.server.boards.map((b) => b['id']), [8]);
      expect(r.server.boardDeletes.single['move_to'], 8);
      expect(await r.lib.pendingDeletions(), isEmpty);
    },
  );

  test(
    'a board deleted on the server is removed here, its quote left on none',
    () async {
      final r = await rig();
      r.server.boards.add(board(7, 'Speeches'));
      r.server.seed('/quotes', loose('Be water.', 7));
      await r.pull.sync();
      r.server.boards.clear();

      await r.pull.sync();

      expect(await r.lib.boards(), isEmpty);
      expect((await r.lib.quotes()).single.boardId, isNull);
    },
  );

  test(
    'a quote that is filed on the server comes down on that board',
    () async {
      final r = await rig();
      r.server.boards.add(board(7, 'Speeches'));
      r.server.seed('/quotes', loose('Be water.', 7));

      await r.pull.sync();

      final b = await boardNamed(r, 'Speeches');
      expect((await r.lib.quotes()).single.boardId, b.id);
    },
  );

  test('moving a quote to another board on the phone moves it there', () async {
    final r = await rig();
    r.server.boards
      ..add(board(7, 'Speeches'))
      ..add(board(8, 'Proverbs'));
    final id = r.server.seed('/quotes', loose('Be water.', 7));
    await r.pull.sync();
    final q = (await r.lib.quotes()).single;
    await r.lib.setQuoteBoard(q.id, (await boardNamed(r, 'Proverbs')).id);

    await r.pull.sync();

    expect(r.server.row('/quotes', id)['board_id'], 8);
    expect(r.server.row('/quotes', id)['quote'], 'Be water.');
  });

  test('moving a quote to another board on the server moves it here', () async {
    final r = await rig();
    r.server.boards
      ..add(board(7, 'Speeches'))
      ..add(board(8, 'Proverbs'));
    final id = r.server.seed('/quotes', loose('Be water.', 7));
    await r.pull.sync();
    r.server.edit('/quotes', id, {'board_id': 8});

    await r.pull.sync();

    final b = await boardNamed(r, 'Proverbs');
    expect((await r.lib.quotes()).single.boardId, b.id);
  });

  test('moving one quote leaves the other quotes where they are', () async {
    final r = await rig();
    r.server.boards
      ..add(board(7, 'Speeches'))
      ..add(board(8, 'Proverbs'));
    final first = r.server.seed('/quotes', loose('Be water.', 7));
    final second = r.server.seed('/quotes', loose('Stay hungry.', 7));
    await r.pull.sync();
    final moved = (await r.lib.quotes()).firstWhere(
      (q) => q.text == 'Stay hungry.',
    );
    await r.lib.setQuoteBoard(moved.id, (await boardNamed(r, 'Proverbs')).id);

    await r.pull.sync();

    expect(r.server.row('/quotes', second)['board_id'], 8);
    expect(r.server.row('/quotes', second)['quote'], 'Stay hungry.');
    expect(r.server.row('/quotes', first)['board_id'], 7);
    expect(r.server.row('/quotes', first)['quote'], 'Be water.');
  });

  test(
    'a server that ignores ?id= never has one quote saved over another',
    () async {
      final r = await rig();
      r.server.ignoreIdFilter = true;
      r.server.boards
        ..add(board(7, 'Speeches'))
        ..add(board(8, 'Proverbs'));
      final first = r.server.seed('/quotes', loose('Be water.', 7));
      final second = r.server.seed('/quotes', loose('Stay hungry.', 7));
      await r.pull.sync();
      final moved = (await r.lib.quotes()).firstWhere(
        (q) => q.text == 'Stay hungry.',
      );
      await r.lib.setQuoteBoard(moved.id, (await boardNamed(r, 'Proverbs')).id);

      await r.pull.sync();

      expect(r.server.row('/quotes', first)['quote'], 'Be water.');
      expect(r.server.row('/quotes', second)['quote'], 'Stay hungry.');
    },
  );
}
