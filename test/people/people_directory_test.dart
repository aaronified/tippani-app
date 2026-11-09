import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/library/quote_chips.dart';
import 'package:tippani/people/people_directory.dart';
import 'package:tippani/people/svg_raster.dart';
import 'package:tippani/screens/quote_chips_row.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
const _melville = '0123456789abcdef.png';
const _ishmael = 'fedcba9876543210.png';
const _actorFile = '1111222233334444.png';

Future<(FakeServer, PairedPeopleDirectory, Directory)> _rig() async {
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
  final dir = await Directory.systemTemp.createTemp('tippani_people');
  addTearDown(() => dir.delete(recursive: true));
  final directory = PairedPeopleDirectory(
    controller,
    CoverCache(controller, folder: Directory('${dir.path}/covers')),
    folder: Directory('${dir.path}/people'),
  );
  return (server, directory, dir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a chip gets the portrait of its author, by name, ignoring case',
    () async {
      final (server, d, _) = await _rig();
      server.people['author'] = [
        {'name': 'Herman Melville', 'image_path': _melville},
      ];
      await d.ready();
      expect(
        d.faceOf(const QuoteChip(ChipKind.author, 'herman  MELVILLE')),
        _melville,
      );
      expect(d.faceOf(const QuoteChip(ChipKind.author, 'Nobody')), '');
    },
  );

  test(
    'a character shows its own picture, else the actor who plays them',
    () async {
      final (server, d, _) = await _rig();
      server.characterRows.add({'name': 'Ishmael', 'image_path': _ishmael});
      server.people['actor'] = [
        {'name': 'Gregory Peck', 'image_path': _actorFile},
      ];
      await d.ready();
      expect(
        d.faceOf(
          const QuoteChip(ChipKind.character, 'Ishmael', 'Gregory Peck'),
        ),
        _ishmael,
      );
      expect(
        d.faceOf(const QuoteChip(ChipKind.character, 'Ahab', 'Gregory Peck')),
        _actorFile,
      );
      expect(d.faceOf(const QuoteChip(ChipKind.character, 'Ahab')), '');
    },
  );

  test('a chip shows the face its work cast gives, or the sync saw', () async {
    final (_, d, _) = await _rig();
    await d.ready();
    // the work's cast names the picture
    expect(
      d.faceOf(const QuoteChip(ChipKind.character, 'Ahab', '', _ishmael)),
      _ishmael,
    );
    // a name the sync saw on a quote, spoken in a book
    expect(d.faceOf(const QuoteChip(ChipKind.speaker, 'Queequeg')), '');
    d.rememberFaces({'Queequeg': _actorFile});
    expect(d.faceOf(const QuoteChip(ChipKind.speaker, 'queequeg')), _actorFile);
    expect(
      d.faceOf(const QuoteChip(ChipKind.character, 'Queequeg')),
      _actorFile,
    );
  });

  test('the lists are kept on the phone and read again offline', () async {
    final (server, d, dir) = await _rig();
    server.people['speaker'] = [
      {'name': 'Rumi', 'image_path': _melville, 'signature_path': _ishmael},
    ];
    await d.ready();
    expect(d.person('speaker', 'Rumi')!.signature, _ishmael);

    final again = PairedPeopleDirectory(
      // an app that is not paired reads only its own copy
      AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
      ),
      CoverCache(
        AppController(
          SettingsStore(
            await SharedPreferences.getInstance(),
            MemoryTokenVault(),
          ),
        ),
        folder: Directory('${dir.path}/covers'),
      ),
      folder: Directory('${dir.path}/people'),
    );
    await again.ready();
    expect(again.person('speaker', 'rumi')!.image, _melville);
  });

  test('a vector signature is drawn into a bitmap', () async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 60"><path d="M5 40 C 30 0, 50 60, 80 30" stroke="#000" stroke-width="3" fill="none"/></svg>';
    final bytes = utf8.encode(svg);
    expect(looksLikeSvg(Uint8List.fromList(bytes)), isTrue);
    expect(looksLikeSvg(_png), isFalse);
    final png = await svgToPng(Uint8List.fromList(bytes), height: 40);
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), [0x50, 0x4e, 0x47]);
  });

  testWidgets('the pill draws the portrait where the initial was', (
    tester,
  ) async {
    // real file and network work happens outside the test's fake clock
    final (server, d, _) = (await tester.runAsync(_rig))!;
    server.people['author'] = [
      {'name': 'Herman Melville', 'image_path': _melville},
    ];
    server.covers[_melville] = _png;
    await tester.runAsync(() => d.ready());
    await tester.pumpWidget(
      MaterialApp(
        home: PeopleDirectoryScope(
          directory: d,
          child: Scaffold(
            body: PersonChip(
              chip: const QuoteChip(ChipKind.author, 'Herman Melville'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    // the picture arrives from disk, which a test clock does not wait for: wait up to five seconds, not a fixed moment
    for (var i = 0; i < 250 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('H'), findsNothing);
  });

  testWidgets('without a portrait the pill keeps its initial', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonChip(
            chip: const QuoteChip(ChipKind.speaker, 'Rumi'),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('R'), findsOneWidget);
  });
}
