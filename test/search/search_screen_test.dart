import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/quote_screen.dart';
import 'package:tippani/screens/search_screen.dart';
import 'package:tippani/search/search_models.dart';
import 'package:tippani/search/search_service.dart';

import '../support/fake_search.dart';
import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

const _server = SearchResults(
  fromServer: true,
  corrected: 'anarchic',
  works: [
    WorkHit(serverId: 3, title: 'The Dispossessed', creator: 'Ursula Le Guin'),
  ],
  people: [PersonGroup(name: 'Ursula Le Guin', role: 'author')],
  tags: [TagGroup(name: 'garden', count: 2)],
  quotes: [
    QuoteHit(
      serverId: 11,
      text: 'There is nothing so wholly anarchic as the unknown.',
      workTitle: 'The Dispossessed',
      speaker: 'Shevek',
    ),
  ],
);

Future<MemoryLibrary> _open(
  WidgetTester tester,
  ServerSearch? server, {
  Future<void> Function(MemoryLibrary lib)? seed,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lib = MemoryLibrary();
  if (seed != null) await seed(lib);
  await tester.pumpWidget(
    MaterialApp(
      home: SearchScreen(store: lib, picker: _Picker(), server: server),
    ),
  );
  await tester.pumpAndSettle();
  return lib;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks the server, says so, and shows every section', (
    tester,
  ) async {
    final server = FakeSearch(results: _server);
    await _open(tester, server);
    expect(find.text('Search your library'), findsOneWidget);
    expect(find.text('Searching your server · forgives typos'), findsOneWidget);

    await _type(tester, 'anarchy');
    expect(server.asked.last.words, 'anarchy');
    expect(server.asked.last.scope, SearchScope.all);
    expect(
      find.textContaining('Showing results for anarchic', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Titles'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Quotes'), findsWidgets);
    expect(find.text('The Dispossessed'), findsWidgets);
    expect(find.text('Ursula Le Guin'), findsWidgets);
    expect(find.text('#garden'), findsOneWidget);
  });

  testWidgets('a scope chip asks again with that scope', (tester) async {
    final server = FakeSearch(results: _server);
    await _open(tester, server);
    await _type(tester, 'anarchy');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Books'));
    await tester.pumpAndSettle();
    expect(server.asked.last.scope, SearchScope.books);
  });

  testWidgets('a filter chosen from a suggestion narrows the search', (
    tester,
  ) async {
    final server = FakeSearch(
      results: _server,
      vocab: const SearchVocabulary({
        'tag': ['garden', 'war'],
        'author': ['Voltaire'],
      }),
    );
    await _open(tester, server);
    await _type(tester, 'gar');
    await tester.tap(find.widgetWithText(ActionChip, 'Tag: garden'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Tag: garden'), findsOneWidget);
    expect(server.asked.last.facets, [const SearchFacet('tag', 'garden')]);
    expect(find.byType(TextField).first, findsOneWidget);

    // taking the chip off asks again without it
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(InputChip, 'Tag: garden'),
            matching: find.byType(Icon),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Tag: garden'), findsNothing);
  });

  testWidgets('a field typed in the box is a filter too', (tester) async {
    final server = FakeSearch(results: _server);
    await _open(tester, server);
    await _type(tester, 'anarchy author:"Le Guin"');
    expect(server.asked.last.words, 'anarchy');
    expect(server.asked.last.facets, [const SearchFacet('author', 'Le Guin')]);
  });

  testWidgets(
    'when the server cannot be reached the phone is searched, and it says so',
    (tester) async {
      final server = FakeSearch(results: _server)..fail = true;
      await _open(
        tester,
        server,
        seed: (lib) async {
          await lib.addQuote(const QuoteDraft(text: 'A local anarchic line'));
        },
      );
      await _type(tester, 'anarchic');
      expect(
        find.text(
          'The server could not be reached, so this searched the phone.',
        ),
        findsOneWidget,
      );
      expect(find.text('A local anarchic line'), findsOneWidget);
    },
  );

  testWidgets('with no server it searches the phone and says that', (
    tester,
  ) async {
    await _open(
      tester,
      FakeSearch(available: false),
      seed: (lib) async {
        await lib.addQuote(const QuoteDraft(text: 'Simplify, simplify.'));
      },
    );
    expect(
      find.textContaining('Searching this phone · exact words'),
      findsOneWidget,
    );
    await _type(tester, 'simplify');
    expect(find.text('Quotes'), findsWidgets);
    // the matched word is drawn marked
    final rich = tester.widgetList<RichText>(find.byType(RichText)).where((r) {
      final t = r.text.toPlainText();
      return t == 'Simplify, simplify.';
    });
    expect(rich, isNotEmpty);
  });

  testWidgets('nothing found says so', (tester) async {
    await _open(tester, FakeSearch(available: false));
    await _type(tester, 'zzzz');
    expect(find.text('Nothing matches.'), findsOneWidget);
  });

  testWidgets('a quote hit opens the quote that is on the phone', (
    tester,
  ) async {
    final server = FakeSearch(results: _server);
    late Quote local;
    await _open(
      tester,
      server,
      seed: (lib) async {
        final w = await lib.addWork(
          const WorkDraft(title: 'The Dispossessed', creator: 'Ursula Le Guin'),
        );
        local = await lib.addQuote(
          QuoteDraft(
            text: 'There is nothing so wholly anarchic as the unknown.',
            workId: w.id,
          ),
        );
        await lib.setQuoteServerId(local.id, 11);
      },
    );
    await _type(tester, 'anarchy');
    await tester.tap(
      find.textContaining('nothing so wholly anarchic', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuoteScreen), findsOneWidget);
  });

  testWidgets('a hit that is only on the server is read in a sheet', (
    tester,
  ) async {
    final server = FakeSearch(results: _server);
    await _open(tester, server);
    await _type(tester, 'anarchy');
    await tester.tap(
      find.textContaining('nothing so wholly anarchic', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuoteScreen), findsNothing);
    expect(
      find.text('On the server only. Sync to bring it here.'),
      findsOneWidget,
    );
  });
}
