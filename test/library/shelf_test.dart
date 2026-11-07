import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/shelf_card.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_details_source.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

Work _work({
  WorkKind kind = WorkKind.book,
  int? serverId = 3,
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

/// A source that answers like the server: it moves the status and keeps a read log.
class _Shelf implements WorkDetailsSource {
  final puts = <(String, int)>[];
  String? refuse;

  @override
  Future<WorkDetails?> fetch(Work work) async => null;

  @override
  Future<WorkDetails?> setStatus(
    Work work,
    String status, {
    int progress = 0,
  }) async {
    if (refuse != null) throw ServerException(refuse!);
    puts.add((status, progress));
    return work.details.copyWith(
      status: status,
      progress: progress,
      reads: [
        ...work.details.reads,
        if (status == 'completed')
          const ReadEntry(
            startedAt: '2026-11-01',
            finishedAt: '2026-11-07',
            outcome: 'finished',
          ),
      ],
    );
  }
}

void main() {
  group('the shelf record', () {
    test('reads the status, the progress and the read log', () {
      final d = WorkDetails.fromJson({
        'status': 'reading',
        'progress': 140,
        'reads': [
          {
            'started_at': '2026-01',
            'finished_at': '2026-03',
            'outcome': 'finished',
          },
          {'started_at': '2026-11-01', 'finished_at': '', 'outcome': 'open'},
          7,
        ],
      });
      expect(d.status, 'reading');
      expect(d.progress, 100, reason: 'kept between 0 and 100');
      expect(d.reads, hasLength(2));
      expect(d.timesFinished, 1);
      expect(WorkDetails.fromJson(d.toJson()).toJson(), d.toJson());
    });

    test('the in-progress word is the server\'s for each kind', () {
      expect(activeStatusOf(WorkKind.book), 'reading');
      expect(activeStatusOf(WorkKind.film), 'watching');
      expect(activeStatusOf(WorkKind.show), 'watching');
      expect(activeStatusOf(WorkKind.game), 'playing');
    });
  });

  group('the server', () {
    late FakeServer server;
    late PairedWorkDetails source;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      server = FakeServer();
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        clientFactory: server.factory,
      );
      await controller.load();
      await controller.pair('ABCD2345', 'My phone');
      source = PairedWorkDetails(controller);
      server.seed('/books', {'title': 'Walden', 'status': ''}, id: 3);
    });

    test(
      'a status is sent to the work\'s own route, and the answer kept',
      () async {
        final d = await source.setStatus(_work(), 'reading', progress: 30);
        expect(server.statusWrites.single, {
          'route': '/books',
          'id': 3,
          'status': 'reading',
          'progress': 30,
        });
        expect(d!.status, 'reading');
        expect(d.progress, 30);
      },
    );

    test('finishing adds a finished read', () async {
      final d = await source.setStatus(_work(), 'completed', progress: 100);
      expect(d!.timesFinished, 1);
    });

    test('a refusal arrives in the server\'s words', () async {
      await source.setStatus(_work(), 'completed', progress: 100);
      await expectLater(
        source.setStatus(_work(), 'paused'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('can only be started again'),
          ),
        ),
      );
    });

    test('a work the server does not have is not asked', () async {
      expect(await source.setStatus(_work(serverId: null), 'reading'), isNull);
      expect(server.statusWrites, isEmpty);
    });
  });

  group('the card', () {
    late MemoryLibrary lib;
    late _Shelf shelf;
    late Work work;
    var changed = 0;

    Future<void> open(
      WidgetTester tester, {
      Work? w,
      bool paired = true,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      shelf = _Shelf();
      changed = 0;
      work = w ?? _work();
      await tester.pumpWidget(
        MaterialApp(
          home: DetailsScope(
            source: paired ? shelf : null,
            child: Scaffold(
              body: ShelfCard(
                work: work,
                store: lib,
                onChanged: () => changed++,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('offers the book\'s own words, and sends the one pressed', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Watching'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('shelf-reading')));
      await tester.pumpAndSettle();
      expect(shelf.puts.single.$1, 'reading');
      expect(changed, 1);
    });

    testWidgets('a film says Watching, a game Playing', (tester) async {
      await open(tester, w: _work(kind: WorkKind.film));
      expect(find.text('Watching'), findsOneWidget);
      await open(tester, w: _work(kind: WorkKind.game));
      expect(find.text('Playing'), findsOneWidget);
    });

    testWidgets(
      'a work in progress shows its bar, and moving it sends the number',
      (tester) async {
        await open(
          tester,
          w: _work(details: const WorkDetails(status: 'reading', progress: 40)),
        );
        expect(find.text('40%'), findsOneWidget);
        await tester.drag(find.byType(Slider), const Offset(120, 0));
        await tester.pumpAndSettle();
        expect(shelf.puts.single.$1, 'reading');
        expect(shelf.puts.single.$2, greaterThan(40));
      },
    );

    testWidgets('finished shows how many times', (tester) async {
      await open(
        tester,
        w: _work(
          details: const WorkDetails(
            status: 'completed',
            progress: 100,
            reads: [
              ReadEntry(
                startedAt: '2025',
                finishedAt: '2025',
                outcome: 'finished',
              ),
              ReadEntry(
                startedAt: '2026',
                finishedAt: '2026',
                outcome: 'finished',
              ),
            ],
          ),
        ),
      );
      expect(find.text('Finished 2 times.'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a refusal is shown in the server\'s words', (tester) async {
      await open(tester);
      shelf.refuse = 'a completed book can only be started again';
      await tester.tap(find.byKey(const ValueKey('shelf-paused')));
      await tester.pumpAndSettle();
      expect(
        find.text('a completed book can only be started again'),
        findsOneWidget,
      );
      expect(changed, 0);
    });

    testWidgets(
      'with no server the card reads and explains, and does not send',
      (tester) async {
        await open(tester, paired: false);
        await tester.tap(find.byKey(const ValueKey('shelf-reading')));
        await tester.pumpAndSettle();
        expect(shelf.puts, isEmpty);
        expect(find.textContaining('kept on your server'), findsOneWidget);
      },
    );
  });
}
