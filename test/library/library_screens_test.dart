import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/memory_library.dart';

/// A library whose search for `alpha` does not answer until [gate] is completed, so a test can make an old
/// search finish after a newer one.
class SlowLibrary extends MemoryLibrary {
  final gate = Completer<void>();

  @override
  Future<List<Quote>> quotes({
    int? workId,
    String query = '',
    bool favouritesOnly = false,
    String? tag,
    int? boardId,
    bool unfiled = false,
    bool standalone = false,
    int limit = 200,
    int offset = 0,
  }) async {
    if (query == 'alpha') await gate.future;
    return super.quotes(
      workId: workId,
      query: query,
      favouritesOnly: favouritesOnly,
      tag: tag,
      boardId: boardId,
      unfiled: unfiled,
      standalone: standalone,
      limit: limit,
      offset: offset,
    );
  }
}

class FakePicker implements BackupPicker {
  final saved = <String, String>{};

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    saved[fileName] = utf8.decode(bytes);
    return true;
  }

  @override
  Future<PickedFile?> pick() async => null;
}

class FakeShares {
  final texts = <String>[];
  Future<void> call(String text, String subject) async => texts.add(text);
}

late MemoryLibrary lib;
late FakePicker picker;
late FakeShares shares;

/// Opens the library screen. [seed] fills the library first: the screen reads it once when it opens, so a
/// test that wants quotes already there must put them there before this.
Future<void> open(
  WidgetTester tester, {
  Future<void> Function(MemoryLibrary lib)? seed,
}) async {
  // Tall, so the whole of a form is built: a ListView builds only what is on screen.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  lib = MemoryLibrary();
  picker = FakePicker();
  shares = FakeShares();
  if (seed != null) await seed(lib);
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(store: lib, picker: picker, share: shares.call),
    ),
  );
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> addQuote(
  WidgetTester tester,
  String words, {
  String? speaker,
  String? tags,
}) async {
  await tapText(tester, 'Add a quote');
  await tester.enterText(field('The words'), words);
  if (speaker != null) await tester.enterText(field('Who said it'), speaker);
  if (tags != null) await tester.enterText(field('Tags'), tags);
  await tapText(tester, 'Save');
}

