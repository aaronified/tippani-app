import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/quote_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/sync/fingerprint.dart';
import 'package:tippani/tools/quote_context.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

Map<String, Object?> answer({
  String before = 'Earlier paragraph.',
  String after = 'Later paragraph.',
  int shownBefore = 1,
  int shownAfter = 1,
  int storedBefore = 5,
  int storedAfter = 5,
  bool boundBefore = false,
  bool boundAfter = false,
  String unit = 'paragraph',
  String body = 'Simplify, simplify.',
}) => {
  'before': before,
  'body': body,
  'after': after,
  'unit': unit,
  'span': {'before': shownBefore, 'after': shownAfter},
  'stored': {'before': storedBefore, 'after': storedAfter},
  'bound_before': boundBefore,
  'bound_after': boundAfter,
  'from': 'default',
};

Quote quote({int? serverId = 7, int? workId}) => Quote(
  id: 1,
  workId: workId,
  text: 'Simplify, simplify.',
  translation: '',
  language: '',
  speaker: '',
  chapter: '',
  location: '',
  note: '',
  color: 'yellow',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
  serverId: serverId,
);

Work work(WorkKind kind) => Work(
  id: 1,
  kind: kind,
  title: 'Walden',
  creator: '',
  year: null,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}

void main() {
  group('reading the answer', () {
    test('the text on each side, the quote as the file has it, and how much more there is', () {
      final c = QuoteContext.fromJson(
        answer(storedBefore: 4, storedAfter: 1, shownAfter: 1),
      )!;
      expect(c.before, 'Earlier paragraph.');
      expect(c.body, 'Simplify, simplify.');
      expect(c.after, 'Later paragraph.');
      expect(c.canShowMoreBefore, isTrue);
      expect(c.canShowMoreAfter, isFalse);
      expect(c.unitWord, 'paragraph');
    });

    test('a film\'s context is lines', () {
      expect(QuoteContext.fromJson(answer(unit: 'cue'))!.unitWord, 'line');
    });

    test('anything that is not an answer is none, never an error', () {
      for (final junk in [
        null,
        5,
        'x',
        <Object?>[],
        <String, Object?>{},
        {'body': 5},
      ]) {
        expect(QuoteContext.fromJson(junk), isNull, reason: '$junk');
      }
    });

    test('the server\'s word for where a quote lives', () {
      expect(contextKindOf(Realm.book), 'annotation');
      expect(contextKindOf(Realm.screen), 'dialogue');
      expect(contextKindOf(Realm.loose), 'utterance');
    });
  });

  group('asking the server', () {
    late FakeServer server;
    late PairedQuoteContext source;
    late AppController controller;

    Future<void> rig({bool paired = true}) async {
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
      controller = c;
      source = PairedQuoteContext(c);
    }

    test('a book quote is asked of the annotation route', () async {
      await rig();
      server.contexts['annotation/7'] = answer();
      final c = await source.fetch(quote(), work(WorkKind.book));
      expect(server.contextReads, ['/quotes/annotation/7/context']);
      expect(c!.before, 'Earlier paragraph.');
    });

    test('a film quote and a standalone quote use their own routes', () async {
      await rig();
      server.contexts['dialogue/7'] = answer();
      server.contexts['utterance/7'] = answer();
      await source.fetch(quote(), work(WorkKind.film));
      await source.fetch(quote(), null);
      expect(server.contextReads, [
        '/quotes/dialogue/7/context',
        '/quotes/utterance/7/context',
      ]);
    });

    test('a wider window is asked for in the query', () async {
      await rig();
      server.contexts['annotation/7'] = answer();
      await source.fetch(quote(), work(WorkKind.book), before: 4, after: 2);
      expect(
        server.contextReads.single,
        '/quotes/annotation/7/context?before=4&after=2',
      );
    });

    test(
      'a quote the server has no context for is none, not an error',
      () async {
        await rig();
        expect(await source.fetch(quote(), work(WorkKind.book)), isNull);
      },
    );

    test('a quote that is not on the server is not asked about', () async {
      await rig();
      expect(await source.fetch(quote(serverId: null), null), isNull);
      expect(server.contextReads, isEmpty);
    });

    test('with no server a window never asked for is answered with the widest one kept', () async {
      await rig();
      server.contexts['annotation/7'] = answer(shownBefore: 2, shownAfter: 2);
      final seen = await source.fetch(
        quote(),
        work(WorkKind.book),
        before: 2,
        after: 2,
      );
      server.unreachable = true;
      final offline = await source.fetch(
        quote(),
        work(WorkKind.book),
        before: 6,
        after: 6,
      );
      expect(offline!.body, seen!.body);
      expect(offline.before, seen.before);
    });

    test(
      'with no server a quote never read is an error, not a blank',
      () async {
        await rig();
        server.unreachable = true;
        await expectLater(
          source.fetch(quote(), work(WorkKind.book)),
          throwsA(isA<ServerException>()),
        );
      },
    );

    test(
      'the favourites are kept after a sync, a few at a time, and only once',
      () async {
        await rig();
        final lib = MemoryLibrary();
        final w = await lib.addWork(
          const WorkDraft(kind: WorkKind.book, title: 'Walden'),
        );
        final fav = await lib.addQuote(
          QuoteDraft(text: 'Simplify.', workId: w.id, favorite: true),
        );
        await lib.setQuoteServerId(fav.id, 7);
        await lib.addQuote(QuoteDraft(text: 'Not a favourite.', workId: w.id));
        server.contexts['annotation/7'] = answer();

        expect(await keepFavouriteContexts(lib, source, controller.offline), 1);
        expect(server.contextReads, ['/quotes/annotation/7/context']);
        expect(
          await keepFavouriteContexts(lib, source, controller.offline),
          0,
          reason: 'already kept',
        );
        server.unreachable = true;
        final read = await source.fetch(
          (await lib.quote(fav.id))!,
          w,
          before: 3,
        );
        expect(read!.body, 'Simplify, simplify.');
      },
    );

    test('a server that errors is said, with the reason', () async {
      await rig();
      server.failContextWith = 500;
      await expectLater(
        source.fetch(quote(), work(WorkKind.book)),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('on the quote screen', () {
    late _Source source;

    Future<void> open(
      WidgetTester tester, {
      bool synced = true,
      bool withSource = true,
      List<CastMember> cast = const [],
      String chapter = '',
      String location = '',
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      source = _Source();
      final lib = MemoryLibrary();
      final w = await lib.addWork(const WorkDraft(title: 'Walden'));
      if (cast.isNotEmpty) {
        await lib.setWorkDetails(w.id, WorkDetails(cast: cast));
      }
      final q = await lib.addQuote(
        QuoteDraft(
          text: 'Simplify, simplify.',
          workId: w.id,
          chapter: chapter,
          location: location,
        ),
      );
      if (synced) await lib.setQuoteServerId(q.id, 7);
      await tester.pumpWidget(
        ContextScope(
          source: withSource ? source : null,
          child: MaterialApp(
            home: QuoteScreen(store: lib, quoteId: q.id, picker: _NoPicker()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openViewer(WidgetTester tester) async {
      await tester.tap(find.text('Show where it comes from'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a quote on the server offers its context, and asks nothing until pressed',
      (tester) async {
        await open(tester);
        expect(find.text('Context'), findsOneWidget);
        expect(source.asked, isEmpty);
        await openViewer(tester);
        expect(source.asked.first, (null, null));
        expect(find.text('Earlier paragraph.'), findsOneWidget);
        expect(find.text('Later paragraph.'), findsOneWidget);
        expect(find.textContaining('Your quote'), findsOneWidget);
      },
    );

    testWidgets(
      'a quote not on the server, or no source, shows no Context section',
      (tester) async {
        await open(tester, synced: false);
        expect(find.text('Context'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await open(tester, withSource: false);
        expect(find.text('Context'), findsNothing);
      },
    );

    testWidgets('reaching an edge asks for six more on that side', (
      tester,
    ) async {
      await open(tester);
      await openViewer(tester);
      // the text does not fill the screen, so both edges are in reach and each is asked for
      expect(source.asked, contains((7, 1)));
    });

    testWidgets('where the file ends, it says so and asks for no more', (
      tester,
    ) async {
      await open(tester);
      source.next = QuoteContext.fromJson(
        answer(
          storedBefore: 1,
          storedAfter: 1,
          boundBefore: true,
          boundAfter: true,
        ),
      );
      await openViewer(tester);
      expect(source.asked, hasLength(1));
      expect(find.text('The start of the chapter or scene.'), findsOneWidget);
      expect(
        find.text('The end of the chapter, scene or work.'),
        findsOneWidget,
      );
    });

    testWidgets('a quote the server has no context for says so', (
      tester,
    ) async {
      await open(tester);
      source.next = null;
      await openViewer(tester);
      expect(
        find.textContaining('has no context for this quote'),
        findsOneWidget,
      );
    });

    testWidgets('a server that cannot be reached is said, with Try again', (
      tester,
    ) async {
      await open(tester);
      source.fail = const ServerException('The server could not be reached.');
      await openViewer(tester);
      expect(find.text('The server could not be reached.'), findsOneWidget);
      source.fail = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier paragraph.'), findsOneWidget);
    });

    testWidgets(
      'a character of the work is picked out, listed above, and opens its sheet',
      (tester) async {
        await open(
          tester,
          cast: const [
            CastMember(character: 'Henry'),
            CastMember(character: 'Thoreau'),
          ],
        );
        source.next = QuoteContext.fromJson(
          answer(
            before: 'Henry spoke first.\nThen nobody did.',
            after: 'Later, Thoreau answered Henry.',
            storedBefore: 2,
            storedAfter: 1,
            shownBefore: 2,
          ),
        );
        await openViewer(tester);
        expect(find.text('In this passage'), findsOneWidget);
        await tester.tap(find.text('Thoreau').first);
        await tester.pumpAndSettle();
        expect(find.text('Open page'), findsOneWidget);
        expect(find.text('Show their quotes'), findsOneWidget);
        expect(find.text('No description yet.'), findsOneWidget);
        expect(find.textContaining('named once here'), findsOneWidget);
      },
    );

    testWidgets(
      'the chapter and page are a chip in the bar, with the detail a press away',
      (tester) async {
        await open(tester, chapter: 'Economy', location: 'p. 14');
        await openViewer(tester);
        expect(find.text('Economy · p. 14'), findsOneWidget);
        await tester.tap(find.byType(ActionChip));
        await tester.pumpAndSettle();
        expect(find.text('Where this is'), findsOneWidget);
        expect(find.text('Economy'), findsOneWidget);
        expect(find.text('p. 14'), findsOneWidget);
      },
    );

    testWidgets('a quote with no chapter or page has no place chip', (
      tester,
    ) async {
      await open(tester);
      await openViewer(tester);
      expect(find.byType(ActionChip), findsNothing);
    });
  });
}

class _Source implements QuoteContextSource {
  final asked = <(int?, int?)>[];
  ServerException? fail;

  /// When set (even to null), every answer is this; otherwise the answer is the window that was asked for.
  QuoteContext? _fixed;
  bool _useFixed = false;
  set next(QuoteContext? c) {
    _fixed = c;
    _useFixed = true;
  }

  @override
  Future<QuoteContext?> fetch(
    Quote quote,
    Work? work, {
    int? before,
    int? after,
  }) async {
    asked.add((before, after));
    final f = fail;
    if (f != null) throw f;
    if (_useFixed) return _fixed;
    return QuoteContext.fromJson(
      answer(shownBefore: before ?? 1, shownAfter: after ?? 1),
    );
  }
}
