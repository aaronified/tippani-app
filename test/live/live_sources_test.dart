// Runs the source-file code against a real Tippani server, paired as an admin (it sets a library folder, and puts it
// back). Skipped unless TIPPANI_LIVE_URL, TIPPANI_LIVE_CODE and TIPPANI_LIVE_DIR are set; the last names an empty
// folder that exists on the server's computer, which the test fills with a subtitle file and empties again.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sources/sources_service.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];
final _dir = Platform.environment['TIPPANI_LIVE_DIR'];

const _srt = '''1
00:00:01,000 --> 00:00:03,000
Of all the gin joints in all the towns in all the world,

2
00:00:03,500 --> 00:00:05,000
she walks into mine.

3
00:00:06,000 --> 00:00:08,000
Here's looking at you, kid.
''';

void main() {
  final skip = (_url == null || _code == null || _dir == null)
      ? 'set TIPPANI_LIVE_URL, TIPPANI_LIVE_CODE and TIPPANI_LIVE_DIR'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'upload, folders, scan, attach, prune, remove on a real server',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        log: AppLog(),
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live sources')).ok, isTrue);
      final sources = PairedSourcesService(controller);
      final stamp = DateTime.now().millisecondsSinceEpoch;

      Future<Object?> raw(
        String method,
        String path, [
        Map<String, Object?>? body,
      ]) async {
        final got = await controller.withClient<Object?>((c) async {
          switch (method) {
            case 'POST':
              return await c.postJson(path, body ?? const {});
            case 'PUT':
              return await c.putJson(path, body ?? const {});
            case 'DELETE':
              return await c.delete(path);
            default:
              return await c.getJson(path);
          }
        });
        return got;
      }

      // a book with a quote, and a film with a line
      final book = (await raw('POST', '/books', {
        'title': 'Live Source Book $stamp',
        'author': 'Tester',
      })) as Map;
      final bookId = book['id'] as int;
      await raw('POST', '/annotations', {
        'book_id': bookId,
        'quote': 'It was the best of times.',
      });
      final film = (await raw('POST', '/movies', {
        'title': 'Live Source Film $stamp',
        'media_type': 'movie',
      })) as Map;
      final filmId = film['id'] as int;
      await raw('POST', '/dialogues', {
        'movie_id': filmId,
        'quote': "Here's looking at you, kid.",
      });

      // an upload from the phone: attached, listed, read again, pruned after a preview, removed
      await sources.upload(
        bytes: utf8.encode(
          'Chapter 1\n\nIt was the best of times, it was the worst of times.\n',
        ),
        fileName: 'book.txt',
        subject: 'book',
        workId: bookId,
      );
      var list = await sources.attached();
      final mine = list.firstWhere(
        (s) => s.subject == 'book' && s.workId == bookId,
      );
      expect(mine.origin, 'upload');
      expect(mine.prunable, isTrue);
      await sources.rescan(mine.id);
      final preview = await sources.prunePreview(mine.id);
      expect(preview.bytes, greaterThan(0));
      await sources.prune(mine.id);
      list = await sources.attached();
      expect(list.firstWhere((s) => s.id == mine.id).state, 'pruned');
      await sources.remove(mine.id);
      list = await sources.attached();
      expect(list.any((s) => s.id == mine.id), isFalse);

      // a folder: the admin sets it, the phone sees its label, browses it and scans it
      final before =
          (await raw('GET', '/admin/mounts') as Map)['mounts'] as List;
      final folder = Directory(_dir ?? '');
      final file = File('${folder.path}/Live Source Film $stamp.srt');
      await file.writeAsString(_srt);
      try {
        await raw('PUT', '/admin/mounts', {
          'mounts': [
            for (final m in before)
              {'id': (m as Map)['id'], 'label': m['label'], 'path': m['path']},
            {
              'id': 'live-sources',
              'label': 'Live sources',
              'path': folder.path,
            },
          ],
        });
        final mounts = await sources.mounts();
        expect(mounts.any((m) => m.id == 'live-sources'), isTrue);

        final root = await sources.browse('live-sources', '');
        expect(root.root, isTrue);
        final entry = root.entries.firstWhere((e) => e.name.endsWith('.srt'));
        expect(entry.dir, isFalse);

        // the scan runs as a job; it ends, and what it found can be turned down or attached
        await sources.scan('live-sources');
        var state = const ScanState();
        for (var i = 0; i < 60; i++) {
          state = await sources.scanState('live-sources');
          if (!state.live && state.state != 'none') break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(state.live, isFalse, reason: 'the scan ended: ${state.state}');
        final result = await sources.found('live-sources');
        final candidate = result.found.where((f) => f.workId == filmId);
        if (candidate.isNotEmpty) {
          final f = candidate.first;
          final done = await sources.attachFound(f.bucket, [f.token]);
          expect(done.attached, 1);
        } else {
          // the folder was read but the name did not fit: choose the file by hand
          await sources.attachMounted(
            mountId: 'live-sources',
            rel: entry.rel,
            subject: 'screen',
            workId: filmId,
          );
        }
        list = await sources.attached();
        final film1 = list.firstWhere(
          (s) => s.subject == 'screen' && s.workId == filmId,
        );
        expect(film1.mounted, isTrue);
        expect(film1.prunable, isFalse);
        await sources.remove(film1.id);
      } finally {
        await raw('PUT', '/admin/mounts', {
          'mounts': [
            for (final m in before)
              {'id': (m as Map)['id'], 'label': m['label'], 'path': m['path']},
          ],
        });
        if (await file.exists()) await file.delete();
        await raw('DELETE', '/books/$bookId');
        await raw('DELETE', '/movies/$filmId');
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
