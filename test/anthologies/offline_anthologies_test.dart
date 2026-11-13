import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/anthologies/offline_anthologies.dart';
import 'package:tippani/api/offline_cache.dart';
import 'package:tippani/settings/settings_store.dart';

// Anthologies with no server (ADR-0022). A reader makes and edits them where there is no signal; what they did
// shows at once from the phone's copy, and goes to the server, in the order it was done, the next time it
// answers. The server here is a small model that can be switched off; the layer under test is the real one.

/// A server that holds anthologies in memory and can be unreachable. It keeps the phone's cache the way the API
/// client does: every read it answers is remembered.
class _Server implements AnthologyService {
  _Server(this.cache);

  final OfflineCache cache;
  bool up = true;
  int _next = 100;
  final rows = <int, Map<String, Object?>>{};
  final entries = <int, List<Map<String, Object?>>>{};
  final sections = <int, List<Map<String, Object?>>>{};
  final sent = <String>[];
  Set<int> refuse = {};

  /// When set, `edit` waits for it: a request that is out while the reader goes on working.
  Completer<void>? hold;

  @override
  bool get available => true;

  void _reach() {
    if (!up) {
      throw const AnthologyException('no route', unreachable: true);
    }
  }

  Map<String, Object?> _row(int id) => {
    ...rows[id]!,
    'entries': entries[id]!.length,
  };

  Future<void> _remember() async {
    await cache.write(
      '/anthologies',
      jsonEncode({
        'anthologies': [for (final id in rows.keys) _row(id)],
      }),
    );
  }

  @override
  Future<List<Anthology>> list() async {
    _reach();
    await _remember();
    return [for (final id in rows.keys) Anthology.fromJson(_row(id))];
  }

  @override
  Future<AnthologyDetail> get(int id) async {
    _reach();
    if (!rows.containsKey(id)) throw const AnthologyException('not found');
    await cache.write(
      '/anthologies/$id',
      jsonEncode({
        'anthology': _row(id),
        'entries': entries[id],
        'sections': sections[id],
      }),
    );
    return AnthologyDetail(
      Anthology.fromJson(_row(id)),
      [for (final e in entries[id]!) AnthologyEntry.fromJson(e)],
      [for (final s in sections[id]!) AnthologySection.fromJson(s)],
    );
  }

  @override
  Future<Anthology> create(String title, String intro) async {
    _reach();
    sent.add('create $title');
    final id = _next++;
    rows[id] = {'id': id, 'title': title, 'intro': intro};
    entries[id] = [];
    sections[id] = [];
    return Anthology.fromJson(_row(id));
  }

