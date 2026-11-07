// Runs the Tags and Statistics code against a real Tippani server: a rename, a merge and a delete made on the
// server and on the phone leave the two alike, so the next sync finds nothing to bring or settle. Skipped unless
// TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/pull_sync.dart';
import 'package:tippani/sync/push_sync.dart';
import 'package:tippani/tags/tag_ops.dart';
import 'package:tippani/tags/tag_service.dart';
import 'package:tippani/tools/server_tools.dart';

import '../support/memory_library.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;

  test(
    'tags changed on both sides stay in step, and the statistics read',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final vault = MemoryTokenVault();
      final controller = AppController(
        SettingsStore(await SharedPreferences.getInstance(), vault),
        log: AppLog(),
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live tags')).ok, isTrue);
      final token = (await vault.read())!;

      Future<Object?> raw(String path) async {
        final res = await http.get(
          Uri.parse('$_url/api$path'),
          headers: {'Authorization': 'Bearer $token'},
        );
        return jsonDecode(res.body);
      }

      Future<List<String>> serverTags(int id) async {
        final all = ((await raw('/annotations') as Map)['annotations'] as List)
            .cast<Map>();
        return [
          for (final t in all.firstWhere((a) => a['id'] == id)['tags'] as List)
            '$t',
        ]..sort();
      }

      final lib = MemoryLibrary();
      final push = PushSync(lib, controller, log: AppLog());
      final pull = PullSync(lib, controller, log: AppLog());
      final book = await lib.addWork(
        const WorkDraft(title: 'Live Tags Book', creator: 'Tag Author'),
      );
      final q = await lib.addQuote(
        QuoteDraft(
          text: 'A line to tag (live tags).',
          workId: book.id,
          tags: const ['livea', 'liveb'],
        ),
      );
      expect((await push.push()).refused, isEmpty);
      final sid = (await lib.quote(q.id))!.serverId!;
      expect(await serverTags(sid), ['livea', 'liveb']);

      final svc = PairedTagService(controller);
      var tags = await svc.list();
      final a = tags.firstWhere((t) => t.name == 'livea');
      final b = tags.firstWhere((t) => t.name == 'liveb');
      expect(a.quotes, 1);

      // rename: the server first, then the phone
      await svc.save(a, name: 'livea2', color: 'green');
      await renameTagLocal(lib, 'livea', 'livea2');
      var r = await pull.sync();
      expect(r.conflicts, isEmpty, reason: 'both sides changed alike');
      expect(r.refused, isEmpty);
      expect(await serverTags(sid), ['livea2', 'liveb']);
      expect((await lib.quote(q.id))!.tags..sort(), ['livea2', 'liveb']);
      tags = await svc.list();
      expect(tags.firstWhere((t) => t.name == 'livea2').color, 'green');

      // merge
      final a2 = tags.firstWhere((t) => t.name == 'livea2');
      await svc.merge(a2, [b]);
      await mergeTagsLocal(lib, 'livea2', ['liveb']);
      r = await pull.sync();
      expect(r.conflicts, isEmpty);
      expect(await serverTags(sid), ['livea2']);
      expect((await lib.quote(q.id))!.tags, ['livea2']);

      // delete
      await svc.delete(a2);
      await deleteTagLocal(lib, 'livea2');
      r = await pull.sync();
      expect(r.conflicts, isEmpty);
      expect(await serverTags(sid), isEmpty);
      expect((await lib.quote(q.id))!.tags, isEmpty);

      // the statistics read, with every part the page needs
      final s = await PairedServerTools(controller).stats();
      expect(s.quotes, greaterThan(0));
      expect(s.recall.total, greaterThan(0));
      expect(s.breakdown['authors']!.top, isNotEmpty);
      expect(s.saves, isNotEmpty);
    },
    skip: skip,
  );
}
