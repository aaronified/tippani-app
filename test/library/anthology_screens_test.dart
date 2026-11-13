import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_widgets.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/screens/anthology_tools.dart';

import '../support/fake_anthologies.dart';
import '../support/fake_quiz.dart';

AnthologyEntry entry(
  int id,
  String quote, {
  String credit = '',
  String source = '',
  int workId = 0,
  String character = '',
}) => AnthologyEntry(
  kind: 'book',
  itemId: id,
  quote: quote,
  note: '',
  source: source,
  credit: credit,
  color: 'blue',
  language: '',
  locator: '',
  workId: workId,
  characterName: character,
);

class _Picker implements BackupPicker {
  final saved = <String>[];

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    saved.add(fileName);
    return true;
  }

  @override
  Future<PickedFile?> pick() async => null;
}

void main() {
  late FakeAnthologies service;
  late _Picker picker;
  final sent = <String>[];
  late Anthology a;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sent.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: AnthologyScreen(
          service: service,
          id: a.id,
          picker: picker,
          shareFile: (bytes, name) async => sent.add(name),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  setUp(() {
    service = FakeAnthologies();
    picker = _Picker();
    a = service.seed('Openings');
    service.put(a.id, entry(1, 'First one.', credit: 'Ann'));
    service.put(a.id, entry(2, 'Second one.', credit: 'Bob'));
  });

  testWidgets('a heading is added at the end, edited, moved and deleted', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'Add a heading');
    await tester.enterText(
      find.widgetWithText(TextField, 'Heading'),
      'Part one',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Part one'), findsOneWidget);
    expect(service.order(a.id), ['book/1', 'book/2', 'section/1']);

    // move it up past the second passage with its menu
    await tester.tap(find.byTooltip('More for this one').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(service.order(a.id), ['book/1', 'section/1', 'book/2']);

    await tester.tap(find.byTooltip('More for this one').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit heading'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Heading'), 'Part 1');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Part 1'), findsOneWidget);

    await tester.tap(find.byTooltip('More for this one').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete heading'));
    await tester.pumpAndSettle();
    expect(find.text('Part 1'), findsNothing);
    expect(service.order(a.id), ['book/1', 'book/2']);
  });

  testWidgets(
    'a passage moves down with its menu, and the order is the server\'s',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('More for this one').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(service.order(a.id), ['book/2', 'book/1']);
      expect(
        tester.getTopLeft(find.text('“Second one.”')).dy,
        lessThan(tester.getTopLeft(find.text('“First one.”')).dy),
      );
    },
  );

  testWidgets('a passage can be dragged into place', (tester) async {
    await open(tester);
    final handle = find.text('“First one.”');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      service.calls.any((c) => c.startsWith('move ${a.id} book/1')),
      isTrue,
    );
    expect(service.order(a.id), ['book/2', 'book/1']);
  });

  testWidgets('commentary is written for a passage and shown above it', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('More for this one').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commentary'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Read this first.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'note ${a.id} book/1 Read this first.');
    expect(find.text('Read this first.'), findsOneWidget);
  });

  testWidgets('what it shows can be switched, and the page follows', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('— Ann'), findsOneWidget);
    await choose(tester, 'What it shows…');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Who it is by'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.rowOf(a.id)['hide_credit'], true);
    expect(find.text('— Ann'), findsNothing);
  });

  testWidgets('grouping puts a heading over each run of the same book', (
    tester,
  ) async {
    service.put(a.id, entry(3, 'Third.', source: 'Walden', workId: 4));
    service.put(a.id, entry(4, 'Fourth.', source: 'Walden', workId: 4));
    await open(tester);
    expect(find.text('Walden'), findsNothing);
    await choose(tester, 'Group by…');
    await tester.tap(find.text('Book or film'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'group ${a.id} work');
    // one heading, over the two passages from the same book, though both show the book
    expect(find.text('Walden'), findsOneWidget);
  });

  testWidgets('a fill previews, then adds what the search found', (
    tester,
  ) async {
    service.fills['scope=all&favourite=yes'] = [
      entry(10, 'Loved one.'),
      entry(11, 'Loved two.'),
    ];
    await open(tester);
    await choose(tester, 'Fill from…');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fill now'))
          .onPressed,
      isNotNull,
      reason: '"everything" needs nothing more chosen',
    );
    await tester.tap(find.text('My favourites'));
    await tester.pump();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 passages match'), findsOneWidget);
    expect(service.order(a.id), [
      'book/1',
      'book/2',
    ], reason: 'a preview adds nothing');

    await tester.tap(find.text('Fill now'));
    await tester.pumpAndSettle();
    expect(service.order(a.id), ['book/1', 'book/2', 'book/10', 'book/11']);
    expect(find.text('Added 2 passages.'), findsOneWidget);
  });

  testWidgets('a source that needs a choice stays blocked until it is made', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'Fill from…');
    await tester.tap(find.text('A tag'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fill now'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a passage taken out can be put back from the list of those', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Remove from anthology').first);
    await tester.pumpAndSettle();
    expect(find.text('“First one.”'), findsNothing);
    await choose(tester, 'Taken out…');
    expect(find.text('“First one.”'), findsOneWidget);
    await tester.tap(find.text('Put back'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing was taken out of this anthology.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('“First one.”'), findsOneWidget);
  });

  testWidgets('export saves a file or sends it, as Markdown or an EPUB', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'Export…');
    await tester.tap(find.text('Save as Markdown'));
    await tester.pumpAndSettle();
    expect(picker.saved, ['Openings.md']);
    expect(find.text('Saved Openings.md.'), findsOneWidget);

    await choose(tester, 'Export…');
    await tester.tap(find.text('Send as EPUB book'));
    await tester.pumpAndSettle();
    expect(sent, ['Openings.epub']);
  });

  testWidgets('a quote in a list offers Add to anthology only where it can', (
    tester,
  ) async {
    final q = Quote(
      id: 1,
      workId: null,
      text: 'Simplify.',
      translation: '',
      language: '',
      speaker: '',
      chapter: '',
      location: '',
      note: '',
      color: 'blue',
      favorite: false,
      notedAt: DateTime.utc(2026),
      source: 'manual',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      tags: const [],
    );
    var added = 0;
    Widget tile({VoidCallback? add}) => MaterialApp(
      home: Scaffold(
        body: QuoteTile(
          quote: q,
          work: null,
          onTap: () {},
          onFavourite: () {},
          onAddToAnthology: add,
        ),
      ),
    );
    await tester.pumpWidget(tile());
    expect(find.byTooltip('Add to anthology'), findsNothing);
    await tester.pumpWidget(tile(add: () => added++));
    await tester.tap(find.byTooltip('More for this quote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to anthology'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Simplify.'));
    expect(added, 2, reason: 'the menu and a long press both do it');
  });

  testWidgets('Practise runs the quiz on this anthology only', (tester) async {
    final quiz = FakeQuiz();
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AnthologyScreen(service: service, id: a.id, quiz: quiz),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'Practise');
    await tester.pump();
    expect(quiz.practiceAnthologies, [a.id]);
  });

  testWidgets(
    'there is no Practise without the quiz, or with nothing to practise',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Practise'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      final empty = service.seed('Empty');
      await tester.pumpWidget(
        MaterialApp(
          home: AnthologyScreen(
            key: const ValueKey('another'),
            service: service,
            id: empty.id,
            quiz: FakeQuiz(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Practise'), findsNothing);
    },
  );

  testWidgets('the epigraph and dedication are kept', (tester) async {
    await open(tester);
    await choose(tester, 'Cover and front…');
    await tester.enterText(
      find.widgetWithText(TextField, 'Epigraph'),
      'Begin.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Dedication'),
      'For you',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.rowOf(a.id)['epigraph'], 'Begin.');
    expect(find.text('Begin.'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
  });

  testWidgets('a description written by hand shows on the book\'s page', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'Cover and front…');
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Sayings gathered over a decade.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      service.rowOf(a.id)['description'],
      'Sayings gathered over a decade.',
    );
    expect(find.text('Sayings gathered over a decade.'), findsOneWidget);
    // with no poster the page draws one from the title
    expect(find.byType(AnthologyPoster), findsOneWidget);
  });
}
