// Runs the metadata tools against a real Tippani server. Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are
// set. It makes its own books (time-stamped) and removes them. A check against the web needs the server to have the
// internet; if it does not, the check reports the books as unreachable and that part of the test says nothing.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/metadata/metadata_service.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'gaps, duplicates, a check and its apply on a real server',
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
      expect((await controller.pair(_code ?? '', 'live metadata')).ok, isTrue);
      final meta = PairedMetadataService(controller);
      final stamp = DateTime.now().millisecondsSinceEpoch;

      Future<Object?> raw(
        String method,
        String path, [
        Map<String, Object?>? b,
      ]) => controller.withClient<Object?>((c) async {
        switch (method) {
          case 'POST':
            return await c.postJson(path, b ?? const {});
          case 'DELETE':
            return await c.delete(path);
          default:
            return await c.getJson(path);
        }
      });

      Future<int> book(String title, {String isbn = ''}) async {
        final r = await raw('POST', '/books', {
          'title': title,
          'author': 'Meta Tester',
          if (isbn.isNotEmpty) 'isbn': isbn,
        }) as Map;
        return r['id'] as int;
      }

      final a = await book('Meta Twice $stamp');
      final b = await book('Meta Twice $stamp');
      final pinned = await book('Pride and Prejudice', isbn: '9780141439518');
      final made = [a, b, pinned];
      try {
        // the gaps: our books lack a cover, and are listed with what they lack
        final works = await meta.works();
        final mine = works.firstWhere((w) => w.kind == 'book' && w.id == a);
        expect(mine.gaps, contains('Cover'));
        expect(mine.creator, 'Meta Tester');

        // saved twice: the pair is found, and merged into one
        final groups = await meta.duplicates();
        final group = groups.firstWhere((g) => g.any((w) => w.id == a));
        expect(group.map((w) => w.id), containsAll([a, b]));
        await meta.merge(book: true, into: a, from: [b]);
        made.remove(b);
        final after = await meta.works();
        expect(after.any((w) => w.kind == 'book' && w.id == b), isFalse);

        // a check of a book with an identity: answered, never written until applied
        final items = await meta.check([
          works.firstWhere((w) => w.kind == 'book' && w.id == pinned),
        ]);
        expect(items, hasLength(1));
        expect(items.single.id, pinned);
        final item = items.single;
        if (item.checked && item.diffs.any((d) => d.field == 'description')) {
          final d = item.diffs.firstWhere((d) => d.field == 'description');
          final results = await meta.apply([
            ApplyItem(
              type: 'book',
              id: pinned,
              set: {'description': d.fresh},
              sources: {if (item.source.isNotEmpty) 'description': item.source},
              expect: {'description': d.stored},
            ),
          ]);
          expect(results.single.ok, isTrue, reason: results.single.error);
          final now = await raw('GET', '/books/$pinned') as Map;
          expect('${now['description']}', isNotEmpty);
        }
      } finally {
        for (final id in made) {
          await raw('DELETE', '/books/$id');
        }
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
