import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

Future<(FakeServer, PairedImportService)> _rig() async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  await controller.pair('ABCD2345', 'My phone');
  return (
    server,
    PairedImportService(controller, poll: const Duration(milliseconds: 1)),
  );
}

Map<String, Object?> _job(String state, {int done = 0, int total = 1}) => {
  'job': {
    'id': 7,
    'state': state,
    'done': done,
    'total': total,
    'counts': <String, Object?>{},
    'error': '',
  },
};

void main() {
  test(
    'a file goes up, the job is waited for, and the outcome is read',
    () async {
      final (server, service) = await _rig();
      var polls = 0;
      String? sentAs;
      String? sentBody;
      server.extra = (r, path) async {
        if (r.method == 'POST' && path == '/import/auto') {
          sentBody = utf8.decode(r.bodyBytes, allowMalformed: true);
          sentAs = RegExp(r'name="as"\r\n\r\n(\w[\w-]*)')
              .firstMatch(sentBody!)?[1];
          return server.json(_job('queued'), 202);
        }
        if (path == '/jobs/7') {
          polls++;
          return server.json(
            polls < 3
                ? _job('running', done: polls, total: 3)
                : _job('succeeded', done: 3, total: 3),
          );
        }
        if (path == '/jobs/7/result') {
          return server.json({
            'kind': 'import',
            'result': {
              'status': 200,
              'body': {
                'source': 'kindle_clippings',
                'staged': 2,
                'near_duplicates': 1,
                'pending': 5,
                'works': [
                  {'id': 1, 'title': 'Walden'},
                ],
              },
            },
          });
        }
        return null;
      };
      final progress = <(int, int)>[];

      final o = await service.importFile(
        'My Clippings.txt',
        Uint8List.fromList(utf8.encode('Walden (Thoreau)\n')),
        onProgress: (d, t) => progress.add((d, t)),
      );

      expect(o.ok, isTrue);
      expect(o.source, 'kindle_clippings');
      expect(o.staged, 2);
      expect(o.works, 1);
      expect(o.nearDuplicates, 1);
      expect(o.pending, 5);
      expect(sentBody, contains('Walden (Thoreau)'));
      expect(
        sentAs,
        isNull,
        reason: 'the server tells the format from the file',
      );
      expect(progress.last, (3, 3));
      expect(polls, 3);
    },
  );

  test('a format the reader names is sent as the "as" field', () async {
    final (server, service) = await _rig();
    String? body;
    server.extra = (r, path) async {
      if (path == '/import/auto') {
        body = utf8.decode(r.bodyBytes, allowMalformed: true);
        return server.json(_job('queued'), 202);
      }
      if (path == '/jobs/7') return server.json(_job('succeeded'));
      if (path == '/jobs/7/result') {
        return server.json({
          'result': {
            'status': 200,
            'body': {
              'source': 'goodreads_html',
              'staged': 1,
              'pending': 1,
              'works': [],
            },
          },
        });
      }
      return null;
    };
    await service.importFile('q.html', Uint8List(1), as: 'goodreads-html');
    expect(body, contains('name="as"'));
    expect(body, contains('goodreads_html'));
    expect(body, isNot(contains('goodreads-html')));
  });

  test(
    'a file nothing claims comes back as a refusal the reader can answer',
    () async {
      final (server, service) = await _rig();
      server.extra = (r, path) async {
        if (path == '/import/auto') return server.json(_job('queued'), 202);
        if (path == '/jobs/7') {
          return server.json({
            'job': {
              'id': 7,
              'state': 'failed',
              'done': 1,
              'total': 1,
              'error': 'x',
            },
          });
        }
        if (path == '/jobs/7/result') {
          return server.json({
            'result': {
              'status': 422,
              'body': {'error': 'Nothing in this file says what it is.'},
            },
          });
        }
        return null;
      };
      final o = await service.importFile('mystery.bin', Uint8List(1));
      expect(o.ok, isFalse);
      expect(o.unknownFormat, isTrue);
      expect(o.message, contains('Nothing in this file'));
    },
  );

  test('the queue is read into batches, groups and quotes', () async {
    final (server, service) = await _rig();
    server.extra = (r, path) async {
      if (r.method == 'GET' && path == '/import/staged') {
        return server.json({
          'pending': 2,
          'total': 2,
          'batches': [
            {
              'id': 1,
              'source': 'kindle_clippings',
              'filename': 'c.txt',
              'works': 1,
              'quotes': 2,
            },
          ],
          'works': [
            {
              'id': 4,
              'batch_id': 1,
              'kind': 'book',
              'title': 'Walden',
              'author': 'Thoreau',
              'release_year': 1854,
              'quotes': 2,
              'target_id': 9,
              'target_title': 'Walden',
              'target_year': 1854,
              'ambiguous': true,
            },
          ],
          'quotes': [
            {
              'id': 11,
              'staged_work_id': 4,
              'quote': 'Simplify.',
              'color': 'blue',
              'favorite': true,
              'location': 'p.8',
              'tags': ['life'],
            },
          ],
        });
      }
      return null;
    };
    final s = await service.staged();
    expect(s.pending, 2);
    expect(s.batches.single.filename, 'c.txt');
    expect(s.works.single.targetId, 9);
    expect(s.works.single.ambiguous, isTrue);
    expect(s.quotes.single.favorite, isTrue);
    expect(s.quotes.single.tags, ['life']);
    expect(s.quotes.single.location, 'p.8');
  });

  test('approve sends the selection and reads how it went', () async {
    final (server, service) = await _rig();
    Map<String, Object?>? sent;
    server.extra = (r, path) async {
      if (r.method == 'POST' && path == '/import/staged/approve') {
        sent = jsonDecode(r.body) as Map<String, Object?>;
        return server.json(_job('queued'), 202);
      }
      if (path == '/jobs/7') {
        return server.json({
          'job': {
            'id': 7,
            'state': 'succeeded',
            'done': 1,
            'total': 1,
            'counts': {'added': 3, 'skipped': 1},
          },
        });
      }
      if (path == '/jobs/7/result') {
        return server.json({
          'result': {
            'status': 200,
            'body': {'quotes_relinked': 2},
          },
        });
      }
      return null;
    };
    final out = await service.approve(const StagedSelector.quotes([11, 12]));
    expect(sent, {
      'ids': [11, 12],
    });
    expect(out.ok, isTrue);
    expect(out.added, 3);
    expect(out.skipped, 1);
    expect(out.relinked, 2);
  });

  test(
    'every source the reader can pick is sent under the name the server reads',
    () {
      // The server's own slugs, from internal/importer/detect.go.
      const serverSlugs = {
        'md',
        'readest_json',
        'bookcision',
        'kindle_notebook',
        'goodreads_html',
        'hardcover_html',
        'imdb',
        'kindle_clippings',
      };
      final sent = {for (final s in importSources) serverImportSlug(s.kind)};
      expect(sent, serverSlugs);
    },
  );

  test('discard sends the selection in a DELETE body', () async {
    final (server, service) = await _rig();
    Object? sent;
    server.extra = (r, path) async {
      if (r.method == 'DELETE' && path == '/import/staged') {
        sent = jsonDecode(r.body);
        return server.json({'discarded': 4, 'pending': 0});
      }
      return null;
    };
    expect(await service.discard(const StagedSelector.batch(3)), 4);
    expect(sent, {'batch_id': 3});
  });

  test(
    'an edit carries only what changed, and a shift becomes a formula',
    () async {
      final (server, service) = await _rig();
      Map<String, Object?>? sent;
      server.extra = (r, path) async {
        if (path == '/import/staged/bulk') {
          sent = jsonDecode(r.body) as Map<String, Object?>;
          return server.json({'updated': 2});
        }
        return null;
      };
      final n = await service.edit(
        const StagedSelector.quotes([1, 2]),
        const StagedEdit(
          color: 'pink',
          chapter: '',
          shiftField: 'location',
          shiftOp: 'subtract',
          shiftValue: 5,
        ),
      );
      expect(n, 2);
      expect(sent, {
        'ids': [1, 2],
        'color': 'pink',
        'chapter': '',
        'formula': {'field': 'location', 'op': 'subtract', 'value': 5.0},
      });
      expect(sent!.containsKey('favorite'), isFalse);
    },
  );

  test('moving a group onto a library work sends a retarget', () async {
    final (server, service) = await _rig();
    Map<String, Object?>? sent;
    server.extra = (r, path) async {
      if (path == '/import/staged/bulk') {
        sent = jsonDecode(r.body) as Map<String, Object?>;
        return server.json({'updated': 1});
      }
      return null;
    };
    await service.move(
      const StagedSelector.works([4]),
      onto: const WorkChoice('book', 12, 'Walden', 1854, 'Thoreau'),
    );
    expect(sent, {
      'work_ids': [4],
      'retarget': {'kind': 'book', 'id': 12},
    });
    await service.move(const StagedSelector.works([4]), mergeInto: 5);
    expect(sent!['retarget'], {'staged_work_id': 5});
  });

  test('a server that is not paired says so in plain words', () async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    );
    await controller.load();
    final service = PairedImportService(controller);
    expect(service.available, isFalse);
    await expectLater(service.pending(), throwsA(isA<ServerException>()));
  });

  test('every format has its steps, and the file chooser takes them all', () {
    expect(importSources.map((s) => s.kind), contains('kindle-clippings'));
    for (final s in importSources) {
      expect(s.steps, isNotEmpty, reason: s.kind);
    }
    expect(importExtensions, containsAll(['md', 'json', 'html', 'txt']));
    expect(importSourceOf('goodreads-html')!.title, 'Goodreads');
  });
}
