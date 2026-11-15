import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/metadata/metadata_service.dart';
import 'package:tippani/screens/work_screen.dart';

import '../support/fake_metadata.dart';
import '../support/memory_library.dart';

class _NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

/// What a reader does on a work's page to bring its details up to date from the server's sources.
void main() {
  late FakeMetadata meta;
  late MemoryLibrary lib;

  Future<void> open(
    WidgetTester tester, {
    bool synced = true,
    WorkKind kind = WorkKind.book,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    meta = FakeMetadata();
    lib = MemoryLibrary();
    final w = await lib.addWork(WorkDraft(title: 'Walden', kind: kind));
    if (synced) await lib.setWorkServerId(w.id, 3);
    await tester.pumpWidget(
      MetadataScope(
        service: meta,
        child: MaterialApp(
          home: WorkScreen(store: lib, workId: w.id, picker: _NoPicker()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch metadata'));
    await tester.pumpAndSettle();
  }

  testWidgets('a work that is not on the server cannot be fetched', (
    tester,
  ) async {
    await open(tester, synced: false);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Fetch metadata'), findsNothing);
  });

  testWidgets('fetching shows what the sources say, and applying writes it', (
    tester,
  ) async {
    await open(tester);
    meta.checkResult = const [
      ReverifyItem(
        type: 'book',
        id: 3,
        title: 'Walden',
        status: 'ok',
        source: 'google',
        diffs: [
          FieldDiff(field: 'year', stored: '', fresh: 1854, source: 'google'),
        ],
      ),
    ];
    await choose(tester);
    expect(meta.calls, contains('check book3'));
    expect(find.text('Apply 1'), findsOneWidget);
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(meta.applied.single.id, 3);
    expect(meta.applied.single.set, {'year': 1854});
  });

  testWidgets('a work the sources agree with says so and opens nothing', (
    tester,
  ) async {
    await open(tester);
    meta.checkResult = const [
      ReverifyItem(type: 'book', id: 3, title: 'Walden', status: 'ok'),
    ];
    await choose(tester);
    expect(find.textContaining('nothing new'), findsOneWidget);
    expect(find.textContaining('Apply'), findsNothing);
  });

  testWidgets('a work with no source linked is told where to start', (
    tester,
  ) async {
    await open(tester);
    meta.checkResult = const [
      ReverifyItem(type: 'book', id: 3, title: 'Walden', status: 'unpinned'),
    ];
    await choose(tester);
    expect(find.textContaining('No source is linked'), findsOneWidget);
  });

  testWidgets('a server that refuses is said in its own words', (tester) async {
    await open(tester);
    meta.refuse = 'The server is busy.';
    await choose(tester);
    expect(find.text('The server is busy.'), findsOneWidget);
  });

  testWidgets('a work of the Other kind is checked among the books', (
    tester,
  ) async {
    await open(tester, kind: WorkKind.other);
    meta.checkResult = const [
      ReverifyItem(type: 'book', id: 3, title: 'Walden', status: 'ok'),
    ];
    await choose(tester);
    expect(meta.calls, contains('check book3'));
  });

  testWidgets('a film is checked among the films', (tester) async {
    await open(tester, kind: WorkKind.film);
    meta.checkResult = const [
      ReverifyItem(type: 'movie', id: 3, title: 'Walden', status: 'ok'),
    ];
    await choose(tester);
    expect(meta.calls, contains('check movie3'));
  });
}
