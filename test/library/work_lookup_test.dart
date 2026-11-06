import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/work_form_screen.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tools/work_lookup.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

class _Lookup implements WorkLookup {
  _Lookup({this.available = true});

  @override
  bool available;
  List<WorkMatch> matches = const [];
  ServerException? fail;
  final asked = <(WorkKind, String, String)>[];

  @override
  Future<List<WorkMatch>> find(
    WorkKind kind,
    String title, {
    String creator = '',
  }) async {
    asked.add((kind, title, creator));
    final f = fail;
    if (f != null) throw f;
    return matches;
  }
}

class _Server extends FakeServer {
  final seen = <String>[];
  Map<String, Object?> answer = {'candidates': []};
  int status = 200;

  @override
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst(RegExp(r'^.*?/api'), '');
    if (!path.endsWith('/lookup')) return super.handle(r);
    seen.add('${r.method} $path ${r.body}');
    return http.Response(jsonEncode(answer), status);
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

void main() {
  group('the lookup through the server', () {
    test(
      'a book is asked of the books route, with the author when there is one',
      () async {
        final (c, s) = await rig();
        s.answer = {
          'candidates': [
            {
              'title': 'Walden',
              'author': 'Henry David Thoreau',
              'published_year': 1854,
            },
            {'title': '', 'author': 'x'},
          ],
        };
        final found = await PairedWorkLookup(c)
            .find(WorkKind.book, 'Walden', creator: ' Thoreau ');
        expect(
          s.seen.single,
          'POST /books/lookup {"title":"Walden","author":"Thoreau"}',
        );
        expect(found.single.title, 'Walden');
        expect(found.single.creator, 'Henry David Thoreau');
        expect(found.single.year, 1854);
        expect(found.single.summary, 'Henry David Thoreau · 1854');
      },
    );

    test('a film, a show and a game are asked of the movies route with their own media type', () async {
      final (c, s) = await rig();
      s.answer = {
        'candidates': [
          {'title': 'Casablanca', 'release_year': 1942},
        ],
      };
      final lookup = PairedWorkLookup(c);
      final film = await lookup.find(WorkKind.film, 'Casablanca');
      await lookup.find(WorkKind.show, 'Dark');
      await lookup.find(WorkKind.game, 'Hades');
      expect(s.seen[0], contains('/movies/lookup'));
      expect(s.seen[0], contains('"media_type":"movie"'));
      expect(s.seen[1], contains('"media_type":"show"'));
      expect(s.seen[2], contains('"media_type":"game"'));
      expect(film.single.year, 1942);
      expect(film.single.creator, '');
    });

    test(
      'a year of zero is no year; an answer with no list is no matches',
      () async {
        final (c, s) = await rig();
        s.answer = {
          'candidates': [
            {'title': 'A', 'published_year': 0},
          ],
        };
        expect(
          (await PairedWorkLookup(c).find(WorkKind.book, 'A')).single.year,
          isNull,
        );
        s.answer = {'error': 'none'};
        expect(await PairedWorkLookup(c).find(WorkKind.book, 'A'), isEmpty);
      },
    );

    test(
      'the server saying no source is configured comes back in its own words',
      () async {
        final (c, s) = await rig();
        s.status = 400;
        s.answer = {'error': 'No film/show source is configured'};
        await expectLater(
          PairedWorkLookup(c).find(WorkKind.film, 'x'),
          throwsA(isA<ServerException>()),
        );
      },
    );
  });

  group('the work form', () {
    late _Lookup lookup;
    late MemoryLibrary lib;

    Future<void> open(WidgetTester tester, {bool available = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      lookup = _Lookup(available: available);
      lib = MemoryLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkFormScreen(store: lib, lookup: lookup),
        ),
      );
    }

    testWidgets('the button is there only when there is a server to ask', (
      tester,
    ) async {
      await open(tester, available: false);
      expect(find.text('Look up details'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('Look up details'), findsOneWidget);
    });

    testWidgets('a title is needed first', (tester) async {
      await open(tester);
      await tester.tap(find.text('Look up details'));
      await tester.pumpAndSettle();
      expect(find.text('Type a title to look up.'), findsOneWidget);
      expect(lookup.asked, isEmpty);
    });

    testWidgets('choosing a match fills the title, the creator and the year', (
      tester,
    ) async {
      await open(tester);
      lookup.matches = const [
        WorkMatch(title: 'Walden', creator: 'Henry David Thoreau', year: 1854),
        WorkMatch(title: 'Walden Two', creator: 'B. F. Skinner', year: 1948),
      ];
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'walden');
      await tester.tap(find.text('Look up details'));
      await tester.pumpAndSettle();
      expect(lookup.asked.single, (WorkKind.book, 'walden', ''));
      await tester.tap(find.text('Walden Two'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Walden Two'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'B. F. Skinner'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1948'), findsOneWidget);
    });

    testWidgets('no match says so; a server failure says why', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'zzz');
      await tester.tap(find.text('Look up details'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing matched that title.'), findsOneWidget);
      lookup.fail = const ServerException('The server could not be reached.');
      await tester.tap(find.text('Look up details'));
      await tester.pumpAndSettle();
      expect(find.text('The server could not be reached.'), findsOneWidget);
    });

    testWidgets('backing out of the choice changes nothing', (tester) async {
      await open(tester);
      lookup.matches = const [
        WorkMatch(title: 'Walden', creator: 'T', year: 1854),
      ];
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'wal');
      await tester.tap(find.text('Look up details'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'wal'), findsOneWidget);
    });
  });
}
