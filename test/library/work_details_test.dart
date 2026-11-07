import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/work_details_section.dart';
import 'package:tippani/screens/work_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_details_source.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

Work work({
  int? serverId = 3,
  WorkKind kind = WorkKind.book,
  WorkDetails details = const WorkDetails(),
}) => Work(
  id: 1,
  kind: kind,
  title: 'Walden',
  creator: 'Thoreau',
  year: 1854,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  serverId: serverId,
  details: details,
);

void main() {
  group('the details record', () {
    test('reads the server\'s own record, leaving out what is not there', () {
      final d = WorkDetails.fromJson({
        'id': 1,
        'title': 'Walden',
        'description': ' A book about living simply. ',
        'genres': ['Essay', ' ', 'Nature', 5],
        'publisher': 'Ticknor',
        'pages': 352,
        'isbn': '9780142437681',
        'subtitle': '',
        'series': '',
      });
      expect(d.description, 'A book about living simply.');
      expect(d.genres, ['Essay', 'Nature']);
      expect(d.pages, 352);
      expect(d.subtitle, '');
      expect(d.cast, isEmpty);
      expect(d.isEmpty, isFalse);
    });

    test(
      'survives being written and read back, with its cast and its time',
      () {
        final at = DateTime.utc(2026, 11, 7, 9);
        final d = WorkDetails(
          description: 'D',
          genres: const ['G'],
          publisher: 'P',
          pages: 9,
          isbn: 'I',
          subtitle: 'S',
          series: 'Ser',
          cast: const [CastMember(character: 'Rick', actor: 'Bogart')],
          fetchedAt: at,
        );
        final back = WorkDetails.fromJson(d.toJson());
        expect(back.toJson(), d.toJson());
        expect(back.cast.single.actor, 'Bogart');
        expect(back.fetchedAt, at);
      },
    );

    test('anything else is an empty record, never an error', () {
      for (final junk in [
        null,
        5,
        'x',
        <Object?>[],
        {'genres': 'no', 'pages': 'many', 'cast': 7},
      ]) {
        expect(WorkDetails.fromJson(junk).isEmpty, isTrue, reason: '$junk');
      }
      expect(CastMember.fromJson({'character': '', 'actor': ''}), isNull);
    });
  });

  group('asking the server', () {
    late FakeServer server;
    late AppController controller;
    late PairedWorkDetails source;
    final now = DateTime.utc(2026, 11, 7, 12);

    Future<void> setUpRig({bool paired = true}) async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      server = FakeServer();
      controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        clientFactory: server.factory,
      );
      await controller.load();
      if (paired) await controller.pair('ABCD2345', 'My phone');
      source = PairedWorkDetails(controller, clock: () => now);
    }

    test(
      'a book: its record and its characters, stamped with the time',
      () async {
        await setUpRig();
        server.seed('/books', {
          'title': 'Walden',
          'description': 'About living simply.',
          'genres': ['Essay'],
          'pages': 352,
        }, id: 3);
        server.casts['/books/3'] = [
          {'character': 'Thoreau', 'actor': ''},
        ];

        final d = await source.fetch(work());

        expect(d!.description, 'About living simply.');
        expect(d.genres, ['Essay']);
        expect(d.cast.single.character, 'Thoreau');
        expect(d.fetchedAt, now);
      },
    );

    test('a film is asked of the movies route', () async {
      await setUpRig();
      server.seed('/movies', {
        'title': 'Casablanca',
        'description': 'A cafe.',
      }, id: 4);
      server.casts['/movies/4'] = [
        {'character': 'Rick', 'actor': 'Humphrey Bogart'},
      ];
      final d = await source.fetch(work(serverId: 4, kind: WorkKind.film));
      expect(server.castReads, ['/movies/4']);
      expect(d!.cast.single.actor, 'Humphrey Bogart');
    });

    test('if the cast cannot be had, the rest still counts and the cast held before is kept', () async {
      await setUpRig();
      server.seed('/books', {
        'title': 'Walden',
        'description': 'New text.',
      }, id: 3);
      server.failCastWith = 500;
      final held = work(
        details: const WorkDetails(
          cast: [CastMember(character: 'Old', actor: '')],
        ),
      );
      final d = await source.fetch(held);
      expect(d!.description, 'New text.');
      expect(d.cast.single.character, 'Old');
    });

    test(
      'a work that is not on the server, or no server paired, is nothing',
      () async {
        await setUpRig();
        expect(await source.fetch(work(serverId: null)), isNull);
        await setUpRig(paired: false);
        expect(await source.fetch(work()), isNull);
        expect(server.requests, isEmpty);
      },
    );

    test('a work the server no longer has is nothing', () async {
      await setUpRig();
      expect(await source.fetch(work()), isNull);
    });
  });

  group('on screen', () {
    const full = WorkDetails(
      description: 'About living simply.',
      genres: ['Essay', 'Nature'],
      publisher: 'Ticknor',
      pages: 352,
      isbn: '978',
      series: 'Classics',
      cast: [CastMember(character: 'Thoreau')],
    );

    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('shows every part there is', (tester) async {
      await tester.pumpWidget(
        host(WorkDetailsSection(work: work(details: full))),
      );
      expect(find.text('About living simply.'), findsOneWidget);
      expect(find.text('Essay'), findsOneWidget);
      expect(find.text('Publisher'), findsOneWidget);
      expect(find.text('Ticknor'), findsOneWidget);
      expect(find.text('352'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('Characters'), findsOneWidget);
      expect(find.text('Thoreau'), findsOneWidget);
    });

    testWidgets('a film has a Cast, with the actor and the part', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          WorkDetailsSection(
            work: work(
              kind: WorkKind.film,
              details: const WorkDetails(
                cast: [CastMember(character: 'Rick', actor: 'Humphrey Bogart')],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Cast'), findsOneWidget);
      expect(find.text('Humphrey Bogart as Rick'), findsOneWidget);
    });

    testWidgets('nothing to show draws nothing', (tester) async {
      await tester.pumpWidget(host(WorkDetailsSection(work: work())));
      expect(find.byType(Chip), findsNothing);
      expect(find.text('Cast'), findsNothing);
    });

    testWidgets('a long cast is cut, and Show all gives the rest', (
      tester,
    ) async {
      final cast = [
        for (var i = 0; i < 12; i++) CastMember(character: 'C$i', actor: 'A$i'),
      ];
      await tester.pumpWidget(
        host(
          WorkDetailsSection(
            work: work(
              kind: WorkKind.film,
              details: WorkDetails(cast: cast),
            ),
          ),
        ),
      );
      expect(find.text('A0 as C0'), findsOneWidget);
      expect(find.text('A11 as C11'), findsNothing);
      await tester.tap(find.text('Show all 12'));
      await tester.pump();
      expect(find.text('A11 as C11'), findsOneWidget);
    });

    testWidgets('a long description folds, and Show more opens it', (
      tester,
    ) async {
      final text = List.filled(60, 'word').join(' ');
      await tester.pumpWidget(
        host(
          WorkDetailsSection(
            work: work(details: WorkDetails(description: text)),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text(text)).maxLines, 6);
      await tester.tap(find.text('Show more'));
      await tester.pump();
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
    });
  });

  group('a work\'s page', () {
    late MemoryLibrary lib;
    late _Source source;
    late int id;

    Future<void> open(
      WidgetTester tester, {
      bool synced = true,
      WorkDetails? held,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      source = _Source();
      final w = await lib.addWork(const WorkDraft(title: 'Walden'));
      id = w.id;
      if (synced) await lib.setWorkServerId(w.id, 3);
      if (held != null) await lib.setWorkDetails(w.id, held);
      await tester.pumpWidget(
        DetailsScope(
          source: source,
          child: MaterialApp(
            home: WorkScreen(store: lib, workId: w.id, picker: _NoPicker()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'asks the server when it opens, shows the answer, and keeps it',
      (tester) async {
        await open(tester);
        expect(source.asked, 1);
        expect(find.text('Fetched description.'), findsOneWidget);
        expect(
          (await lib.work(id))!.details.description,
          'Fetched description.',
        );
      },
    );

    testWidgets('does not ask again while what it has is under a day old', (
      tester,
    ) async {
      await open(
        tester,
        held: WorkDetails(
          description: 'Kept.',
          fetchedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      expect(source.asked, 0);
      expect(find.text('Kept.'), findsOneWidget);
    });

    testWidgets('asks again when it is older, and replaces it', (tester) async {
      await open(
        tester,
        held: WorkDetails(
          description: 'Stale.',
          fetchedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      );
      expect(source.asked, 1);
      expect(find.text('Stale.'), findsNothing);
      expect(find.text('Fetched description.'), findsOneWidget);
    });

    testWidgets(
      'a server that does not answer leaves what was kept, and is not pestered',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        lib = MemoryLibrary();
        source = _Source()..answer = null;
        final w = await lib.addWork(const WorkDraft(title: 'Walden'));
        await lib.setWorkServerId(w.id, 3);
        await lib.setWorkDetails(
          w.id,
          const WorkDetails(description: 'Old but there.'),
        );
        await tester.pumpWidget(
          DetailsScope(
            source: source,
            child: MaterialApp(
              home: WorkScreen(store: lib, workId: w.id, picker: _NoPicker()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(source.asked, 1);
        expect(find.text('Old but there.'), findsOneWidget);
      },
    );

    testWidgets('a work that is not on the server is not asked about', (
      tester,
    ) async {
      await open(tester, synced: false);
      expect(source.asked, 0);
    });
  });
}

class _Source implements WorkDetailsSource {
  int asked = 0;
  WorkDetails? answer = const WorkDetails(description: 'Fetched description.');

  @override
  Future<WorkDetails?> fetch(Work work) async {
    asked++;
    return answer?.copyWith(fetchedAt: DateTime.now());
  }
}

class _NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}
