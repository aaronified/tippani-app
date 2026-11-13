import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/anthologies/anthologies.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/screens/quote_screen.dart';
import 'package:tippani/sync/fingerprint.dart';

import '../support/fake_anthologies.dart';
import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<PickedFile?> pick() async => null;
}

AnthologyEntry entry(
  String quote, {
  String credit = '',
  String source = '',
  String note = '',
}) => AnthologyEntry(
  kind: 'book',
  itemId: 1,
  quote: quote,
  note: note,
  source: source,
  credit: credit,
  color: 'blue',
  language: '',
  locator: 'p. 8',
);

void main() {
  test('the server\'s word for where a quote lives', () {
    expect(entryKindOf(Realm.book), 'book');
    expect(entryKindOf(Realm.screen), 'screen');
    expect(entryKindOf(Realm.loose), 'utterance');
  });

  test('an entry says who and where, leaving out what is empty', () {
    expect(
      entry('x', credit: 'Thoreau', source: 'Walden').from,
      'Thoreau, Walden, p. 8',
    );
    expect(entry('x').from, 'p. 8');
  });

  test(
    'the text of an anthology is its title, introduction, then each passage',
    () {
      final d = AnthologyDetail(
        Anthology.fromJson({
          'id': 1,
          'title': 'Openings',
          'intro': 'First lines.',
        }),
        [entry('Call me Ishmael.', credit: 'Melville', note: 'the best')],
      );
      expect(
        anthologyShareText(d),
        'Openings\n\nFirst lines.\n\n“Call me Ishmael.”\n— Melville, p. 8\nthe best',
      );
    },
  );

  group('the screens', () {
    late FakeAnthologies service;
    final shared = <String>[];

    Future<void> openList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      shared.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: AnthologiesScreen(
            service: service,
            share: (t, s) async => shared.add(t),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => service = FakeAnthologies());

    testWidgets(
      'lists anthologies with their sizes, and says when there are none',
      (tester) async {
        await openList(tester);
        expect(find.text('No anthologies yet.'), findsOneWidget);
        final a = service.seed('Openings');
        service.put(a.id, entry('one'));
        await tester.pumpWidget(const SizedBox());
        await openList(tester);
        expect(find.text('Openings'), findsOneWidget);
        expect(find.text('1 passage'), findsOneWidget);
      },
    );

    testWidgets(
      'a row carries the description, with the count on its own line',
      (tester) async {
        final a = service.seed('Openings');
        await service.setFront(a.id, '', '', description: 'Old sayings.');
        await openList(tester);
        expect(find.text('Old sayings.'), findsOneWidget);
        expect(find.text('0 passages'), findsOneWidget);
      },
    );

    testWidgets('a new anthology is made from a title and introduction', (
      tester,
    ) async {
      await openList(tester);
      await tester.tap(find.text('New anthology'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Openings',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.calls, ['create Openings']);
      expect(find.text('Openings'), findsOneWidget);
    });

    testWidgets(
      'a server that cannot be reached is said, with a way to try again',
      (tester) async {
        service.fail = const AnthologyException(
          'The server could not be reached.',
        );
        await openList(tester);
        expect(find.text('The server could not be reached.'), findsOneWidget);
        service.fail = null;
        service.seed('Back');
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Back'), findsOneWidget);
      },
    );

    testWidgets('opening one shows its passages; sharing sends the text', (
      tester,
    ) async {
      final a = service.seed('Openings', intro: 'First lines.');
      service.put(
        a.id,
        entry('Call me Ishmael.', credit: 'Melville', note: 'the best'),
      );
      await openList(tester);
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      expect(find.text('“Call me Ishmael.”'), findsOneWidget);
      expect(find.text('— Melville, p. 8'), findsOneWidget);
      expect(find.text('the best'), findsOneWidget);
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(shared.single, startsWith('Openings\n\nFirst lines.'));
    });

    testWidgets('a passage can be removed, and the list shows it gone', (
      tester,
    ) async {
      final a = service.seed('Openings');
      service.put(a.id, entry('Call me Ishmael.'));
      await openList(tester);
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from anthology'));
      await tester.pumpAndSettle();
      expect(service.calls, ['remove ${a.id} book 1']);
      expect(find.text('“Call me Ishmael.”'), findsNothing);
    });

    testWidgets('editing changes the title through the service', (
      tester,
    ) async {
      service.seed('Openings');
      await openList(tester);
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Closings',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.calls.last, 'edit 1 Closings');
      expect(find.text('Closings'), findsWidgets);
    });

    testWidgets('delete asks first, and then leaves the screen', (
      tester,
    ) async {
      service.seed('Openings');
      await openList(tester);
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(service.calls, ['delete 1']);
      expect(find.text('No anthologies yet.'), findsOneWidget);
    });
  });

  group('adding from a quote', () {
    late FakeAnthologies service;
    late MemoryLibrary lib;

    Future<void> open(
      WidgetTester tester, {
      bool synced = true,
      bool available = true,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      service = FakeAnthologies(available: available);
      lib = MemoryLibrary();
      final w = await lib.addWork(const WorkDraft(title: 'Walden'));
      final q = await lib.addQuote(QuoteDraft(text: 'Simplify.', workId: w.id));
      if (synced) await lib.setQuoteServerId(q.id, 42);
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteScreen(
            store: lib,
            quoteId: q.id,
            picker: _Picker(),
            anthologies: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the button is there only when paired and the quote is on the server',
      (tester) async {
        await open(tester, synced: false);
        expect(find.text('Add to anthology'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await open(tester, available: false);
        expect(find.text('Add to anthology'), findsNothing);
      },
    );

    testWidgets(
      'choosing an anthology adds the quote under its server id and kind',
      (tester) async {
        await open(tester);
        service.seed('Openings');
        await tester.tap(find.text('Add to anthology'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Openings'));
        await tester.pumpAndSettle();
        expect(service.calls, ['add 1 book 42']);
        expect(find.text('Added to Openings.'), findsOneWidget);
      },
    );

    testWidgets('a quote already in it says so', (tester) async {
      await open(tester);
      final a = service.seed('Openings');
      await service.add(a.id, 'book', 42);
      service.calls.clear();
      await tester.tap(find.text('Add to anthology'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Openings'));
      await tester.pumpAndSettle();
      expect(find.text('Already in Openings.'), findsOneWidget);
    });

    testWidgets('a new anthology can be made on the way', (tester) async {
      await open(tester);
      await tester.tap(find.text('Add to anthology'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A new anthology…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Fresh');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.calls, ['create Fresh', 'add 1 book 42']);
    });
  });
}
