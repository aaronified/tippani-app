import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/metadata/metadata_service.dart';

import '../support/fake_metadata.dart';
import '../support/work_page_rig.dart';

/// What a reader does for a work no catalogue is linked to: ask the server what it might be, pick the right entry,
/// confirm, and have the link written on the server.
void main() {
  const walden = {
    'source': 'google',
    'source_id': 'gb-1',
    'title': 'Walden',
    'author': 'Henry David Thoreau',
    'published_year': 1854,
    'google_id': 'gb-1',
    'cover_url': 'https://example.org/c.jpg',
  };
  const waldenOl = {
    'source': 'openlibrary',
    'source_id': 'OL1W',
    'title': 'Walden; or, Life in the Woods',
    'author': 'Thoreau',
    'published_year': 1854,
    'openlibrary_id': 'OL1W',
  };

  testWidgets('a book is looked up by what the page knows and linked on pick', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(
      tester,
      record: {'author': 'Thoreau', 'translator': 'A. Translator'},
    );
    rig.server.bookCandidates = [walden, waldenOl];
    await WorkPageRig.menu(tester, 'Find it online');
    expect(rig.server.lookups.single, startsWith('/books/lookup'));
    expect(
      jsonDecode(rig.server.lookups.single.split(' ').skip(1).join(' ')),
      containsPair('title', 'Walden'),
    );
    expect(find.text('Walden; or, Life in the Woods'), findsOneWidget);
    expect(find.textContaining('Henry David Thoreau'), findsOneWidget);
    expect(find.textContaining('1854'), findsWidgets);
    await tester.tap(find.text('Walden'));
    await tester.pumpAndSettle();
    // nothing is sent until the reader confirms
    expect(rig.server.updated, isEmpty);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    final sent = rig.server.updated.single;
    expect(sent.path, '/books/3');
    expect(sent.body['source'], 'google');
    expect(sent.body['source_id'], 'gb-1');
    expect(sent.body['google_id'], 'gb-1');
    // the record rides along, so nothing else is lost
    expect(sent.body['translator'], 'A. Translator');
    // back on the work's page
    expect(find.text('Which one is it?'), findsNothing);
  });

  testWidgets('declining the confirmation links nothing', (tester) async {
    final rig = await WorkPageRig.open(tester);
    rig.server.bookCandidates = [walden];
    await WorkPageRig.menu(tester, 'Find it online');
    await tester.tap(find.text('Walden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rig.server.updated, isEmpty);
    expect(find.text('Which one is it?'), findsOneWidget);
  });

  testWidgets('a film is linked by its source and id, as a re-sync', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, kind: WorkKind.film);
    rig.server.movieCandidates = [
      {
        'source': 'tmdb',
        'source_id': '603',
        'tmdb_id': 603,
        'media_type': 'movie',
        'title': 'Walden',
        'release_year': 2011,
      },
    ];
    await WorkPageRig.menu(tester, 'Find it online');
    expect(rig.server.lookups.single, startsWith('/movies/lookup'));
    await tester.tap(find.text('Walden'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pulled again'), findsOneWidget);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(rig.server.updated.single.path, '/movies/3');
    expect(rig.server.updated.single.body, {
      'source': 'tmdb',
      'source_id': '603',
      'media_type': 'movie',
    });
  });

  testWidgets('Fetch metadata on an unlinked work leads straight here', (
    tester,
  ) async {
    final meta = FakeMetadata()
      ..checkResult = const [
        ReverifyItem(type: 'book', id: 3, title: 'Walden', status: 'unpinned'),
      ];
    final rig = await WorkPageRig.open(
      tester,
      around: (page) => MetadataScope(service: meta, child: page),
    );
    rig.server.bookCandidates = [walden];
    await WorkPageRig.menu(tester, 'Fetch metadata');
    expect(find.textContaining('No source is linked'), findsOneWidget);
    await tester.tap(find.text('Find it online'));
    await tester.pumpAndSettle();
    expect(find.text('Which one is it?'), findsOneWidget);
    expect(find.text('Walden'), findsOneWidget);
  });

  testWidgets('nothing found says so', (tester) async {
    await WorkPageRig.open(tester);
    await WorkPageRig.menu(tester, 'Find it online');
    expect(find.textContaining('Nothing matched'), findsOneWidget);
  });

  testWidgets('a lookup the server cannot do is shown in its words', (
    tester,
  ) async {
    final rig = await WorkPageRig.open(tester, kind: WorkKind.film);
    rig.server.lookupRefusal = 'No movie source is configured.';
    await WorkPageRig.menu(tester, 'Find it online');
    expect(find.text('No movie source is configured.'), findsOneWidget);
  });

  testWidgets('a work that is not on the server is not offered it', (
    tester,
  ) async {
    await WorkPageRig.open(tester, synced: false);
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    expect(find.text('Find it online'), findsNothing);
  });
}
