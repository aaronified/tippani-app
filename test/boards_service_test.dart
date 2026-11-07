import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/boards/board_service.dart';
import 'package:tippani/library/models.dart';

import 'sync/pull_sync_test.dart' show rig, Rig;

Map<String, Object?> serverBoard(int id, String name, {int pos = 0}) => {
  'id': id,
  'name': name,
  'description': 'kept by the server',
  'color': 'yellow',
  'image_path': '',
  'hidden': false,
  'pos': pos,
  'quotes': 0,
  'kind': 'plain',
  'languages': <String>[],
  'text_order': 'kept',
};

Future<(Rig, ServerBoards, Board)> linked({int pos = 0}) async {
  final r = await rig();
  r.server.boards.add(serverBoard(7, 'Speeches', pos: pos));
  await r.pull.sync();
  final b = (await r.lib.boards()).single;
  return (r, ServerBoards(r.controller, r.lib), b);
}

void main() {
  test('what the server holds comes down with the board', () async {
    final r = await rig();
    r.server.boards.add({
      ...serverBoard(7, 'Proverbs', pos: 3),
      'kind': 'proverb',
      'languages': ['Bengali', 'Hindi'],
      'hidden': true,
      'image_path': '0123456789abcdef.png',
      'description': 'old sayings',
    });
    await r.pull.sync();
    final b = (await r.lib.boards()).single;
    expect(b.kind, 'proverb');
    expect(b.languages, ['Bengali', 'Hindi']);
    expect(b.hidden, isTrue);
    expect(b.pos, 3);
    expect(b.imagePath, '0123456789abcdef.png');
    expect(b.description, 'old sayings');
  });

  test('a change the web makes to a board shows after the next sync', () async {
    final (r, _, _) = await linked();
    r.server.boards.single['hidden'] = true;
    r.server.boards.single['pos'] = 5;
    await r.pull.sync();
    final b = (await r.lib.boards()).single;
    expect(b.hidden, isTrue);
    expect(b.pos, 5);
  });

  test(
    'an edit sends the server\'s whole board with only the change',
    () async {
      final (r, svc, b) = await linked();
      await svc.update(b, {'hidden': true, 'kind': 'speech'});
      final sent = r.server.boardWrites.last;
      expect(sent['hidden'], true);
      expect(sent['kind'], 'speech');
      expect(
        sent['text_order'],
        'kept',
        reason: 'what the phone does not show stays',
      );
      expect(sent['description'], 'kept by the server');
      expect(sent['name'], 'Speeches');
      // and the phone shows it at once
      final now = (await r.lib.boards()).single;
      expect(now.hidden, isTrue);
      expect(now.kind, 'speech');
    },
  );

  test(
    'the server\'s current board is the one changed, not an old copy',
    () async {
      final (r, svc, b) = await linked();
      // the web moved it after the phone last looked
      r.server.boards.single['pos'] = 9;
      await svc.update(b, {'hidden': true});
      expect(r.server.boardWrites.last['pos'], 9);
    },
  );

  test('a board not on the server yet says so instead of trying', () async {
    final r = await rig();
    final b = await r.lib.addBoard('Local only');
    final svc = ServerBoards(r.controller, r.lib);
    await expectLater(
      svc.update(b, {'hidden': true}),
      throwsA(isA<BoardException>()),
    );
    expect(r.server.boardWrites, isEmpty);
  });

  test('a picture goes up and its name comes back to the board', () async {
    final (r, svc, b) = await linked();
    await svc.setImage(b, Uint8List.fromList([1, 2, 3]), 'p.png');
    expect(r.server.boardPictures[7], isNotNull);
    final now = (await r.lib.boards()).single;
    expect(now.imagePath, matches(RegExp(r'^[0-9a-f]{16}\.png$')));
    await svc.removeImage(now);
    expect((await r.lib.boards()).single.imagePath, '');
    expect(r.server.boardWrites.last['image_path'], '');
  });

  test('starter proverbs are listed, and filed on the board', () async {
    final (r, svc, b) = await linked();
    final offers = await svc.starters();
    expect(offers.map((o) => (o.language, o.count)), [
      ('Bengali', 12),
      ('English', 10),
    ]);
    expect(await svc.addStarters(b, 'Bengali'), 12);
    expect(r.server.starterSeeds.single, {
      'language': 'Bengali',
      'board_id': 7,
    });
  });

  test('the kinds have words', () {
    expect(boardKindLabel('proverb'), 'Proverbs');
    expect(boardKindLabel('weird'), 'Plain');
  });
}
