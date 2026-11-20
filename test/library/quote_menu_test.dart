import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/board_screen.dart';
import 'package:tippani/screens/dashboard_screen.dart';
import 'package:tippani/screens/filtered_quotes_screen.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/search_screen.dart';
import 'package:tippani/screens/work_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/quote_context.dart';

import '../support/fake_anthologies.dart';
import '../support/fake_quiz.dart';
import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

/// A context source that has an answer for any quote.
class _Contexts implements QuoteContextSource {
  final asked = <int>[];
  @override
  Future<QuoteContext?> fetch(
    Quote quote,
    Work? work, {
    int? before,
    int? after,
  }) async {
    asked.add(quote.id);
    return null;
  }
}

/// What a person can press in a card's menu, by name. The card draws Favourite, Copy, Read aloud and Share as
/// buttons of its own, so the menu must hold everything else a quote can do and none of those four.
const _needed = ['Edit', 'Colour', 'Add a tag', 'Take a tag off', 'Delete'];
const _onTheCard = ['Copy', 'Read aloud', 'Share'];

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More for this quote').first);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  late MemoryLibrary lib;
  late Work walden;
  late Quote quote;

  setUp(() async {
    lib = MemoryLibrary();
    walden = await lib.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau'),
    );
    quote = await lib.addQuote(
      QuoteDraft(
        text: 'Simplify, simplify.',
        workId: walden.id,
        tags: const ['life'],
      ),
    );
  });

  Future<void> library(
    WidgetTester tester, {
    FakeAnthologies? anthologies,
    QuoteContextSource? contexts,
  }) async {
    await _tall(tester);
    Widget home = MaterialApp(
      home: LibraryScreen(
        store: lib,
        picker: _Picker(),
        anthologies: anthologies,
      ),
    );
    if (contexts != null) {
      home = ContextScope(source: contexts, child: home);
    }
    await tester.pumpWidget(home);
    await tester.pumpAndSettle();
  }

  group('the card menu holds what the card does not show', () {
    testWidgets(
      'on the library: every other action, and not the four buttons',
      (tester) async {
        await library(tester);
        for (final tip in ['Favourite', ..._onTheCard]) {
          expect(find.byTooltip(tip), findsWidgets, reason: '$tip is a button');
        }
        await _openMenu(tester);
        for (final label in [..._needed, 'Open the work']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        for (final label in [..._onTheCard, 'Favourite']) {
          expect(find.text(label), findsNothing, reason: '$label is a button');
        }
        // nothing that needs the server is offered with no server
        expect(find.text('Add to anthology'), findsNothing);
        expect(find.text('Show where it comes from'), findsNothing);
      },
    );

    testWidgets('a quote with no tags has no Take a tag off', (tester) async {
      await lib.updateQuote(quote.id, QuoteDraft(text: quote.text));
      await library(tester);
      await _openMenu(tester);
      expect(find.text('Add a tag'), findsOneWidget);
      expect(find.text('Take a tag off'), findsNothing);
    });

    testWidgets('the server actions come once the quote is on the server', (
      tester,
    ) async {
      await lib.setQuoteServerId(quote.id, 7);
      await library(
        tester,
        anthologies: FakeAnthologies(),
        contexts: _Contexts(),
      );
      await _openMenu(tester);
      expect(find.text('Add to anthology'), findsOneWidget);
      expect(find.text('Show where it comes from'), findsOneWidget);
    });

    testWidgets('a server that is not there takes them away again', (
      tester,
    ) async {
      await lib.setQuoteServerId(quote.id, 7);
      await library(tester, anthologies: FakeAnthologies(available: false));
      await _openMenu(tester);
      expect(find.text('Add to anthology'), findsNothing);
    });

    testWidgets('Show where it comes from asks for this quote', (tester) async {
      await lib.setQuoteServerId(quote.id, 7);
      final contexts = _Contexts();
      await library(tester, contexts: contexts);
      await _openMenu(tester);
      await _press(tester, 'Show where it comes from');
      expect(contexts.asked, [quote.id]);
    });

    testWidgets('on a work page: the same, without Open the work', (
      tester,
    ) async {
      await _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkScreen(store: lib, workId: walden.id, picker: _Picker()),
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester);
      for (final label in [..._needed, 'Open', 'Select']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Open the work'), findsNothing);
    });

    testWidgets('in a filtered list', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: FilteredQuotesScreen(
            store: lib,
            picker: _Picker(),
            title: 'life',
            tag: 'life',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester);
      for (final label in [..._needed, 'Open', 'Open the work']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('on a board', (tester) async {
      await _tall(tester);
      final board = await lib.addBoard('Proverbs');
      final loose = await lib.addQuote(
        const QuoteDraft(text: 'A stitch in time', tags: ['saying']),
      );
      await lib.setQuoteBoard(loose.id, board.id);
      await tester.pumpWidget(
        MaterialApp(
          home: BoardScreen(store: lib, boardId: board.id),
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester);
      for (final label in [..._needed, 'Open', 'Move to a board…']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Open the work'), findsNothing);
    });

    testWidgets('on Home', (tester) async {
      await _tall(tester);
      await lib.setFavorite(quote.id, true);
      SharedPreferences.setMockInitialValues({});
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              store: lib,
              quiz: FakeQuiz(),
              controller: controller,
              picker: _Picker(),
              random: math.Random(1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester);
      for (final label in [..._needed, 'Open', 'Open the work']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets(
      'on a search result, which draws no buttons, the menu holds all of it',
      (tester) async {
        await _tall(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: SearchScreen(store: lib, picker: _Picker()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'simplify');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await _openMenu(tester);
        for (final label in [
          ..._needed,
          'Open',
          'Favourite',
          'Copy',
          'Read aloud',
          'Share',
          'Open the work',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      },
    );
  });

  group('and each item does its job', () {
    testWidgets('Edit opens the quote to change', (tester) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Edit');
      expect(
        find.widgetWithText(TextField, 'The words'),
        findsOneWidget,
        reason: 'the quote form is open',
      );
      expect(find.text('Simplify, simplify.'), findsWidgets);
    });

    testWidgets('Delete asks, removes the quote and offers Undo', (
      tester,
    ) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Delete');
      expect(find.text('Delete this quote?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await lib.quote(quote.id), isNull);
      expect(find.text('Simplify, simplify.'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await lib.quotes()).single.text, 'Simplify, simplify.');
    });

    testWidgets('keeping it at the question leaves it there', (tester) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Delete');
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(await lib.quote(quote.id), isNotNull);
    });

    testWidgets('Colour sets the quote\'s colour', (tester) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Colour');
      await _press(tester, 'green');
      expect((await lib.quote(quote.id))!.color, 'green');
    });

    testWidgets('Add a tag tags it, and Take a tag off takes it away', (
      tester,
    ) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Add a tag');
      await tester.enterText(find.byType(TextField).last, 'stoic');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect((await lib.quote(quote.id))!.tags, contains('stoic'));

      await _openMenu(tester);
      await _press(tester, 'Take a tag off');
      await tester.tap(find.widgetWithText(ActionChip, 'life'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Take off'));
      await tester.pumpAndSettle();
      expect((await lib.quote(quote.id))!.tags, ['stoic']);
    });

    testWidgets('Move to a board files it', (tester) async {
      final board = await lib.addBoard('Proverbs');
      final loose = await lib.addQuote(const QuoteDraft(text: 'A stitch'));
      await library(tester);
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('A stitch'),
                matching: find.byType(Card),
              ),
              matching: find.byTooltip('More for this quote'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await _press(tester, 'Move to a board…');
      await _press(tester, 'Proverbs');
      expect((await lib.quote(loose.id))!.boardId, board.id);
    });

    testWidgets('Open the work goes to the work', (tester) async {
      await library(tester);
      await _openMenu(tester);
      await _press(tester, 'Open the work');
      // the work's own page has its Edit in the bar and its quotes beneath
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.text('Simplify, simplify.'), findsOneWidget);
    });

    testWidgets('Add to anthology opens the chooser for this quote', (
      tester,
    ) async {
      await lib.setQuoteServerId(quote.id, 7);
      final anthologies = FakeAnthologies();
      anthologies.seed('Openings');
      await library(tester, anthologies: anthologies);
      await _openMenu(tester);
      await _press(tester, 'Add to anthology');
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      expect(find.text('Added to Openings.'), findsOneWidget);
    });
  });
}
