import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/quote_chips.dart';
import 'package:tippani/people/face_stack.dart';
import 'package:tippani/people/people_directory.dart';
import 'package:tippani/people/people_service.dart';
import 'package:tippani/screens/library_widgets.dart';
import 'package:tippani/screens/work_details_section.dart';
import 'package:tippani/screens/quote_chips_row.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
const _melville = '0123456789abcdef.png';
const _ishmael = 'fedcba9876543210.png';

class _Rig {
  _Rig(this.server, this.directory, this.service, this.controller);
  final FakeServer server;
  final PairedPeopleDirectory directory;
  final PairedPeopleService service;
  final AppController controller;
}

Future<_Rig> _rig() async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  await controller.pair('ABCD2345', 'My phone');
  final dir = await Directory.systemTemp.createTemp('tippani_person');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // a picture file may still be open on Windows
    }
  });

  server.people['author'] = [
    {'id': 3, 'name': 'Herman Melville', 'image_path': _melville},
  ];
  server.people['actor'] = [
    {'id': 9, 'name': 'Richard Basehart', 'image_path': ''},
  ];
  server.characterRows.add({
    'id': 7,
    'name': 'Ishmael',
    'image_path': _ishmael,
  });
  server.covers[_melville] = _png;
  server.covers[_ishmael] = _png;
  server.personDetails[3] = {
    'id': 3,
    'name': 'Herman Melville',
    'kinds': ['author'],
    'bio': 'Wrote Moby-Dick.',
    'born': '1819',
    'died': '1891',
    'links': 'https://en.wikipedia.org/wiki/Herman_Melville\nhttps://example.com/x | My site',
    'note': 'A favourite.',
    'image_path': _melville,
    'signature_path': '',
    'aliases': ['H. Melville'],
    'credits': [
      {
        'kind': 'book',
        'work_id': 1,
        'title': 'Moby-Dick',
        'role': 'author',
        'year': 1851,
      },
    ],
    'roles': [],
    'lines': [
      {
        'id': 1,
        'text': 'Call me Ishmael.',
        'name': 'Herman Melville',
        'work_id': 1,
        'work_title': 'Moby-Dick',
        'favorite': true,
      },
    ],
    'shared_lines': 2,
    'quotes': 5,
    'favourites': 1,
  };
  server.personDetails[9] = {
    'id': 9,
    'name': 'Richard Basehart',
    'kinds': ['actor'],
    'aliases': [],
    'credits': [],
    'roles': [],
    'lines': [],
  };
  server.characterDetails[7] = {
    'id': 7,
    'name': 'Ishmael',
    'description': 'The narrator.',
    'image_path': _ishmael,
    'aliases': ['Call-me-Ishmael'],
    'appearances': [
      {
        'kind': 'movie',
        'work_id': 2,
        'work_title': 'Moby Dick (1956)',
        'character': 'Ishmael',
        'actor': 'Richard Basehart',
      },
    ],
    'lines': [],
    'quotes': 1,
    'favourites': 0,
  };

  final directory = PairedPeopleDirectory(
    controller,
    CoverCache(controller, folder: Directory('${dir.path}/covers')),
    folder: Directory('${dir.path}/people'),
  );
  await directory.ready();
  return _Rig(server, directory, PairedPeopleService(controller), controller);
}

/// The scopes wrap the navigator, as in the app, so a page pushed from [child] can reach them too.
Widget _scoped(_Rig r, Widget child) => MaterialApp(
  builder: (context, page) => PeopleDirectoryScope(
    directory: r.directory,
    child: PeopleServiceScope(service: r.service, child: page!),
  ),
  home: Scaffold(body: child),
);

