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
}) => {
  'before': before,
  'body': 'Simplify, simplify.',
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
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      source = _Source();
      final lib = MemoryLibrary();
      final w = await lib.addWork(const WorkDraft(title: 'Walden'));
      final q = await lib.addQuote(
        QuoteDraft(text: 'Simplify, simplify.', workId: w.id),
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

    testWidgets(
      'a quote on the server offers its context, and asks nothing until pressed',
      (tester) async {
        await open(tester);
        expect(find.text('Context'), findsOneWidget);
        expect(source.asked, isEmpty);
        await tester.tap(find.text('Show where it comes from'));
        await tester.pumpAndSettle();
        expect(source.asked, [(null, null)]);
        expect(find.text('Earlier paragraph.'), findsOneWidget);
        expect(find.text('Later paragraph.'), findsOneWidget);
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

    testWidgets('Show more widens one side by three, keeping the other', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Show where it comes from'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more before'));
      await tester.pumpAndSettle();
      expect(source.asked.last, (4, 1));
      await tester.tap(find.text('Show more after'));
      await tester.pumpAndSettle();
      expect(source.asked.last, (4, 4));
    });

    testWidgets('where the file ends, it says so and offers no more', (
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
      await tester.tap(find.text('Show where it comes from'));
      await tester.pumpAndSettle();
      expect(find.text('Show more before'), findsNothing);
      expect(find.text('Show more after'), findsNothing);
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
      await tester.tap(find.text('Show where it comes from'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Show where it comes from'));
      await tester.pumpAndSettle();
      expect(find.text('The server could not be reached.'), findsOneWidget);
      source.fail = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier paragraph.'), findsOneWidget);
    });
  });
}

class _Source implements QuoteContextSource {
  final asked = <(int?, int?)>[];
  ServerException? fail;
  QuoteContext? next = QuoteContext.fromJson(answer());

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
    return next;
  }
}
