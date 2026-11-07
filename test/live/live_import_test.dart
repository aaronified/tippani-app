// Runs the import and checks code against a real Tippani server. Skipped unless TIPPANI_LIVE_URL and
// TIPPANI_LIVE_CODE are set (see live_sync_test.dart).
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/checks/checks_service.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  HttpOverrides.global = null;

  late AppController controller;
  late String token;

  Future<Object?> raw(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$_url/api$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode >= 400) {
      throw Exception('$method $path -> ${res.statusCode} ${res.body}');
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  setUpAll(() async {
    if (skip != null) return;
    SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
    final vault = MemoryTokenVault();
    controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), vault),
      log: AppLog(),
    );
    await controller.load();
    expect((await controller.pair(_code ?? '', 'live import')).ok, isTrue);
    token = (await vault.read())!;
  });

  test('a file is imported, looked over, edited and approved', () async {
    final service = PairedImportService(controller);
    final title = 'Live Import ${DateTime.now().millisecondsSinceEpoch}';
    final clip =
        '$title (Some Author)\n- Your Highlight on page 3 | location 30-31 | Added on Saturday, November 7, 2026 10:00:00 AM\n\nFirst live words.\n==========\n'
        '$title (Some Author)\n- Your Highlight on page 5 | location 50-51 | Added on Saturday, November 7, 2026 10:05:00 AM\n\nSecond live words.\n==========\n';

    final before = await service.pending();
    final o = await service.importFile(
      'My Clippings.txt',
      Uint8List.fromList(utf8.encode(clip)),
    );
    expect(o.ok, isTrue, reason: o.message);
    expect(o.staged, 2);
    expect(await service.pending(), before + 2);

    final s = await service.staged();
    final group = s.works.firstWhere((w) => w.title == title);
    expect(group.quotes, 2);
    final mine = s.quotes.where((q) => q.workId == group.id).toList();
    expect(mine, hasLength(2));

    // edit: colour, a favourite mark, and shift the page numbers back by one
    final sel = StagedSelector.quotes([for (final q in mine) q.id]);
    await service.edit(sel, const StagedEdit(color: 'blue', favorite: true));
    await service.edit(
      sel,
      const StagedEdit(
        shiftField: 'location',
        shiftOp: 'subtract',
        shiftValue: 1,
      ),
    );
    final after = (await service.staged(workId: group.id)).quotes;
    expect(after.every((q) => q.color == 'blue' && q.favorite), isTrue);
    expect(after.map((q) => q.location).toSet(), {'p.2', 'p.4'});

    // approve the group: the quotes land in the library under a new book
    final out = await service.approve(StagedSelector.works([group.id]));
    expect(out.ok, isTrue, reason: out.message);
    expect(out.added, greaterThanOrEqualTo(2));
    final books = ((await raw('GET', '/books')) as Map)['books'] as List;
    expect(books.any((b) => (b as Map)['title'] == title), isTrue);
    expect(await service.pending(), before);
  });

  test(
    'a file nothing claims is refused, and naming the format reads it',
    () async {
      final service = PairedImportService(controller);
      final o = await service.importFile(
        'notes.txt',
        Uint8List.fromList(utf8.encode('nothing like a format at all')),
      );
      expect(o.ok, isFalse);
      expect(o.message, isNotEmpty);
    },
  );

  test('stray marks are found, fixed, and ignored', () async {
    final checks = PairedChecksService(controller);
    final books = ((await raw('GET', '/books')) as Map)['books'] as List;
    final bookId = (books.first as Map)['id'];
    final made = await raw('POST', '/annotations', {
      'book_id': bookId,
      'quote': 'Two  spaces live ${DateTime.now().microsecondsSinceEpoch}.',
      'color': 'yellow',
    }) as Map;
    final scan = await checks.cleanup();
    final item = scan.items.firstWhere(
      (i) => i.id == made['id'] && i.kind == 'book',
    );
    final finding = item.findings.firstWhere((f) => f.rule == 'double-space');
    expect(finding.fixable, isTrue);
    expect(finding.snippet, contains('«'));

    final r = await checks.cleanupAccept([CleanupTarget(item, finding)]);
    expect(r.applied, 1);
    final all =
        ((await raw('GET', '/annotations')) as Map)['annotations'] as List;
    final fixed = all.cast<Map>().firstWhere((a) => a['id'] == made['id']);
    expect(fixed['quote'], isNot(contains('  ')));

    // a second mark is ignored, then restored
    final made2 = await raw('POST', '/annotations', {
      'book_id': bookId,
      'quote':
          'Another  doubled space ${DateTime.now().microsecondsSinceEpoch}.',
      'color': 'yellow',
    }) as Map;
    final scan2 = await checks.cleanup();
    final item2 = scan2.items.firstWhere(
      (i) => i.id == made2['id'] && i.kind == 'book',
    );
    final f2 = item2.findings.first;
    await checks.cleanupIgnore([CleanupTarget(item2, f2)], ignore: true);
    expect(
      (await checks.cleanup()).items.where(
        (i) => i.id == made2['id'] && i.kind == 'book',
      ),
      isEmpty,
    );
    final ignored = await checks.cleanup(ignored: true);
    expect(
      ignored.items.any((i) => i.id == made2['id'] && i.kind == 'book'),
      isTrue,
    );
    await checks.cleanupIgnore([CleanupTarget(item2, f2)], ignore: false);
    expect(
      (await checks.cleanup()).items.any(
        (i) => i.id == made2['id'] && i.kind == 'book',
      ),
      isTrue,
    );
  });

  test(
    'corrections, locators and the badges read from a real server',
    () async {
      final checks = PairedChecksService(controller);
      final c = await checks.corrections();
      expect(c.proposals, isA<List<Correction>>());
      final l = await checks.locators();
      expect(l, isA<List<LocatorProposal>>());
      final counts = await checks.counts();
      expect(counts.total, greaterThanOrEqualTo(0));
    },
  );
}
