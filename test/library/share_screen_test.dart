import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/share_format.dart';
import 'package:tippani/screens/share_screen.dart';

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

bool isPng(Uint8List b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4e &&
    b[3] == 0x47;

Quote q({
  String text = 'Simplify, simplify.',
  String translation = 'saral',
  String speaker = '',
  String chapter = 'Economy',
  String location = 'p. 8',
  String note = 'my margin',
  List<String> tags = const ['life', 'work'],
}) => Quote(
  id: 7,
  workId: 1,
  text: text,
  translation: translation,
  language: '',
  speaker: speaker,
  chapter: chapter,
  location: location,
  note: note,
  color: 'blue',
  favorite: false,
  notedAt: DateTime.utc(2026, 11, 6, 12),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: tags,
);

Work walden() => Work(
  id: 1,
  kind: WorkKind.book,
  title: 'Walden',
  creator: 'Thoreau',
  year: 1854,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('the parts of a share', () {
    test('only parts with something in them are listed, in reading order', () {
      final ids = shareFieldsOf(
        q(note: '', tags: const []),
        walden(),
      ).map((f) => f.id);
      expect(ids, [
        'quote',
        'translation',
        'author',
        'work',
        'year',
        'chapter',
        'location',
        'noted',
      ]);
    });

    test(
      'where in the work, the save date and the year start switched off',
      () {
        final on = shareDefaults(shareFieldsOf(q(), walden()));
        expect(
          on,
          containsAll([
            'quote',
            'translation',
            'author',
            'work',
            'chapter',
            'tags',
            'note',
          ]),
        );
        expect(on, isNot(contains('location')));
        expect(on, isNot(contains('noted')));
        expect(on, isNot(contains('year')));
      },
    );

    test('the credit is the switched-on parts of who and where', () {
      expect(
        shareCredit(q(speaker: 'Rick'), walden(), {
          'speaker',
          'author',
          'work',
        }),
        'Rick, Thoreau, Walden',
      );
      expect(
        shareCredit(q(), walden(), {'work', 'location', 'year'}),
        'Walden, 1854, p. 8',
      );
      expect(shareCredit(q(), walden(), {'quote'}), '');
    });
  });

  group('the text in each format', () {
    final on = shareDefaults(shareFieldsOf(q(), walden()));

    test('plain text has no marks', () {
      expect(
        buildShareText(q(), walden(), on, ShareFormat.plain),
        '“Simplify, simplify.”\n\nsaral\n\n— Thoreau, Walden, Economy\n\n#life #work\n\nNote: my margin',
      );
    });

    test(
      'Markdown quotes the words, and bolds the person and italicises the work',
      () {
        final t = buildShareText(q(), walden(), on, ShareFormat.markdown);
        expect(t, startsWith('> “Simplify, simplify.”\n\n> *saral*'));
        expect(t, contains('— **Thoreau**, *Walden*, Economy'));
      },
    );

    test('WhatsApp uses its own marks', () {
      final t = buildShareText(q(), walden(), on, ShareFormat.whatsapp);
      expect(t, contains('— *Thoreau*, _Walden_, Economy'));
      expect(t, startsWith('“Simplify, simplify.”'));
    });

    test('Reddit is Markdown', () {
      expect(
        buildShareText(q(), walden(), on, ShareFormat.reddit),
        buildShareText(q(), walden(), on, ShareFormat.markdown),
      );
    });

    test('a part switched off is left out, and so is a part switched on that is empty', () {
      final t = buildShareText(q(), walden(), {'quote'}, ShareFormat.plain);
      expect(t, '“Simplify, simplify.”');
      expect(
        buildShareText(q(note: ''), walden(), {'note'}, ShareFormat.plain),
        '',
      );
    });

    test('the date and place come out when asked for', () {
      final t = buildShareText(q(), walden(), {
        'quote',
        'noted',
        'location',
        'work',
      }, ShareFormat.plain);
      expect(t, contains('— Walden, p. 8'));
      expect(t, contains('Noted 2026-11-06'));
    });
  });

  group('the screen', () {
    late _Picker picker;
    final texts = <String>[];
    final images = <({Uint8List png, String name, String text})>[];
    final copied = <String>[];
    bool failImage = false;
    bool failCopy = false;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      picker = _Picker();
      texts.clear();
      images.clear();
      copied.clear();
      failImage = false;
      failCopy = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ShareScreen(
            quote: q(),
            work: walden(),
            share: (t, s) async => texts.add(t),
            shareImage: (png, name, text) async {
              if (failImage) throw Exception('no share sheet');
              images.add((png: png, name: name, text: text));
            },
            picker: picker,
            copy: (t) async {
              if (failCopy) throw Exception('no clipboard');
              copied.add(t);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

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

    testWidgets(
      'it opens on the picture, with the parts the web app starts with',
      (tester) async {
        await open(tester);
        expect(find.text('“Simplify, simplify.”'), findsOneWidget);
        expect(find.text('— Thoreau, Walden, Economy'), findsOneWidget);
        expect(find.text('my margin'), findsOneWidget);
        expect(find.text('#life #work'), findsOneWidget);
        expect(find.text('p. 8'), findsNothing);
      },
    );

    testWidgets(
      'switching a part off takes it off the picture; switching one on puts it there',
      (tester) async {
        await open(tester);
        await tester.tap(find.widgetWithText(FilterChip, 'Translation'));
        await tester.tap(find.widgetWithText(FilterChip, 'Location'));
        await tester.pumpAndSettle();
        expect(find.text('saral'), findsNothing);
        expect(find.text('— Thoreau, Walden, Economy, p. 8'), findsOneWidget);
      },
    );

    testWidgets(
      'sharing the picture sends a real PNG named for the quote, with the text beside it',
      (tester) async {
        await open(tester);
        await waitFor(
          tester,
          () => tester.tap(find.widgetWithText(FilledButton, 'Share')),
          () => images.isNotEmpty,
        );
        final sent = images.single;
        expect(isPng(sent.png), isTrue);
        expect(sent.name, 'tippani-quote-7.png');
        expect(sent.text, contains('Simplify, simplify.'));
        expect(sent.png.length, greaterThan(2000));
      },
    );

    testWidgets('light and dark both draw', (tester) async {
      await open(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () => tester.tap(find.widgetWithText(FilledButton, 'Share')),
        () => images.isNotEmpty,
      );
      expect(isPng(images.single.png), isTrue);
    });

    testWidgets('saving the picture writes a PNG where the reader chose', (
      tester,
    ) async {
      await open(tester);
      await waitFor(
        tester,
        () => tester.tap(find.text('Save picture')),
        () => picker.saved.isNotEmpty,
      );
      expect(isPng(picker.saved.values.single), isTrue);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('a cancelled save says nothing was saved', (tester) async {
      await open(tester);
      picker.accept = false;
      await waitFor(
        tester,
        () => tester.tap(find.text('Save picture')),
        () => find.text('Nothing was saved.').evaluate().isNotEmpty,
      );
      expect(find.text('Nothing was saved.'), findsOneWidget);
    });

    testWidgets('a share sheet that fails is said, not thrown', (tester) async {
      await open(tester);
      failImage = true;
      await waitFor(
        tester,
        () => tester.tap(find.widgetWithText(FilledButton, 'Share')),
        () =>
            find.text('The picture could not be shared.').evaluate().isNotEmpty,
      );
      expect(find.text('The picture could not be shared.'), findsOneWidget);
    });

    testWidgets(
      'a text format shows editable text instead of the picture, and Share sends what is edited',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Markdown'));
        await tester.pumpAndSettle();
        expect(find.text('Save picture'), findsNothing);
        final box = find.widgetWithText(
          TextField,
          '> “Simplify, simplify.”',
          skipOffstage: false,
        );
        expect(find.byType(TextField), findsOneWidget);
        expect(box, findsNothing);
        await tester.enterText(find.byType(TextField), 'edited by hand');
        await tester.tap(find.widgetWithText(FilledButton, 'Share'));
        await tester.pumpAndSettle();
        expect(texts.single, 'edited by hand');
      },
    );

    testWidgets('changing a part regenerates the text', (tester) async {
      await open(tester);
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'My note'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isNot(contains('Note:')));
      expect(field.controller!.text, contains('_Walden_'));
    });

    testWidgets(
      'Copy puts the text on the clipboard and says so; a failure is said',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Plain text'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(copied.single, startsWith('“Simplify, simplify.”'));
        expect(find.text('Copied.'), findsOneWidget);
      },
    );

    testWidgets('a clipboard that fails is said', (tester) async {
      await open(tester);
      failCopy = true;
      await tester.tap(find.text('Plain text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(find.text('The quote could not be copied.'), findsOneWidget);
    });
  });
}
