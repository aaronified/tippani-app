import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/cover_search_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/cover_search.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class _Server extends FakeServer {
  final seen = <String>[];
  Map<String, Object?> books = {'candidates': []};
  Map<String, Object?> images = {'images': []};
  bool imagesFail = false;

  @override
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst(RegExp(r'^.*?/api'), '');
    if (path == '/books/lookup' ||
        path == '/movies/lookup' ||
        path == '/images/search') {
      seen.add('$path ${r.body}');
      if (path == '/images/search') {
        return imagesFail
            ? http.Response('{"error":"no"}', 500)
            : http.Response(jsonEncode(images), 200);
      }
      return http.Response(jsonEncode(books), 200);
    }
    return super.handle(r);
  }
}

Future<(AppController, _Server)> rig() async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = _Server();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  await controller.pair('ABCD2345', 'My phone');
  return (controller, server);
}

class _Fake implements CoverSearch {
  @override
  bool get available => true;
  final asked = <String>[];
  Uint8List bytes = Uint8List.fromList([1, 2, 3]);

  @override
  Future<List<CoverOption>> find({
    required WorkKind kind,
    String title = '',
    String creator = '',
    String isbn = '',
    int? year,
  }) async {
    asked.add('$title|$creator|$isbn');
    return const [
      CoverOption(url: 'https://x.test/a.jpg', source: 'Open Library'),
      CoverOption(url: 'https://x.test/b.png', source: 'Amazon'),
    ];
  }

  @override
  Future<Uint8List> download(String url) async {
    asked.add('download $url');
    return bytes;
  }
}

void main() {
  group('finding covers', () {
    test(
      'the catalogues first, then the picture suppliers, each once and named',
      () async {
        final (c, server) = await rig();
        server.books = {
          'candidates': [
            {
              'cover_url': 'https://x.test/one.jpg',
              'source': 'openlibrary',
              'sources': {'cover': 'openlibrary'},
            },
            {'cover_url': 'https://x.test/one.jpg', 'source': 'google'},
            {'cover_url': 'https://x.test/two.jpg', 'source': 'google'},
          ],
        };
        server.images = {
          'images': [
            {'url': 'https://x.test/three.jpg', 'source': 'amazon'},
            {
              'url': 'https://x.test/four.jpg',
              'source': 'google',
              'thumb': 'https://x.test/four-small.jpg',
            },
          ],
        };
        final found = await PairedCoverSearch(c).find(
          kind: WorkKind.book,
          title: 'Walden',
          creator: 'Thoreau',
          isbn: '9780',
        );
        expect(found.map((o) => o.url), [
          'https://x.test/one.jpg',
          'https://x.test/two.jpg',
          'https://x.test/three.jpg',
          'https://x.test/four.jpg',
        ]);
        expect(found.map((o) => o.source), [
          'Open Library',
          'Google Books',
          'Amazon',
          'Web images',
        ]);
        expect(found.last.shown, 'https://x.test/four-small.jpg');
        expect(server.seen.first, contains('"isbn":"9780"'));
        expect(server.seen.last, startsWith('/images/search'));
      },
    );

    test('a film is searched as a poster, by title and kind', () async {
      final (c, server) = await rig();
      server.books = {
        'candidates': [
          {'poster_url': 'https://x.test/p.jpg', 'source': 'tmdb'},
        ],
      };
      final found = await PairedCoverSearch(c)
          .find(kind: WorkKind.show, title: 'Dark', year: 2017);
      expect(found.single.source, 'TMDB');
      expect(server.seen.first, startsWith('/movies/lookup'));
      expect(server.seen.first, contains('"media_type":"show"'));
      expect(server.seen.first, contains('"year":2017'));
    });

    test(
      'a failing picture supplier does not spoil the catalogues\' answer',
      () async {
        final (c, server) = await rig();
        server.books = {
          'candidates': [
            {'cover_url': 'https://x.test/one.jpg', 'source': 'google'},
          ],
        };
        server.imagesFail = true;
        final found = await PairedCoverSearch(c)
            .find(kind: WorkKind.book, title: 'Walden');
        expect(found, hasLength(1));
      },
    );

    test('a picture is brought down, and what is not one is refused', () async {
      final (c, _) = await rig();
      final ok = PairedCoverSearch(
        c,
        client: MockClient((r) async => http.Response.bytes([9, 9, 9], 200)),
      );
      expect(await ok.download('https://x.test/a.jpg'), [9, 9, 9]);
      final missing = PairedCoverSearch(
        c,
        client: MockClient((r) async => http.Response('', 404)),
      );
      await expectLater(
        missing.download('https://x.test/a.jpg'),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        ok.download('file:///etc/passwd'),
        throwsA(isA<ServerException>()),
      );
      final big = PairedCoverSearch(
        c,
        client: MockClient(
          (r) async => http.Response.bytes(Uint8List(maxCoverBytes + 1), 200),
        ),
      );
      await expectLater(
        big.download('https://x.test/a.jpg'),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('the screen', () {
    late Work work;

    Future<_Fake> open(WidgetTester tester, void Function(Object?) got) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = MemoryLibrary();
      work = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      final fake = _Fake();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => got(
                  await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (_) =>
                          CoverSearchScreen(search: fake, work: work),
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
      return fake;
    }

    testWidgets(
      'starts by searching the work\'s own title and author, and can search again by ISBN',
      (tester) async {
        final fake = await open(tester, (_) {});
        expect(fake.asked.first, 'Walden|Thoreau|');
        expect(find.text('Open Library'), findsWidgets);
        await tester.enterText(
          find.widgetWithText(TextField, 'ISBN'),
          '9780141',
        );
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(fake.asked.last, 'Walden|Thoreau|9780141');
      },
    );

    testWidgets(
      'a source can be filtered to, and a cover chosen is brought down and returned',
      (tester) async {
        Object? result;
        final fake = await open(tester, (r) => result = r);
        await tester.tap(find.widgetWithText(FilterChip, 'Amazon'));
        await tester.pumpAndSettle();
        expect(
          find.text('Open Library'),
          findsOneWidget,
        ); // only its chip is left
        await tester.tap(find.text('Amazon').last);
        await tester.pumpAndSettle();
        expect(find.text('Use this cover?'), findsOneWidget);
        await tester.tap(find.text('Use it'));
        await tester.pumpAndSettle();
        expect(fake.asked.last, 'download https://x.test/b.png');
        final r = result as ({Uint8List bytes, String name});
        expect(r.bytes, [1, 2, 3]);
        expect(r.name, 'cover.png');
      },
    );
  });
}
