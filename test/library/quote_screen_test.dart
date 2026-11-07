import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets('one Share button opens the share screen for this quote', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Share text'), findsNothing);
      expect(find.text('Share picture'), findsNothing);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Include'), findsOneWidget);
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

    testWidgets('copy puts the words and the credit on the clipboard', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester);
      await tester.tap(find.byTooltip('Copy'));
      await tester.pumpAndSettle();
      expect(copied, contains('Simplify, simplify.'));
      expect(copied, contains('Thoreau'));
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a deleted quote comes back with Undo, with all it had', (
      tester,
    ) async {
      await open(tester);
      // opened from a page that stays behind it, as in the app: the message is shown on that page
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => QuoteScreen(
                      store: lib,
                      quoteId: quote.id,
                      picker: picker,
                      share: out.text,
                      shareImage: out.image,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await lib.quotes(), isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final back = (await lib.quotes()).single;
      expect(back.text, 'Simplify, simplify.');
      expect(back.workId, work.id);
      expect(back.note, 'my margin');
      expect(back.tags, ['life']);
      expect(back.color, 'blue');
    });

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
