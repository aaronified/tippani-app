import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';

import '../support/work_page_rig.dart';

/// What a reader does to a work's details on its page: open Edit details, change what the form offers, save. The
/// server replaces the whole record on a save, so what the form does not show has to survive it.
void main() {
  const book = {
    'author': 'Henry David Thoreau',
    'translator': 'A. Translator',
    'description': 'Old words.',
    'genres': ['Essay'],
    'series': '',
    'series_index': 0,
    'publisher': 'Ticknor',
    'pages': 352,
    'isbn': '9780142437681',
    'links': 'https://example.org/walden',
    'cover_path': 'abc.png',
  };

  Future<void> fill(WidgetTester tester, String field, String text) async {
    await tester.enterText(find.widgetWithText(TextField, field), text);
    await tester.pump();
  }

  testWidgets('a book\'s details are changed, saved on the server, and shown', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, record: book);
    await WorkPageRig.menu(tester, 'Edit details');
    // the form opens on what the server holds, links included
    expect(find.text('Old words.'), findsOneWidget);
    expect(find.text('https://example.org/walden'), findsOneWidget);
    await fill(tester, 'Description', 'New words.');
    await fill(tester, 'Genres', 'Essay, Nature');
    await fill(tester, 'Series', 'Walden cycle');
    await fill(tester, 'Series #', '2');
    await fill(tester, 'Pages', '360');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = rig.server.updated.last;
    expect(sent.path, '/books/3');
    expect(sent.body['description'], 'New words.');
    expect(sent.body['genres'], ['Essay', 'Nature']);
    expect(sent.body['series'], 'Walden cycle');
    expect(sent.body['series_index'], 2);
    expect(sent.body['pages'], 360);
    // what the form never showed is sent back as it was
    expect(sent.body['translator'], 'A. Translator');
    expect(sent.body['cover_path'], 'abc.png');
    expect(sent.body['isbn'], '9780142437681');
    // the page shows what the server now holds
    expect(find.text('New words.'), findsOneWidget);
    expect(find.text('Nature'), findsOneWidget);
    expect(find.text('Walden cycle'), findsOneWidget);
  });

  testWidgets('a film is not asked for pages or an ISBN', (tester) async {
    final rig = await WorkPageRig.open(
      tester,
      kind: WorkKind.film,
      record: {'director': 'Someone', 'description': 'A film.'},
    );
    await WorkPageRig.menu(tester, 'Edit details');
    expect(find.widgetWithText(TextField, 'Pages'), findsNothing);
    expect(find.widgetWithText(TextField, 'ISBN'), findsNothing);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    await fill(tester, 'Description', 'A better film.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = rig.server.updated.last;
    expect(sent.path, '/movies/3');
    expect(sent.body['description'], 'A better film.');
    expect(sent.body.containsKey('pages'), isFalse);
    expect(sent.body['director'], 'Someone');
  });

  testWidgets(
    'pages that are not a number are refused before anything is sent',
    (tester) async {
      final rig = await WorkPageRig.open(tester, record: book);
      await WorkPageRig.menu(tester, 'Edit details');
      await fill(tester, 'Pages', 'lots');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('must be numbers'), findsOneWidget);
      expect(rig.server.updated, isEmpty);
    },
  );

  testWidgets('a refusal is shown in the server\'s words and the form stays', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, record: book);
    await WorkPageRig.menu(tester, 'Edit details');
    rig.server.failUpdatesWith = 409;
    await fill(tester, 'Description', 'New words.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('refused'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
  });

  testWidgets('a work that is not on the server cannot be edited here', (
    tester,
  ) async {
    await WorkPageRig.open(tester, synced: false);
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    expect(find.text('Edit details'), findsNothing);
  });

  testWidgets('a phone that is no longer paired is not offered the edits', (
    tester,
  ) async {
    await WorkPageRig.open(tester, paired: false);
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    expect(find.text('Edit details'), findsNothing);
    expect(find.text('Find it online'), findsNothing);
  });
}
