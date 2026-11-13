import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/work_keeper.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_details_source.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Details implements WorkDetailsSource {
  final asked = <int>[];
  bool answer = true;

  @override
  Future<WorkDetails?> fetch(Work work) async {
    asked.add(work.serverId!);
    return answer
        ? WorkDetails(
            description: 'About ${work.title}',
            fetchedAt: DateTime.utc(2026, 11, 13),
          )
        : null;
  }

  @override
  Future<WorkDetails?> setStatus(
    Work work,
    String status, {
    int progress = 0,
  }) async => null;
}

void main() {
  late FakeServer server;
  late CoverCache covers;
  late MemoryLibrary lib;
  late _Details details;
  final clock = DateTime.utc(2026, 11, 13, 12);

  Future<void> rig() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    server = FakeServer();
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
      clientFactory: server.factory,
    );
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    final dir = await Directory.systemTemp.createTemp('tippani_keeper');
    addTearDown(() => dir.delete(recursive: true));
    covers = CoverCache(controller, folder: Directory('${dir.path}/covers'));
    lib = MemoryLibrary();
    details = _Details();
  }

  Future<Work> addWork(String title, int serverId, {String cover = ''}) async {
    final w = await lib.addWork(WorkDraft(title: title));
    await lib.setWorkServerId(w.id, serverId);
    if (cover.isNotEmpty) await lib.setWorkCover(w.id, cover);
    return (await lib.work(w.id))!;
  }

  test('covers and details of every work are kept, and only what is missing is asked for', () async {
    await rig();
    const one = '0123456789abcdef.png';
    const two = 'fedcba9876543210.png';
    server.covers[one] = png;
    server.covers[two] = png;
    final a = await addWork('Walden', 3, cover: one);
    await addWork('Dune', 4, cover: two);

    final made = await keepWorkExtras(lib, covers, details, clock: () => clock);
    expect(made, 4, reason: 'two covers and two details');
    expect(await covers.kept(one), isTrue);
    expect(await covers.kept(two), isTrue);
    expect((await lib.work(a.id))!.details.description, 'About Walden');

    final again = await keepWorkExtras(
      lib,
      covers,
      details,
      clock: () => clock,
    );
    expect(again, 0, reason: 'nothing is asked for twice');
    expect(server.coverReads, unorderedEquals([one, two]));
  });

  test(
    'details are read again after two weeks, and a run is bounded',
    () async {
      await rig();
      await addWork('Walden', 3);
      await keepWorkExtras(lib, covers, details, clock: () => clock);
      expect(details.asked, [3]);

      await keepWorkExtras(
        lib,
        covers,
        details,
        clock: () => clock.add(const Duration(days: 15)),
      );
      expect(details.asked, [
        3,
        3,
      ], reason: 'a month-old shelf is asked about again');

      for (var i = 0; i < 5; i++) {
        await addWork('Book $i', 10 + i);
      }
      details.asked.clear();
      final made = await keepWorkExtras(
        lib,
        covers,
        details,
        limit: 2,
        clock: () => clock.add(const Duration(days: 40)),
      );
      expect(
        made,
        2,
        reason: 'a run stops at its limit; the rest follows at the next sync',
      );
    },
  );

  test(
    'a server that does not answer stops the run after three misses',
    () async {
      await rig();
      for (var i = 0; i < 6; i++) {
        await addWork('Book $i', 10 + i);
      }
      details.answer = false;
      final made = await keepWorkExtras(
        lib,
        covers,
        details,
        clock: () => clock,
      );
      expect(made, 3);
      expect(details.asked, hasLength(3));
    },
  );

  test('a work not yet on the server is not asked about', () async {
    await rig();
    await lib.addWork(const WorkDraft(title: 'Only here'));
    expect(await keepWorkExtras(lib, covers, details, clock: () => clock), 0);
  });
}
