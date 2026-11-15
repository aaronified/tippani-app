import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/work_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_details_source.dart';
import 'package:tippani/tools/work_edit_service.dart';

import 'fake_server.dart';
import 'memory_library.dart';

class NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

/// A work's page against a fake server over HTTP, with the real services behind it: what the work edit tests
/// press is what a reader presses, and what they check is on the screen or on the wire.
class WorkPageRig {
  WorkPageRig(this.server, this.library, this.workId);
  final FakeServer server;
  final MemoryLibrary library;
  final int workId;

  /// The server's id for the work the page shows.
  static const serverId = 3;

  static Future<WorkPageRig> open(
    WidgetTester tester, {
    WorkKind kind = WorkKind.book,
    Map<String, Object?> record = const {},
    bool synced = true,
    bool paired = true,
    String cover = '',
    Widget Function(Widget page)? around,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final route = kind == WorkKind.book ? '/books' : '/movies';
    late FakeServer server;
    final controller = (await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      server = FakeServer();
      final c = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        clientFactory: server.factory,
      );
      await c.load();
      if (paired) await c.pair('ABCD2345', 'My phone');
      return c;
    }))!;
    server.seed(route, {'title': 'Walden', ...record}, id: serverId);
    final lib = MemoryLibrary();
    final w = await lib.addWork(WorkDraft(title: 'Walden', kind: kind));
    if (synced) await lib.setWorkServerId(w.id, serverId);
    if (cover.isNotEmpty) await lib.setWorkCover(w.id, cover);
    Widget page = MaterialApp(
      home: WorkScreen(store: lib, workId: w.id, picker: NoPicker()),
    );
    page = WorkEditScope(service: PairedWorkEdit(controller), child: page);
    page = DetailsScope(source: PairedWorkDetails(controller), child: page);
    if (around != null) page = around(page);
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();
    return WorkPageRig(server, lib, w.id);
  }

  /// Opens the work's menu and presses [item].
  static Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }
}
