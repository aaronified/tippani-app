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

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class _NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

/// What a reader does to a work's cast on its own page: add a row, correct one, take one off (or only its
/// performer), and have the server fill the list from TheTVDB or IMDb. Every change is written to the server and
/// the page then shows what the server holds, so the web and the phone agree.
void main() {
  late FakeServer server;

  Future<void> open(
    WidgetTester tester, {
    WorkKind kind = WorkKind.film,
    bool synced = true,
    List<Map<String, Object?>> cast = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final isBook = kind == WorkKind.book;
    final route = isBook ? '/books' : '/movies';
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
      await c.pair('ABCD2345', 'My phone');
      return c;
    }))!;
    server.seed(route, {'title': 'Casablanca'}, id: 4);
    server.casts['$route/4'] = [...cast];
    final lib = MemoryLibrary();
    final w = await lib.addWork(WorkDraft(title: 'Casablanca', kind: kind));
    if (synced) await lib.setWorkServerId(w.id, 4);
    await tester.pumpWidget(
      DetailsScope(
        source: PairedWorkDetails(controller),
        child: WorkEditScope(
          service: PairedWorkEdit(controller),
          child: MaterialApp(
            home: WorkScreen(store: lib, workId: w.id, picker: _NoPicker()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressMenu(
    WidgetTester tester,
    String tooltip,
    String item,
  ) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String field, String text) async {
    await tester.enterText(find.widgetWithText(TextField, field), text);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  const rick = {'id': 50, 'character': 'Rick', 'actor': 'Humphrey Bogart'};

  testWidgets('adding a row writes it to the server and shows it', (
    tester,
  ) async {
    await open(tester);
    await pressMenu(tester, 'Cast actions', 'Add to the cast');
    await fill(tester, 'Character', 'Ilsa');
    await fill(tester, 'Actor', 'Ingrid Bergman');
    await press(tester, 'Save');
    expect(server.castWrites.single.call, 'POST /movies/4/cast');
    expect(server.castWrites.single.body, {
      'character': 'Ilsa',
      'actor': 'Ingrid Bergman',
    });
    expect(find.text('Ingrid Bergman as Ilsa'), findsOneWidget);
  });

  testWidgets('a row cannot be saved without a character', (tester) async {
    await open(tester);
    await pressMenu(tester, 'Cast actions', 'Add to the cast');
    await fill(tester, 'Actor', 'Ingrid Bergman');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(server.castWrites, isEmpty);
  });

  testWidgets('a book adds a character and has no actor to give', (
    tester,
  ) async {
    await open(tester, kind: WorkKind.book);
    await tester.tap(find.byTooltip('Cast actions'));
    await tester.pumpAndSettle();
    expect(find.text('Fetch cast from TheTVDB'), findsNothing);
    expect(find.text('Fetch cast from IMDb'), findsNothing);
    await tester.tap(find.text('Add a character'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Actor'), findsNothing);
    await fill(tester, 'Character', 'Ishmael');
    await press(tester, 'Save');
    expect(server.castWrites.single.call, 'POST /books/4/cast');
    expect(server.castWrites.single.body, {'character': 'Ishmael'});
    expect(find.text('Ishmael'), findsOneWidget);
  });

  testWidgets('editing a row sends both names and shows the change', (
    tester,
  ) async {
    await open(tester, cast: [rick]);
    expect(find.text('Humphrey Bogart as Rick'), findsOneWidget);
    await pressMenu(tester, 'Row actions', 'Edit');
    await fill(tester, 'Actor', 'Bogie');
    await press(tester, 'Save');
    expect(server.castWrites.single.call, 'PUT /cast/50');
    expect(server.castWrites.single.body, {
      'character': 'Rick',
      'actor': 'Bogie',
    });
    expect(find.text('Bogie as Rick'), findsOneWidget);
    expect(find.text('Humphrey Bogart as Rick'), findsNothing);
  });

  testWidgets('removing a row deletes it on the server', (tester) async {
    await open(tester, cast: [rick]);
    await pressMenu(tester, 'Row actions', 'Remove');
    expect(server.castWrites.single.call, 'DELETE /cast/50');
    expect(find.text('Humphrey Bogart as Rick'), findsNothing);
  });

  testWidgets('removing the performer only keeps the character', (
    tester,
  ) async {
    await open(tester, cast: [rick]);
    await pressMenu(tester, 'Row actions', 'Remove the performer only');
    expect(server.castWrites.single.call, 'DELETE /cast/50/actor');
    expect(find.text('Rick'), findsOneWidget);
    expect(find.textContaining('Bogart'), findsNothing);
  });

  testWidgets('Fetch cast from TheTVDB fills the list from the server', (
    tester,
  ) async {
    await open(tester);
    server.tvdbCast = [
      {'character': 'Rick', 'actor': 'Humphrey Bogart'},
    ];
    await pressMenu(tester, 'Cast actions', 'Fetch cast from TheTVDB');
    expect(server.castWrites.single.call, 'POST /movies/4/cast/tvdb');
    expect(find.text('Humphrey Bogart as Rick'), findsOneWidget);
  });

  testWidgets('a film with no TheTVDB id is told so in the server\'s words', (
    tester,
  ) async {
    await open(tester);
    server.tvdbPinned = false;
    await pressMenu(tester, 'Cast actions', 'Fetch cast from TheTVDB');
    expect(find.textContaining('has no TheTVDB id'), findsOneWidget);
  });

  testWidgets('Fetch cast from IMDb asks for the link and sends it', (
    tester,
  ) async {
    await open(tester);
    server.imdbCast = [
      {'character': 'Rick', 'actor': 'Humphrey Bogart'},
    ];
    await pressMenu(tester, 'Cast actions', 'Fetch cast from IMDb');
    await fill(
      tester,
      'IMDb title link or id (tt...)',
      'imdb.com/title/tt0034583/',
    );
    await press(tester, 'Fetch');
    expect(server.castWrites.single.call, 'POST /movies/4/cast/imdb');
    expect(server.castWrites.single.body, {
      'imdb': 'imdb.com/title/tt0034583/',
    });
    expect(find.text('Humphrey Bogart as Rick'), findsOneWidget);
  });

  testWidgets('a link the server cannot read is refused in its words', (
    tester,
  ) async {
    await open(tester);
    await pressMenu(tester, 'Cast actions', 'Fetch cast from IMDb');
    await fill(tester, 'IMDb title link or id (tt...)', 'nm0000000');
    await press(tester, 'Fetch');
    expect(find.textContaining('paste an IMDb title link'), findsOneWidget);
  });

  testWidgets('a work that is not on the server has no cast controls', (
    tester,
  ) async {
    await open(tester, synced: false);
    expect(find.byTooltip('Cast actions'), findsNothing);
  });
}
