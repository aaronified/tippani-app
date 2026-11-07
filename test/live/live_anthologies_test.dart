// Runs the anthology and board code against a real Tippani server that has at least two quotes on one book.
// Skipped unless TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test('a real server takes every anthology call the screens make', () async {
    SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
      log: AppLog(),
    );
    await controller.load();
    expect((await controller.pair(_code ?? '', 'live anthologies')).ok, isTrue);
    final svc = ServerAnthologies(controller);

    final made = await svc.create('Live anthology', 'first lines');
    final id = made.id;
    final quotes = await controller.withClient(
      (c) async => (await c.getJson('/annotations')) as Map,
    );
    final rows = (quotes!['annotations'] as List).cast<Map>();
    expect(rows.length, greaterThanOrEqualTo(1));
    for (final r in rows) {
      await svc.add(id, 'book', (r['id'] as num).toInt());
    }

    // a heading at the end, then one at the top
    final s1 = await svc.addSection(id, 'Part one', 'words');
    var d = await svc.get(id);
    expect(d.slots.last.section?.id, s1.id);
    await svc.move(id, 'section', s1.id);
    d = await svc.get(id);
    expect(d.slots.first.section?.id, s1.id, reason: 'moved to the top');
    await svc.editSection(id, s1.id, 'Part 1', '');
    expect((await svc.get(id)).sections.single.title, 'Part 1');

    // commentary, grouping, front matter, switches
    final first = d.entries.first;
    await svc.setNote(id, first.kind, first.itemId, 'my words');
    await svc.setGrouping(id, 'work');
    await svc.setFront(id, 'an epigraph', 'a dedication');
    d = await svc.get(id);
    expect(
      d.entries.firstWhere((e) => e.itemId == first.itemId).note,
      'my words',
    );
    expect(d.anthology.groupBy, 'work');
    expect(d.anthology.epigraph, 'an epigraph');
    expect(d.anthology.dedication, 'a dedication');
    await svc.setSwitches(d.anthology, {
      'show_date': true,
      'hide_colour': true,
    });
    d = await svc.get(id);
    expect(d.anthology.flag('show_date'), isTrue);
    expect(
      d.anthology.groupBy,
      'work',
      reason: 'the full save did not clear it',
    );
    expect(d.anthology.epigraph, 'an epigraph');

    // a cover, a fill, taking out and putting back, the files
    // a real picture: the server refuses what it cannot decode
    final png = await File('assets/share/cotton.png').readAsBytes();
    final cover = await svc.setCover(id, png, 'c.png');
    expect(cover, matches(RegExp(r'^[0-9a-f]{16}\.png$')));
    expect((await svc.get(id)).anthology.coverPath, cover);
    await svc.removeCover(id);
    expect((await svc.get(id)).anthology.coverPath, '');

    final v = await svc.vocabulary();
    expect(v.colours, isNotEmpty);
    final preview = await svc.fill(id, fillRule(FillSource.all), preview: true);
    expect(preview.matched, greaterThanOrEqualTo(1));
    expect(preview.added, 0);

    final gone = (await svc.get(id)).entries.first;
    await svc.removeEntry(id, gone.kind, gone.itemId);
    final out = await svc.removed(id);
    expect(out.any((r) => r.itemId == gone.itemId), isTrue);
    await svc.restore(id, gone.kind, gone.itemId);
    expect(
      (await svc.removed(id)).any((r) => r.itemId == gone.itemId),
      isFalse,
    );
    expect(
      (await svc.get(id)).entries.any((e) => e.itemId == gone.itemId),
      isTrue,
    );

    final md = await svc.export(id);
    expect(md.name, 'Live anthology.md');
    expect(String.fromCharCodes(md.bytes), contains('Live anthology'));
    final epub = await svc.export(id, epub: true);
    expect(epub.bytes.sublist(0, 2), [0x50, 0x4b], reason: 'an EPUB is a zip');

    await svc.deleteSection(id, s1.id);
    await svc.delete(id);
  }, skip: skip);
}