void main() {
  group('the library tab', () {
    testWidgets(
      'the app opens on the library, with the server a tab of its own',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        );
        final c = AppController(store);
        await tester.pumpWidget(
          TippaniApp(
            controller: c,
            harness: Harness.fake(
              store,
              controller: c,
              library: MemoryLibrary(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // the app opens on the Library: the books
        expect(find.text('No books yet.'), findsOneWidget);
        expect(
          find.text('Server'),
          findsNothing,
          reason: 'it is in Settings now',
        );
        await tapText(tester, 'Settings');
        expect(find.text('Connect to your server'), findsOneWidget);
      },
    );

    testWidgets('an empty library says so', (tester) async {
      await open(tester);
      expect(find.textContaining('No quotes yet'), findsOneWidget);
      expect(find.text('Quotes 0'), findsOneWidget);
    });
  });

  group('the Quotes section', () {
    testWidgets('is the quote board: only quotes with no work behind them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryLibrary();
      final book = await store.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      await store.addQuote(QuoteDraft(text: 'From a book', workId: book.id));
      await store.addQuote(const QuoteDraft(text: 'A proverb on the board'));
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            store: store,
            picker: FakePicker(),
            section: LibrarySection.quotes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A proverb on the board'), findsOneWidget);
      expect(find.text('From a book'), findsNothing);
    });
  });

  group('quotes', () {
    testWidgets('a quote is added, listed with who said it, and counted', (
      tester,
    ) async {
      await open(tester);
      await addQuote(
        tester,
        'I went to the woods',
        speaker: 'Thoreau',
        tags: 'nature, life',
      );
      expect(find.text('I went to the woods'), findsOneWidget);
      expect(find.text('Thoreau'), findsOneWidget);
      expect(find.text('#life'), findsOneWidget);
      expect(find.text('#nature'), findsOneWidget);
      expect(find.text('Quotes 1'), findsOneWidget);
      expect((await lib.quotes()).single.tags, ['life', 'nature']);
    });

    testWidgets(
      'a quote with no words is refused with a sentence, and nothing is saved',
      (tester) async {
        await open(tester);
        await addQuote(tester, '   ');
        expect(find.text('A quote needs its words.'), findsOneWidget);
        expect(await lib.quotes(), isEmpty);
      },
    );

    testWidgets('a quote can be given to a work made on the spot', (
      tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Add a quote');
      await tester.enterText(field('The words'), 'Call me Ishmael.');
      await tapText(tester, 'New work');
      await tester.enterText(field('Title'), 'Moby-Dick');
      await tester.enterText(field('Author'), 'Herman Melville');
      await tapText(tester, 'Save');
      await tapText(tester, 'Save');
      final q = (await lib.quotes()).single;
      expect((await lib.work(q.workId!))!.title, 'Moby-Dick');
      expect(find.text('Moby-Dick'), findsOneWidget);
    });

    testWidgets(
      'search narrows the list, says when nothing matches, and clears',
      (tester) async {
        await open(tester);
        await addQuote(tester, 'alpha words');
        await addQuote(tester, 'beta words');
        await tester.enterText(find.byType(TextField).first, 'alpha');
        await tester.pumpAndSettle();
        expect(find.text('alpha words'), findsOneWidget);
        expect(find.text('beta words'), findsNothing);
        await tester.enterText(find.byType(TextField).first, 'gamma');
        await tester.pumpAndSettle();
        expect(find.text('Nothing matches.'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('alpha words'), findsOneWidget);
        expect(find.text('beta words'), findsOneWidget);
      },
    );

    testWidgets(
      'a slow search that finishes late does not overwrite a newer one',
      (tester) async {
        final slow = SlowLibrary();
        await slow.addQuote(const QuoteDraft(text: 'alpha one'));
        await slow.addQuote(const QuoteDraft(text: 'beta one'));
        await tester.pumpWidget(
          MaterialApp(
            home: LibraryScreen(
              store: slow,
              picker: FakePicker(),
              share: FakeShares().call,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'alpha');
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'beta');
        await tester.pumpAndSettle();
        expect(find.text('beta one'), findsOneWidget);
        slow.gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('beta one'), findsOneWidget);
        expect(find.text('alpha one'), findsNothing);
      },
    );

    testWidgets(
      'the star favourites a quote, and Favourites keeps only those',
      (tester) async {
        await open(tester);
        await addQuote(tester, 'plain one');
        await addQuote(tester, 'loved one');
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(Card, 'loved one'),
            matching: find.byTooltip('Favourite'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          (await lib.quotes(favouritesOnly: true)).single.text,
          'loved one',
        );
        await tapText(tester, 'Favourites');
        expect(find.text('loved one'), findsOneWidget);
        expect(find.text('plain one'), findsNothing);
      },
    );

    testWidgets('the Tag chip filters by a tag picked from the ones in use', (
      tester,
    ) async {
      await open(tester);
      await addQuote(tester, 'about rivers', tags: 'water');
      await addQuote(tester, 'about hills', tags: 'land');
      await tapText(tester, 'Tag');
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('#water'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('about rivers'), findsOneWidget);
      expect(find.text('about hills'), findsNothing);
      expect(find.text('#water'), findsWidgets);
    });

    testWidgets('a quote is opened, changed and saved', (tester) async {
      await open(tester);
      await addQuote(tester, 'before');
      await tapText(tester, 'before');
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit quote'), findsOneWidget);
      await tester.enterText(field('The words'), 'after');
      await tester.tap(find.byKey(const ValueKey('colour-blue')));
      await tester.pump();
      await tapText(tester, 'Save');
      final q = (await lib.quotes()).single;
      expect(q.text, 'after');
      expect(q.color, 'blue');
      // saving returns to the quote's own screen, which shows it in quotation marks
      expect(find.text('“after”'), findsOneWidget);
    });

    testWidgets(
      'delete asks first; keeping it changes nothing, deleting removes it',
      (tester) async {
        await open(tester);
        await addQuote(tester, 'doomed');
        await tapText(tester, 'doomed');
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Keep it');
        expect(await lib.quotes(), hasLength(1));
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Delete');
        expect(await lib.quotes(), isEmpty);
        expect(find.textContaining('No quotes yet'), findsOneWidget);
      },
    );
  });

  group('works', () {
    testWidgets('a work is added, listed, and opened to its quotes', (
      tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Works 0');
      await tapText(tester, 'Add a work');
      await tester.enterText(field('Title'), 'Walden');
      await tester.enterText(field('Author'), 'Thoreau');
      await tester.enterText(field('Year'), '1854');
      await tapText(tester, 'Save');
      expect(find.text('Walden'), findsOneWidget);
      expect(find.text('Thoreau · 1854'), findsOneWidget);
      expect(find.text('BOOK'), findsOneWidget);
      await tapText(tester, 'Walden');
      expect(find.text('No quotes from this work yet.'), findsOneWidget);
      await tapText(tester, 'Add a quote');
      await tester.enterText(field('The words'), 'Simplify.');
      await tapText(tester, 'Save');
      expect(find.text('Simplify.'), findsOneWidget);
      expect((await lib.quotes()).single.workId, isNotNull);
    });

    testWidgets('a year that is not a number is refused', (tester) async {
      await open(tester);
      await tapText(tester, 'Works 0');
      await tapText(tester, 'Add a work');
      await tester.enterText(field('Title'), 'X');
      await tester.enterText(field('Year'), 'nineteen');
      await tapText(tester, 'Save');
      expect(find.text('The year must be a number.'), findsOneWidget);
      expect(await lib.works(), isEmpty);
    });

    testWidgets('the creator is called what the kind of work calls it', (
      tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Works 0');
      await tapText(tester, 'Add a work');
      expect(field('Author'), findsOneWidget);
      await tapText(tester, 'Film');
      expect(field('Director'), findsOneWidget);
      await tapText(tester, 'Game');
      expect(field('Studio'), findsOneWidget);
    });

    testWidgets(
      'deleting a work says how many quotes go with it, and takes them',
      (tester) async {
        await open(
          tester,
          seed: (lib) async {
            final w = await lib.addWork(const WorkDraft(title: 'Walden'));
            await lib.addQuote(QuoteDraft(text: 'one', workId: w.id));
            await lib.addQuote(QuoteDraft(text: 'two', workId: w.id));
            await lib.addQuote(const QuoteDraft(text: 'kept, it has no work'));
          },
        );
        await tapText(tester, 'Works 1');
        await tapText(tester, 'Walden');
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tapText(tester, 'Delete work');
        expect(
          find.textContaining('Its 2 quotes are deleted with it'),
          findsOneWidget,
        );
        await tapText(tester, 'Delete');
        expect(await lib.works(), isEmpty);
        expect((await lib.quotes()).single.text, 'kept, it has no work');
      },
    );
  });

  group('export', () {
    testWidgets('an empty library has nothing to share, and says so', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Share as Markdown');
      expect(find.text('There are no quotes to export yet.'), findsOneWidget);
      expect(shares.texts, isEmpty);
    });

    testWidgets('Share hands the Markdown to the share sheet', (tester) async {
      await open(
        tester,
        seed: (lib) async {
          final w = await lib.addWork(const WorkDraft(title: 'Walden'));
          await lib.addQuote(QuoteDraft(text: 'Simplify.', workId: w.id));
        },
      );
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Share as Markdown');
      expect(shares.texts.single, contains('title: Walden\ntype: book'));
      expect(shares.texts.single, contains('> Simplify.'));
    });

    testWidgets('Save writes tippani-library.md through the file picker', (
      tester,
    ) async {
      await open(
        tester,
        seed: (lib) => lib.addQuote(const QuoteDraft(text: 'A proverb.')),
      );
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save as Markdown file');
      expect(picker.saved.keys, ['tippani-library.md']);
      expect(picker.saved.values.single, contains('type: quotes'));
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets(
      'a work exports on its own, named for it, with only its quotes',
      (tester) async {
        await open(
          tester,
          seed: (lib) async {
            final w = await lib.addWork(const WorkDraft(title: 'A/B: C'));
            final other = await lib.addWork(const WorkDraft(title: 'Other'));
            await lib.addQuote(QuoteDraft(text: 'mine', workId: w.id));
            await lib.addQuote(QuoteDraft(text: 'not mine', workId: other.id));
          },
        );
        await tapText(tester, 'Works 2');
        await tapText(tester, 'A/B: C');
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tapText(tester, 'Save as Markdown file');
        expect(picker.saved.keys, ['tippani-A-B- C.md']);
        expect(picker.saved.values.single, contains('> mine'));
        expect(picker.saved.values.single, isNot(contains('not mine')));
      },
    );
  });
}
