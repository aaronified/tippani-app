import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';

import '../support/work_page_rig.dart';

/// What a reader does about a work's cover without a picture on the phone: give the server a link to fetch, or take
/// the cover off. Both are written to the server; the phone keeps the file name the server now holds.
void main() {
  const book = {'author': 'Thoreau', 'cover_path': 'abc.png'};

  Future<void> chooseCover(WidgetTester tester, String how) async {
    await WorkPageRig.menu(tester, 'Choose a cover');
    await tester.tap(find.text(how));
    await tester.pumpAndSettle();
  }

  testWidgets('a cover is taken from a link the server fetches', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, record: book);
    await chooseCover(tester, 'Cover from a link');
    await tester.enterText(
      find.widgetWithText(TextField, 'Address of the picture'),
      'https://example.org/walden.png',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = rig.server.updated.last;
    expect(sent.path, '/books/3');
    expect(sent.body['cover_url'], 'https://example.org/walden.png');
    // the rest of the record rides along unchanged
    expect(sent.body['author'], 'Thoreau');
    expect((await rig.library.work(rig.workId))!.cover, 'linked.png');
  });

  testWidgets('a film\'s link goes in as its poster', (tester) async {
    final rig = await WorkPageRig.open(tester, kind: WorkKind.film);
    await chooseCover(tester, 'Cover from a link');
    await tester.enterText(
      find.widgetWithText(TextField, 'Address of the picture'),
      'https://example.org/p.jpg',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = rig.server.updated.last;
    expect(sent.path, '/movies/3');
    expect(sent.body['poster_url'], 'https://example.org/p.jpg');
    expect(sent.body.containsKey('cover_url'), isFalse);
  });

  testWidgets(
    'a link that is not a picture is refused in the server\'s words',
    (tester) async {
      final rig = await WorkPageRig.open(
        tester,
        record: book,
        cover: 'abc.png',
      );
      await chooseCover(tester, 'Cover from a link');
      await tester.enterText(
        find.widgetWithText(TextField, 'Address of the picture'),
        'https://example.org/page.html',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('check the URL points directly'),
        findsOneWidget,
      );
      expect((await rig.library.work(rig.workId))!.cover, 'abc.png');
    },
  );

  testWidgets('Remove cover clears it on the server and on the phone', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, record: book, cover: 'abc.png');
    await chooseCover(tester, 'Remove cover');
    final sent = rig.server.updated.last;
    expect(sent.body['clear_cover'], isTrue);
    expect(rig.server.row('/books', 3)['cover_path'], '');
    expect((await rig.library.work(rig.workId))!.cover, '');
  });

  testWidgets('a work with no cover is not offered Remove cover', (
    tester,
  ) async {
    await WorkPageRig.open(tester, record: {'author': 'Thoreau'});
    await WorkPageRig.menu(tester, 'Choose a cover');
    expect(find.text('Remove cover'), findsNothing);
    expect(find.text('Cover from a link'), findsOneWidget);
  });
}