Quote _quote({String speaker = ''}) => Quote(
  id: 1,
  workId: 1,
  text: 'Call me Ishmael.',
  translation: '',
  language: '',
  speaker: speaker,
  chapter: '',
  location: '',
  note: '',
  color: '',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

Work _work(WorkKind kind, {String creator = ''}) => Work(
  id: 1,
  kind: kind,
  title: 'Moby-Dick',
  creator: creator,
  year: 1851,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// A tall screen, so a long page is built in full.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  // real file work (the pictures) happens outside the test clock
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('links', () {
    test('a provider is named, an unknown address gets its host, a given name wins', () {
      final l = parseLinks(
        'https://en.wikipedia.org/wiki/X\nhttps://www.example.com/a\nhttps://imdb.com/n | Their page\nnot a link',
      );
      expect(l.map((x) => x.label), ['Wikipedia', 'example.com', 'Their page']);
    });
  });

  group('the pills', () {
    test('a work page leaves out its own author, and keeps the speaker', () {
      final w = _work(WorkKind.book, creator: 'Herman Melville');
      final q = _quote(speaker: 'Ishmael');
      expect(chipsFor(q, w).map((c) => c.name), ['Herman Melville', 'Ishmael']);
      expect(chipsFor(q, w, omitAuthor: true).map((c) => c.name), ['Ishmael']);
    });

    test('a credit is split into the people in it', () {
      expect(creditNames('Neil Gaiman & Terry Pratchett'), [
        'Neil Gaiman',
        'Terry Pratchett',
      ]);
      expect(creditNames('A, B and A'), ['A', 'B']);
    });

    testWidgets(
      'a pill opens the person\'s page, and its button filters the library',
      (tester) async {
        _tall(tester);
        final r = (await tester.runAsync(_rig))!;
        ChipFilter? got;
        await tester.pumpWidget(
          _scoped(
            r,
            QuoteChipsRow(
              quote: _quote(),
              work: _work(WorkKind.book, creator: 'Herman Melville'),
              onTap: (f) => got = f,
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.text('Herman Melville'));
        await tester.pumpAndSettle();
        await _settle(tester);

        // the page: bio, dates, the alias, the work, the line, the links
        expect(find.text('Wrote Moby-Dick.'), findsOneWidget);
        expect(find.text('1819 – 1891'), findsOneWidget);
        expect(find.text('H. Melville'), findsOneWidget);
        expect(find.text('Moby-Dick'), findsWidgets);
        expect(find.text('Call me Ishmael.'), findsOneWidget);
        expect(find.text('Wikipedia'), findsOneWidget);
        expect(find.text('My site'), findsOneWidget);
        expect(find.text('7 quotes · 1 favourite'), findsOneWidget);
        expect(got, isNull, reason: 'opening the page does not filter');

        await tester.ensureVisible(find.text('Show their quotes'));
        await tester.tap(find.text('Show their quotes'));
        await tester.pumpAndSettle();
        expect(got!.name, 'Herman Melville');
        expect(
          find.text('Wrote Moby-Dick.'),
          findsNothing,
          reason: 'the page closed',
        );
      },
    );

    testWidgets('a name the server has no record of still gets a page', (
      tester,
    ) async {
      final r = (await tester.runAsync(_rig))!;
      await tester.pumpWidget(
        _scoped(
          r,
          QuoteChipsRow(
            quote: _quote(speaker: 'Nobody Known'),
            work: null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Nobody Known'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('has no page for Nobody Known'),
        findsOneWidget,
      );
      expect(find.text('Show their quotes'), findsOneWidget);
    });

    testWidgets(
      'a character\'s page names who played them, and that opens the actor',
      (tester) async {
        _tall(tester);
        final r = (await tester.runAsync(_rig))!;
        await tester.pumpWidget(
          _scoped(
            r,
            QuoteChipsRow(
              quote: _quote(speaker: 'Ishmael'),
              work: Work(
                id: 2,
                kind: WorkKind.film,
                title: 'Moby Dick (1956)',
                creator: '',
                year: 1956,
                language: '',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                details: const WorkDetails(
                  cast: [
                    CastMember(character: 'Ishmael', actor: 'Richard Basehart'),
                  ],
                ),
              ),
              onTap: (_) {},
            ),
          ),
        );
        await tester.tap(find.text('Ishmael'));
        await tester.pumpAndSettle();
        await _settle(tester);
        expect(find.text('The narrator.'), findsOneWidget);
        expect(find.text('Call-me-Ishmael'), findsOneWidget);
        expect(find.text('PLAYED BY'), findsOneWidget);
        await tester.tap(find.text('Richard Basehart').first);
        await tester.pumpAndSettle();
        expect(
          find.text('Actor'),
          findsOneWidget,
          reason: 'the actor\'s own page',
        );
      },
    );
  });

  group('faces on a card', () {
    testWidgets('a stack shows only the people who have a picture', (
      tester,
    ) async {
      final r = (await tester.runAsync(_rig))!;
      await tester.pumpWidget(
        _scoped(r, const FaceStack(names: ['Herman Melville', 'No Portrait'])),
      );
      await _settle(tester);
      expect(find.byType(PersonFace), findsOneWidget);
    });

    testWidgets('a stack for people with no picture draws nothing', (
      tester,
    ) async {
      final r = (await tester.runAsync(_rig))!;
      await tester.pumpWidget(
        _scoped(r, const FaceStack(names: ['No Portrait'])),
      );
      expect(find.byType(PersonFace), findsNothing);
    });

    testWidgets(
      'a cast row has the character\'s picture, and a press opens their page',
      (tester) async {
        _tall(tester);
        final r = (await tester.runAsync(_rig))!;
        ChipFilter? got;
        await tester.pumpWidget(
          _scoped(
            r,
            WorkDetailsSection(
              onFilter: (f) => got = f,
              work: Work(
                id: 2,
                kind: WorkKind.film,
                title: 'Moby Dick (1956)',
                creator: '',
                year: 1956,
                language: '',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                details: const WorkDetails(
                  cast: [
                    CastMember(character: 'Ishmael', actor: 'Richard Basehart'),
                  ],
                ),
              ),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byType(PersonFace), findsOneWidget);
        expect(find.text('Richard Basehart as Ishmael'), findsOneWidget);
        await tester.tap(find.text('Richard Basehart as Ishmael'));
        await tester.pumpAndSettle();
        await _settle(tester);
        expect(find.text('The narrator.'), findsOneWidget);
        expect(got, isNull);
      },
    );

    testWidgets('a work tile carries the author\'s face', (tester) async {
      final r = (await tester.runAsync(_rig))!;
      await tester.pumpWidget(
        _scoped(
          r,
          WorkTile(
            work: _work(WorkKind.book, creator: 'Herman Melville'),
            onTap: () {},
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(FaceStack), findsOneWidget);
      expect(find.byType(PersonFace), findsOneWidget);
    });
  });

  group('editing a person', () {
    test(
      'only the fields that changed are sent, and the person comes back',
      () async {
        final r = await _rig();
        final p = await r.service.save(3, const PersonEdit(bio: 'New bio.'));
        expect(r.server.personWrites.single.$1, 'PUT /people/id/3');
        expect(r.server.personWrites.single.$2, {'bio': 'New bio.'});
        expect(p!.bio, 'New bio.');
        expect(p.born, '1819', reason: 'the rest is untouched');
      },
    );

    test('removing the portrait and the signature ask the server to', () async {
      final r = await _rig();
      await r.service.clearPortrait(3);
      await r.service.clearSignature(3);
      expect(r.server.personWrites.map((w) => w.$2), [
        {'clear_image': true},
        {'clear_signature': true},
      ]);
      expect((await r.service.person(3))!.image, '');
    });

    test('a person the server does not have is a plain error', () async {
      final r = await _rig();
      expect(() => r.service.person(99), throwsA(isA<Exception>()));
    });
  });
}
