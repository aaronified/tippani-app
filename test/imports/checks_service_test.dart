import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/checks/checks_service.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

Future<(FakeServer, PairedChecksService)> _rig() async {
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
  return (server, PairedChecksService(controller));
}

void main() {
  test(
    'stray marks are read, and a finding is answered by its address',
    () async {
      final (server, service) = await _rig();
      Map<String, Object?>? accepted;
      String? bucket;
      server.extra = (r, path) async {
        if (path == '/cleanup' && r.method == 'GET') {
          bucket = r.url.queryParameters['bucket'];
          return server.json({
            'rules': ['double-space'],
            'items': [
              {
                'kind': 'book',
                'id': 5,
                'work_id': 2,
                'work_title': 'Walden',
                'findings': [
                  {
                    'rule': 'double-space',
                    'field': 'quote',
                    'snippet': 'a«  »b',
                    'after_snippet': 'a« »b',
                    'count': 2,
                    'match_hash': 'h1',
                  },
                ],
              },
            ],
            'counts': {'open': 1, 'ignored': 3},
            'truncated': true,
          });
        }
        if (path == '/cleanup/accept') {
          accepted = jsonDecode(r.body) as Map<String, Object?>;
          return server.json({'applied': 1, 'stale': 0, 'duplicates': 0});
        }
        return null;
      };

      final scan = await service.cleanup(ignored: true);
      expect(bucket, 'ignored');
      expect(scan.open, 1);
      expect(scan.ignored, 3);
      expect(scan.truncated, isTrue);
      final item = scan.items.single;
      final finding = item.findings.single;
      expect(finding.fixable, isTrue);
      expect(finding.count, 2);

      final r = await service.cleanupAccept([CleanupTarget(item, finding)]);
      expect(r.applied, 1);
      expect(accepted, {
        'items': [
          {
            'kind': 'book',
            'id': 5,
            'field': 'quote',
            'rule': 'double-space',
            'match_hash': 'h1',
          },
        ],
      });
    },
  );

  test('ignoring and restoring use their own routes', () async {
    final (server, service) = await _rig();
    final paths = <String>[];
    server.extra = (r, path) async {
      if (path.startsWith('/cleanup/')) {
        paths.add(path);
        return server.json({'ignored': 1});
      }
      return null;
    };
    const item = CleanupItem(
      kind: 'quote',
      id: 1,
      workId: 0,
      workTitle: '',
      findings: [],
    );
    const f = CleanupFinding(
      rule: 'edge-space',
      field: 'note',
      snippet: '',
      afterSnippet: '',
      count: 1,
      hash: 'x',
      ignored: false,
    );
    await service.cleanupIgnore([const CleanupTarget(item, f)], ignore: true);
    await service.cleanupIgnore([const CleanupTarget(item, f)], ignore: false);
    expect(paths, ['/cleanup/ignore', '/cleanup/unignore']);
  });

  test(
    'corrections are read, and an accept names the bucket and bulk',
    () async {
      final (server, service) = await _rig();
      Map<String, Object?>? sent;
      server.extra = (r, path) async {
        if (path == '/corrections' && r.method == 'GET') {
          return server.json({
            'buckets': [],
            'proposals': [
              {
                'kind': 'book',
                'id': 8,
                'work_id': 2,
                'work_title': 'Walden',
                'quote': 'a',
                'proposed': 'a,',
                'from': '',
                'to': ',',
                'bucket': 'punctuation',
                'edited': true,
              },
            ],
            'wrong_file': [
              {
                'kind': 'book',
                'work_id': 3,
                'work_title': 'Emma',
                'differing': 9,
                'total': 10,
              },
            ],
          });
        }
        if (path == '/corrections/accept') {
          sent = jsonDecode(r.body) as Map<String, Object?>;
          return server.json({
            'applied': 1,
            'stale': 2,
            'skipped': 3,
            'skipped_edited': 4,
            'duplicates': 5,
          });
        }
        return null;
      };

      final scan = await service.corrections();
      expect(scan.proposals.single.edited, isTrue);
      expect(scan.wrongFile.single.workTitle, 'Emma');
      final r = await service.correctionsAccept(
        'punctuation',
        scan.proposals,
        bulk: true,
      );
      expect(sent, {
        'bucket': 'punctuation',
        'bulk': true,
        'items': [
          {'kind': 'book', 'id': 8, 'quote': 'a', 'proposed': 'a,'},
        ],
      });
      expect(r.applied, 1);
      expect(r.skippedEdited, 4);
      expect(r.words, contains('Updated 1 quote'));
      expect(r.words, contains('2 had changed since you looked'));
    },
  );

  test(
    'times and places carry what the reader saw back to the server',
    () async {
      final (server, service) = await _rig();
      Map<String, Object?>? sent;
      server.extra = (r, path) async {
        if (path == '/locators/proposals') {
          return server.json({
            'counts': {'exact': 1, 'review': 1},
            'proposals': [
              {
                'kind': 'annotation',
                'id': 4,
                'quote': 'q',
                'work_id': 1,
                'work_title': 'Emma',
                'current': '',
                'current_end': '',
                'proposed': '34%',
                'proposed_end': '',
                'evidence': 'q',
                'bucket': 'exact',
                'current_chapter': '',
                'proposed_chapter': 'Chapter 3',
              },
            ],
          });
        }
        if (path == '/locators/accept') {
          sent = jsonDecode(r.body) as Map<String, Object?>;
          return server.json({'applied': 1});
        }
        return null;
      };
      final all = await service.locators();
      expect(all.single.isBook, isTrue);
      await service.locatorsAccept('exact', all);
      expect(sent!['bucket'], 'exact');
      final item = (sent!['items'] as List).single as Map;
      expect(item['kind'], 'annotation');
      expect(item['proposed'], '34%');
      expect(item['proposed_chapter'], 'Chapter 3');
    },
  );

  test('the badges add up what each check holds', () async {
    final (server, service) = await _rig();
    server.extra = (r, path) async {
      if (path == '/cleanup') {
        return server.json({
          'rules': [],
          'items': [],
          'counts': {'open': 4, 'ignored': 0},
        });
      }
      if (path == '/corrections') {
        return server.json({
          'buckets': [],
          'proposals': [
            {'kind': 'book', 'id': 1, 'quote': '', 'proposed': ''},
            {'kind': 'book', 'id': 2, 'quote': '', 'proposed': ''},
          ],
          'wrong_file': [],
        });
      }
      if (path == '/locators/proposals') {
        return server.json({
          'counts': {'exact': 3, 'review': 1},
          'proposals': [],
        });
      }
      return null;
    };
    final c = await service.counts();
    expect(c.strayMarks, 4);
    expect(c.corrections, 2);
    expect(c.locators, 4);
    expect(c.total, 10);
  });
}
