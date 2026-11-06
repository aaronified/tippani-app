import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/quote_text.dart';
import 'package:tippani/screens/quote_screen.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  final saved = <String, Uint8List>{};
  bool accept = true;
  bool fail = false;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (fail) throw Exception('disk full');
    if (accept) saved[fileName] = bytes;
    return accept;
  }

  @override
  Future<PickedFile?> pick() async => null;
}

class _Out {
  final texts = <String>[];
  final images = <({Uint8List png, String name, String text})>[];
  bool failImage = false;

  Future<void> text(String t, String subject) async => texts.add(t);

  Future<void> image(Uint8List png, String name, String text) async {
    if (failImage) throw Exception('no share sheet');
    images.add((png: png, name: name, text: text));
  }
}

bool isPng(Uint8List b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4e &&
    b[3] == 0x47;

Quote q({
  String text = 'Simplify, simplify.',
  String translation = '',
  String speaker = '',
  String chapter = '',
  String location = '',
}) => Quote(
  id: 1,
  workId: null,
  text: text,
  translation: translation,
  language: '',
  speaker: speaker,
  chapter: chapter,
  location: location,
  note: '',
  color: 'yellow',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

Work walden() => Work(
  id: 1,
  kind: WorkKind.book,
  title: 'Walden',
  creator: 'Henry David Thoreau',
  year: 1854,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('the words that go with a quote', () {
    test('attribution joins what is there and leaves out what is not', () {
      expect(
        quoteAttribution(
          q(speaker: 'Thoreau', chapter: 'Economy', location: 'p. 8'),
          walden(),
        ),
        'Thoreau, Walden (Henry David Thoreau), Economy, p. 8',
      );
      expect(quoteAttribution(q(), null), '');
      expect(quoteAttribution(q(speaker: ' A '), null), 'A');
      final noCreator = Work(
        id: 1,
        kind: WorkKind.book,
        title: 'Anon',
        creator: '',
        year: null,
        language: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(quoteAttribution(q(), noCreator), 'Anon');
    });

    test(
      'share text is the words in quotes, the translation, then the source',
      () {
        expect(
          quoteShareText(q(translation: 'saral', speaker: 'Thoreau'), null),
          '“Simplify, simplify.”\nsaral\n— Thoreau',
        );
        expect(quoteShareText(q(), null), '“Simplify, simplify.”');
      },
    );
  });

  group('the screen', () {
    late MemoryLibrary lib;
    late _Picker picker;
    late _Out out;
    late Work work;
    late Quote quote;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lib = MemoryLibrary();
      picker = _Picker();
      out = _Out();
      work = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau', year: 1854),
      );
      quote = await lib.addQuote(
        QuoteDraft(
          text: 'Simplify, simplify.',
          workId: work.id,
          translation: 'saral',
          speaker: 'Thoreau',
          chapter: 'Economy',
          location: 'p. 8',
          note: 'my margin',
          tags: const ['life'],
          color: 'blue',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteScreen(
            store: lib,
            quoteId: quote.id,
            picker: picker,
            share: out.text,
            shareImage: out.image,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A message shown while a picture is being drawn gets a real-time timer (the drawing runs outside the
      // test's clock). Taking the screen down at the end cancels it, so it cannot fire into the next test.
      addTearDown(() => tester.pumpWidget(const SizedBox()));
    }

    /// Runs [press] and waits (in real time, because drawing a picture is not driven by the test's clock)
    /// until [done] is true.
    Future<void> waitFor(
      WidgetTester tester,
      Future<void> Function() press,
      bool Function() done,
    ) async {
      await tester.runAsync(() async {
        await press();
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('it shows the quote as a card with its note, tags and work', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('“Simplify, simplify.”'), findsOneWidget);
      expect(find.text('saral'), findsOneWidget);
      expect(
        find.text('— Thoreau, Walden (Thoreau), Economy, p. 8'),
        findsOneWidget,
      );
      expect(find.text('my margin'), findsOneWidget);
      expect(find.text('#life'), findsOneWidget);
      expect(find.text('Walden'), findsOneWidget);
      expect(find.text('Noted 2026-11-06'), findsOneWidget);
    });

    testWidgets('favouriting toggles the star and keeps it', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Favourite'));
      await tester.pumpAndSettle();
      expect((await lib.quote(quote.id))!.favorite, isTrue);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
    });

    testWidgets('share text sends the words, the translation and the source', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Share text'));
      await tester.pumpAndSettle();
      expect(
        out.texts.single,
        startsWith('“Simplify, simplify.”\nsaral\n— Thoreau'),
      );
    });

    testWidgets(
      'share picture sends a real PNG named for the quote, with the text beside it',
      (tester) async {
        await open(tester);
        await waitFor(
          tester,
          () => tester.tap(find.text('Share picture')),
          () => out.images.isNotEmpty,
        );
        final sent = out.images.single;
        expect(isPng(sent.png), isTrue);
        expect(sent.name, 'tippani-quote-${quote.id}.png');
        expect(sent.text, contains('Simplify, simplify.'));
        expect(sent.png.length, greaterThan(2000));
      },
    );

    testWidgets(
      'save picture writes the same kind of PNG where the reader chose',
      (tester) async {
        await open(tester);
        await waitFor(
          tester,
          () => tester.tap(find.text('Save picture')),
          () => picker.saved.isNotEmpty,
        );
        expect(picker.saved.keys.single, 'tippani-quote-${quote.id}.png');
        expect(isPng(picker.saved.values.single), isTrue);
        expect(find.text('Saved.'), findsOneWidget);
      },
    );

    testWidgets('a cancelled save says nothing was saved', (tester) async {
      await open(tester);
      picker.accept = false;
      await waitFor(
        tester,
        () => tester.tap(find.text('Save picture')),
        () => find.text('Nothing was saved.').evaluate().isNotEmpty,
      );
      expect(find.text('Nothing was saved.'), findsOneWidget);
      expect(picker.saved, isEmpty);
    });

    testWidgets('a save that fails says it could not be saved', (tester) async {
      await open(tester);
      picker.fail = true;
      await waitFor(
        tester,
        () => tester.tap(find.text('Save picture')),
        () =>
            find.text('The picture could not be saved.').evaluate().isNotEmpty,
      );
      expect(find.text('The picture could not be saved.'), findsOneWidget);
    });

    testWidgets('a share sheet that fails is said, not thrown', (tester) async {
      await open(tester);
      out.failImage = true;
      await waitFor(
        tester,
        () => tester.tap(find.text('Share picture')),
        () =>
            find.text('The picture could not be shared.').evaluate().isNotEmpty,
      );
      expect(find.text('The picture could not be shared.'), findsOneWidget);
    });

    testWidgets(
      'delete asks first; keeping it changes nothing, deleting closes the screen',
      (tester) async {
        await open(tester);
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep it'));
        await tester.pumpAndSettle();
        expect(await lib.quote(quote.id), isNotNull);
        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(await lib.quote(quote.id), isNull);
      },
    );

    testWidgets('edit opens the form, and the screen shows what was saved', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'The words'),
        'Simplify.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('“Simplify.”'), findsOneWidget);
    });

    testWidgets('a quote deleted from its editor takes the screen with it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryLibrary();
      final gone = await store.addQuote(const QuoteDraft(text: 'soon gone'));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => QuoteScreen(
                      store: store,
                      quoteId: gone.id,
                      picker: _Picker(),
                    ),
                  ),
                ),
                child: const Text('open it'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open it'));
      await tester.pumpAndSettle();
      expect(find.text('“soon gone”'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await store.quote(gone.id), isNull);
      expect(find.byType(QuoteScreen), findsNothing);
      expect(find.text('open it'), findsOneWidget);
    });

    testWidgets('the work row opens the work', (tester) async {
      await open(tester);
      await tester.tap(find.text('Walden'));
      await tester.pumpAndSettle();
      expect(find.text('Add a quote'), findsOneWidget);
    });
  });
}
