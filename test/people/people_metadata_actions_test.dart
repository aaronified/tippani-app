import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/people/people_console.dart';
import 'package:tippani/people/people_directory.dart';
import 'package:tippani/people/people_service.dart';
import 'package:tippani/screens/person_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A real client against the fake server, so a press goes all the way to a request and back.
class _Rig {
  _Rig(this.server, this.directory, this.service, this.console);
  final FakeServer server;
  final PairedPeopleDirectory directory;
  final PairedPeopleService service;
  final PairedPeopleConsole console;
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
  final dir = await Directory.systemTemp.createTemp('tippani_meta');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // a picture file may still be open on Windows
    }
  });
  server.people['author'] = [
    {'id': 3, 'name': 'Herman Melville', 'image_path': ''},
  ];
  server.characterRows.add({'id': 7, 'name': 'Ishmael', 'image_path': ''});
  server.covers[FakeServer.linkedPicture] = _png;
  server.personDetails[3] = {
    'id': 3,
    'name': 'Herman Melville',
    'kinds': ['author'],
    'sort_name': 'Melville, Herman',
    'image_path': '',
    'signature_path': '',
    'aliases': <String>[],
    'credits': [],
    'roles': [],
    'lines': [],
  };
  server.characterDetails[7] = {
    'id': 7,
    'name': 'Ishmael',
    'image_path': '',
    'aliases': <String>[],
    'appearances': [],
    'lines': [],
  };
  final directory = PairedPeopleDirectory(
    controller,
    CoverCache(controller, folder: Directory('${dir.path}/covers')),
    folder: Directory('${dir.path}/people'),
  );
  await directory.ready();
  return _Rig(
    server,
    directory,
    PairedPeopleService(controller),
    PairedPeopleConsole(controller),
  );
}

Widget _app(_Rig r, Widget home) => MaterialApp(
  builder: (context, page) => PeopleDirectoryScope(
    directory: r.directory,
    child: PeopleServiceScope(
      service: r.service,
      child: PeopleConsoleScope(console: r.console, child: page!),
    ),
  ),
  home: home,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('More').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<_Rig> _openPerson(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = (await tester.runAsync(_rig))!;
  await tester.pumpWidget(
    _app(r, PersonScreen(id: 3, name: 'Herman Melville', onFilter: (_) {})),
  );
  await _settle(tester);
  return r;
}

Future<_Rig> _openCharacter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = (await tester.runAsync(_rig))!;
  await tester.pumpWidget(
    _app(r, CharacterScreen(id: 7, name: 'Ishmael', onFilter: (_) {})),
  );
  await _settle(tester);
  return r;
}

/// Presses through the picture choice to "From a link", types [url] and confirms.
Future<void> _pasteLink(WidgetTester tester, String url) async {
  await tester.tap(find.text('From a link'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('Save'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a picture from a link', () {
    testWidgets('a person\'s portrait is set from an address', (tester) async {
      final r = await _openPerson(tester);
      await _openMenu(tester, 'Choose a portrait');
      await _pasteLink(tester, 'https://example.org/melville.jpg');
      expect(r.server.personWrites.last.$1, 'PUT /people/id/3');
      expect(r.server.personWrites.last.$2, {
        'image_url': 'https://example.org/melville.jpg',
      });
      expect(
        r.server.personDetails[3]!['image_path'],
        FakeServer.linkedPicture,
      );
      expect(
        r.directory.anyPerson('Herman Melville')?.image,
        FakeServer.linkedPicture,
        reason:
            'the faces elsewhere pick the new portrait up without a restart',
      );
    });

    testWidgets('an address the server cannot fetch is told in its words', (
      tester,
    ) async {
      final r = await _openPerson(tester);
      r.server.refuseImageLink = 'that picture could not be fetched';
      await _openMenu(tester, 'Choose a portrait');
      await _pasteLink(tester, 'https://example.org/nothing.jpg');
      expect(find.text('that picture could not be fetched'), findsOneWidget);
      expect(r.server.personDetails[3]!['image_path'], '');
    });

    testWidgets('a character\'s picture is set from an address', (
      tester,
    ) async {
      final r = await _openCharacter(tester);
      await _openMenu(tester, 'Choose a picture');
      await _pasteLink(tester, 'https://example.org/ishmael.jpg');
      expect(r.server.characterWrites.single.$1, 'PUT /characters/7/image');
      expect(r.server.characterWrites.single.$2, {
        'image_url': 'https://example.org/ishmael.jpg',
      });
      expect(
        r.directory.characterImage('Ishmael'),
        FakeServer.linkedPicture,
        reason: 'the chips elsewhere pick the new picture up',
      );
    });

    testWidgets('a character address the server refuses is told in its words', (
      tester,
    ) async {
      final r = await _openCharacter(tester);
      r.server.refuseImageLink = 'that picture could not be fetched';
      await _openMenu(tester, 'Choose a picture');
      await _pasteLink(tester, 'https://example.org/nope.jpg');
      expect(find.text('that picture could not be fetched'), findsOneWidget);
    });
  });
}