  @override
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  }) async {
    _reach();
    if (hold != null) await hold!.future;
    if (refuse.contains(a.id)) throw const AnthologyException('it is gone');
    sent.add('edit ${a.id} $title');
    rows[a.id]!
      ..['title'] = title
      ..['intro'] = intro;
  }

  @override
  Future<bool> add(int id, String kind, int itemId) async {
    _reach();
    sent.add('add $id $kind/$itemId');
    entries[id]!.add({
      'kind': kind,
      'item_id': itemId,
      'position': entries[id]!.length + 1.0,
      'quote': 'from the server',
      'note': '',
      'source': '',
      'credit': '',
      'color': 'yellow',
      'language': '',
      'locator': '',
    });
    return true;
  }

  @override
  Future<void> setNote(int id, String kind, int itemId, String note) async {
    _reach();
    sent.add('note $id $kind/$itemId $note');
    for (final e in entries[id]!) {
      if (e['kind'] == kind && e['item_id'] == itemId) e['note'] = note;
    }
  }

  @override
  Future<void> removeEntry(int id, String kind, int itemId) async {
    _reach();
    sent.add('remove $id $kind/$itemId');
    entries[id]!.removeWhere(
      (e) => e['kind'] == kind && e['item_id'] == itemId,
    );
  }

  @override
  Future<AnthologySection> addSection(
    int id,
    String title,
    String prose, {
    ({String kind, int itemId})? after,
  }) async {
    _reach();
    sent.add('section $id $title after ${after?.itemId}');
    final s = {'id': _next++, 'position': 9.0, 'title': title, 'prose': prose};
    sections[id]!.add(s);
    return AnthologySection.fromJson(s);
  }

  @override
  Future<void> editSection(
    int id,
    int sectionId,
    String title,
    String prose,
  ) async {
    _reach();
    sent.add('editSection $id/$sectionId $title');
  }

  @override
  Future<void> delete(int id) async {
    _reach();
    sent.add('delete $id');
    rows.remove(id);
  }

  @override
  Future<String> setCover(int id, Uint8List bytes, String fileName) async {
    _reach();
    sent.add('cover $id ${bytes.length} $fileName');
    return 'c.jpg';
  }

  @override
  Future<FillResult> fill(
    int id,
    String rule, {
    bool preview = false,
    bool auto = false,
  }) async {
    _reach();
    sent.add('fill $id $rule $auto');
    return const FillResult(added: 1, matched: 1, skipped: 0, capped: false);
  }

  @override
  Future<FillVocabulary> vocabulary() async {
    _reach();
    return const FillVocabulary();
  }

  @override
  Future<ExportedFile> export(int id, {bool epub = false}) async {
    _reach();
    return ExportedFile('x.md', Uint8List(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<
  ({
    _Server server,
    OfflineAnthologies service,
    SettingsStore store,
    OfflineCache cache,
  })
>
_rig({PassageLookup? lookup}) async {
  SharedPreferences.setMockInitialValues({});
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final cache = OfflineCache(store);
  final server = _Server(cache);
  final service = OfflineAnthologies(server, cache, store, lookup: lookup);
  return (server: server, service: service, store: store, cache: cache);
}

void main() {
  test(
    'an anthology made with no server is there at once and goes up later',
    () async {
      final r = await _rig();
      r.server.up = false;
      final made = await r.service.create('Proverbs', 'Ones I like');
      expect(made.id, lessThan(0), reason: 'not on the server yet');
      expect((await r.service.list()).map((a) => a.title), ['Proverbs']);
      expect(r.service.pending.value, 1);

      r.server.up = true;
      expect(await r.service.flush(), 1);
      expect(r.server.sent, ['create Proverbs']);
      final all = await r.service.list();
      expect(all.single.id, greaterThan(0));
      expect(all.single.title, 'Proverbs');
      expect(r.service.pending.value, 0);
    },
  );

  test(
    'changes made to it while it is still only here follow it to its real id',
    () async {
      final r = await _rig();
      r.server.up = false;
      final made = await r.service.create('Draft', '');
      await r.service.edit(made, title: 'Final', intro: 'Done');
      await r.service.add(made.id, 'book', 7);
      await r.service.addSection(made.id, 'Part one', '');
      final open = await r.service.get(made.id);
      expect(open.anthology.title, 'Final');
      expect(open.entries.single.itemId, 7);
      expect(open.sections.single.title, 'Part one');

      r.server.up = true;
      expect(await r.service.flush(), 4);
      expect(r.server.sent, [
        'create Draft',
        'edit 100 Final',
        'add 100 book/7',
        'section 100 Part one after null',
      ]);
      expect((await r.service.get(100)).entries.single.itemId, 7);
    },
  );

  test(
    'a passage added with no server shows its words when the phone knows them',
    () async {
      final r = await _rig(
        lookup: (kind, id) async => kind == 'utterance' && id == 3
            ? {'quote': 'Well begun is half done.'}
            : null,
      );
      r.server.up = true;
      final made = await r.service.create('Proverbs', '');
      await r.service.list();
      r.server.up = false;
      await r.service.add(made.id, 'utterance', 3);
      final open = await r.service.get(made.id);
      expect(open.entries.single.quote, 'Well begun is half done.');
      expect(
        await r.service.add(made.id, 'utterance', 3),
        isFalse,
        reason: 'already in it',
      );
    },
  );

  test(
    'notes and removals made with no server are applied here and sent in order',
    () async {
      final r = await _rig();
      final made = await r.service.create('Proverbs', '');
      await r.service.add(made.id, 'book', 1);
      await r.service.add(made.id, 'book', 2);
      await r.service.get(made.id);
      r.server.up = false;
      await r.service.setNote(made.id, 'book', 1, 'my favourite');
      await r.service.removeEntry(made.id, 'book', 2);
      final open = await r.service.get(made.id);
      expect(open.entries.map((e) => e.itemId), [1]);
      expect(open.entries.single.note, 'my favourite');

      r.server.up = true;
      await r.service.flush();
      expect(r.server.sent.sublist(3), [
        'note ${made.id} book/1 my favourite',
        'remove ${made.id} book/2',
      ]);
    },
  );

  test('a change made online waits behind changes already waiting', () async {
    final r = await _rig();
    final made = await r.service.create('A', '');
    r.server.up = false;
    await r.service.setNote(made.id, 'book', 1, 'first');
    r.server.up = true;
    await r.service.setNote(made.id, 'book', 1, 'second');
    expect(r.server.sent.where((s) => s.startsWith('note')), [
      'note ${made.id} book/1 first',
      'note ${made.id} book/1 second',
    ]);
    expect(r.service.pending.value, 0);
  });

  test(
    'a change the server refuses is dropped and the ones behind it still go',
    () async {
      final r = await _rig();
      final a = await r.service.create('A', '');
      final b = await r.service.create('B', '');
      r.server.up = false;
      await r.service.edit(a, title: 'A2', intro: '');
      await r.service.edit(b, title: 'B2', intro: '');
      r.server.up = true;
      r.server.refuse = {a.id};
      await r.service.flush();
      expect(r.server.sent.where((s) => s.startsWith('edit')), [
        'edit ${b.id} B2',
      ]);
      expect(r.service.problems.value, ['it is gone']);
      expect(r.service.pending.value, 0);
    },
  );

  test('a count of what a fill would find, and an EPUB, need the server and say so instead of queueing', () async {
    final r = await _rig();
    r.server.up = false;
    final made = await r.service.create('Draft', '');
    await expectLater(
      r.service.fill(made.id, 'tag:x', preview: true),
      throwsA(isA<AnthologyException>()),
    );
    expect(r.service.pending.value, 1, reason: 'only the creation waits');
  });

  test('the queue survives the app closing', () async {
    final r = await _rig();
    r.server.up = false;
    await r.service.create('Kept', '');
    final again = OfflineAnthologies(r.server, OfflineCache(r.store), r.store);
    expect(again.pending.value, 1);
    r.server.up = true;
    expect(await again.flush(), 1);
    expect(r.server.sent, ['create Kept']);
  });

  test('a change made while a send is out is kept, not written over', () async {
    final r = await _rig();
    final a = await r.service.create('A', '');
    r.server.up = false;
    await r.service.edit(a, title: 'A2', intro: '');
    await r.service.setNote(a.id, 'book', 1, 'first');
    r.server.up = true;
    r.server.hold = Completer<void>();
    final flushing = r.service.flush();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // the edit is out; the reader goes on working
    r.server.up = false;
    await r.service.setNote(a.id, 'book', 1, 'second');
    r.server.up = true;
    r.server.hold!.complete();
    await flushing;
    await r.service.flush();
    expect(r.server.sent.where((x) => x.startsWith('note')), [
      'note ${a.id} book/1 first',
      'note ${a.id} book/1 second',
    ]);
    expect(r.service.pending.value, 0);
  });

  test('a screen opened before the anthology was sent goes on working with its temporary id', () async {
    final r = await _rig();
    r.server.up = false;
    final made = await r.service.create('Draft', '');
    final tmp = made.id;
    r.server.up = true;
    await r.service.flush();
    // the screen still holds the temporary id: it reads, edits and adds through it
    final open = await r.service.get(tmp);
    expect(open.anthology.id, greaterThan(0));
    await r.service.edit(
      Anthology.fromJson({...made.raw}),
      title: 'Final',
      intro: '',
    );
    await r.service.add(tmp, 'book', 9);
    expect(r.server.rows[open.anthology.id]!['title'], 'Final');
    expect(r.server.entries[open.anthology.id]!.single['item_id'], 9);
    // and the next anthology made with no server does not reuse its temporary id
    r.server.up = false;
    final next = await r.service.create('Another', '');
    expect(next.id, isNot(tmp));
  });

  test(
    'a heading added with no server is sent after the passage it was put after',
    () async {
      final r = await _rig();
      final a = await r.service.create('A', '');
      await r.service.get(a.id);
      r.server.up = false;
      await r.service.addSection(
        a.id,
        'Part two',
        '',
        after: (kind: 'book', itemId: 4),
      );
      r.server.up = true;
      await r.service.flush();
      expect(r.server.sent.last, 'section ${a.id} Part two after 4');
    },
  );

  test(
    'a section made with no server is edited and removed under its real id',
    () async {
      final r = await _rig();
      final a = await r.service.create('A', '');
      r.server.up = false;
      final s = await r.service.addSection(a.id, 'Part one', '');
      await r.service.editSection(a.id, s.id, 'Part one, renamed', 'prose');
      r.server.up = true;
      await r.service.flush();
      final real = r.server.sections[a.id]!.single['id'];
      expect(r.server.sent.last, 'editSection ${a.id}/$real Part one, renamed');
    },
  );

  test(
    'a cover picture and a fill made with no server are queued and sent',
    () async {
      final r = await _rig();
      final a = await r.service.create('A', '');
      await r.service.get(a.id);
      r.server.up = false;
      await r.service.setCover(
        a.id,
        Uint8List.fromList([1, 2, 3]),
        'poster.jpg',
      );
      await r.service.fill(a.id, 'tag:proverb', auto: true);
      expect(r.service.pending.value, 2);
      r.server.up = true;
      await r.service.flush();
      expect(r.server.sent.sublist(r.server.sent.length - 2), [
        'cover ${a.id} 3 poster.jpg',
        'fill ${a.id} tag:proverb true',
      ]);
    },
  );

  test(
    'a Markdown export with no server is made from the phone\'s copy',
    () async {
      final r = await _rig();
      final a = await r.service.create('Proverbs', 'Ones I like');
      await r.service.add(a.id, 'book', 1);
      await r.service.get(a.id);
      r.server.up = false;
      final file = await r.service.export(a.id);
      final text = utf8.decode(file.bytes);
      expect(file.name, 'Proverbs.md');
      expect(text, contains('# Proverbs'));
      expect(text, contains('Ones I like'));
      await expectLater(
        r.service.export(a.id, epub: true),
        throwsA(isA<AnthologyException>()),
      );
    },
  );

  test('unpairing (the cache is cleared) forgets what waited, so it is never sent to another account', () async {
    final r = await _rig();
    r.server.up = false;
    await r.service.create('Draft', '');
    expect(r.service.pending.value, 1);
    await r.cache.clear();
    expect(r.service.pending.value, 0);
    r.server.up = true;
    expect(await r.service.flush(), 0);
    expect(r.server.sent, isEmpty);
  });
}
