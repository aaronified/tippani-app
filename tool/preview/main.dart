// A browser build of the app over made-up data, for looking at every screen without a phone:
//
//   flutter build web -t tool/preview/main.dart
//
// Nothing here is the real app's storage. The library is the in-memory one the tests use, filled with a few
// books, films and quotes, and nothing talks to a server. See docs/wiki/Developing.md.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/share/share_people.dart';

import '../../test/support/fake_anthologies.dart';
import '../../test/support/fake_server.dart';
import '../../test/support/fake_tools.dart';
import '../../test/support/memory_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://tippani.example.org',
  });
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(prefs, MemoryTokenVault());
  // A made-up server that answers like the real one, so the screens that need a server have something to show.
  final server = FakeServer();
  final controller = AppController(settings, clientFactory: server.factory);
  await controller.load();
  await controller.pair('ABCD2345', 'Preview phone');
  final lib = MemoryLibrary();
  await _seed(lib);
  final anthologies = FakeAnthologies();
  anthologies.seed(
    'Stoic mornings',
    intro: 'What to read before the day starts.',
  );
  anthologies.seed('Speeches that held a room');
  final tools = FakeTools();
  tools.put(1, 'The mass of men lead lives of quiet desperation.');
  tools.put(2, 'Heat', kind: 'movie');
  final harness = Harness.fake(
    settings,
    controller: controller,
    library: lib,
    anthologies: anthologies,
    tools: tools,
    people: _PreviewPeople(),
  );
  runApp(TippaniApp(controller: controller, harness: harness));
}

Future<void> _seed(MemoryLibrary lib) async {
  final walden = await lib.addWork(
    const WorkDraft(
      title: 'Walden',
      creator: 'Henry David Thoreau',
      year: 1854,
    ),
  );
  final meditations = await lib.addWork(
    const WorkDraft(
      title: 'Meditations',
      creator: 'Marcus Aurelius',
      year: 180,
    ),
  );
  final pride = await lib.addWork(
    const WorkDraft(
      title: 'Pride and Prejudice',
      creator: 'Jane Austen',
      year: 1813,
    ),
  );
  final heat = await lib.addWork(
    const WorkDraft(
      title: 'Heat',
      kind: WorkKind.film,
      creator: 'Michael Mann',
      year: 1995,
    ),
  );
  await lib.addWork(
    const WorkDraft(
      title: 'Disco Elysium',
      kind: WorkKind.game,
      creator: 'ZA/UM',
      year: 2019,
    ),
  );
  final speeches = await lib.addBoard('Speeches', color: 'blue');
  final proverbs = await lib.addBoard('Proverbs', color: 'green');
  await lib.addBoard('Others', color: 'orange');

  Future<void> q(
    String text, {
    int? work,
    String speaker = '',
    String chapter = '',
    String location = '',
    String note = '',
    String color = 'yellow',
    bool favorite = false,
    List<String> tags = const [],
    int? board,
    String translation = '',
    String language = '',
  }) async {
    await lib.addQuote(
      QuoteDraft(
        text: text,
        workId: work,
        speaker: speaker,
        chapter: chapter,
        location: location,
        note: note,
        color: color,
        favorite: favorite,
        tags: tags,
        boardId: board,
        translation: translation,
        language: language,
      ),
    );
  }

  await q(
    'I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived.',
    work: walden.id,
    chapter: 'Where I Lived, and What I Lived For',
    location: 'p. 90',
    favorite: true,
    tags: ['nature', 'life'],
    color: 'green',
    note: 'The one to reread every spring.',
  );
  await q(
    'The mass of men lead lives of quiet desperation.',
    work: walden.id,
    chapter: 'Economy',
    location: 'p. 8',
    tags: ['life'],
  );
  await q(
    'You have power over your mind, not outside events. Realise this, and you will find strength.',
    work: meditations.id,
    location: 'VI.8',
    tags: ['stoic'],
    color: 'blue',
    favorite: true,
  );
  await q(
    'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    work: pride.id,
    chapter: 'Chapter 1',
    speaker: 'Narrator',
    color: 'pink',
  );
  await q(
    'A guy told me once, do not let yourself get attached to anything you are not willing to walk out on in thirty seconds flat if you feel the heat around the corner.',
    work: heat.id,
    speaker: 'Neil McCauley',
    location: '00:21:14',
    tags: ['film'],
    color: 'purple',
  );
  await q(
    'We shall defend our island, whatever the cost may be, we shall fight on the beaches.',
    speaker: 'Winston Churchill',
    chapter: 'House of Commons',
    location: 'London, 4 June 1940',
    board: speeches.id,
    tags: ['war'],
  );
  await q(
    'The only thing we have to fear is fear itself.',
    speaker: 'Franklin D. Roosevelt',
    chapter: 'First inaugural address',
    board: speeches.id,
    favorite: true,
    color: 'orange',
  );
  await q(
    'অতি লোভে তাঁতি নষ্ট।',
    translation: 'Too much greed ruins the weaver.',
    language: 'Bengali',
    board: proverbs.id,
    color: 'green',
  );
  await q('A rolling stone gathers no moss.', board: proverbs.id);
  await q('Be water, my friend.', speaker: 'Bruce Lee');
}

/// Pictures of people drawn on the spot, so the share picture's portraits, backdrop and signature can be looked at.
class _PreviewPeople implements SharePeopleSource {
  @override
  bool get available => true;

  @override
  Future<SharePeople> forQuote(Quote quote, Work? work) async {
    final name = quote.speaker.isNotEmpty
        ? quote.speaker
        : (work?.creator ?? 'Someone');
    final names = [name, 'Second Person'];
    return SharePeople(
      faces: [
        for (var i = 0; i < names.length; i++)
          ShareFace(names[i], await _portrait(names[i], i)),
      ],
      signature: ShareFace(name, await _signature()),
    );
  }

  Future<Uint8List> _portrait(String name, int i) async {
    const s = 300.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final hues = [24.0, 200.0];
    c.drawRect(
      const Rect.fromLTWH(0, 0, s, s),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(s, s), [
          HSLColor.fromAHSL(1, hues[i], 0.45, 0.62).toColor(),
          HSLColor.fromAHSL(1, hues[i] + 30, 0.5, 0.30).toColor(),
        ]),
    );
    c.drawCircle(
      const Offset(s / 2, s * 0.40),
      s * 0.17,
      Paint()..color = const Color(0x66FFFFFF),
    );
    c.drawOval(
      const Rect.fromLTWH(s * 0.22, s * 0.62, s * 0.56, s * 0.5),
      Paint()..color = const Color(0x66FFFFFF),
    );
    final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<Uint8List> _signature() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final path = Path()
      ..moveTo(4, 50)
      ..cubicTo(30, -10, 50, 90, 80, 30)
      ..cubicTo(100, 0, 110, 70, 150, 25)
      ..cubicTo(170, 10, 180, 40, 196, 28);
    c.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final img = await rec.endRecording().toImage(200, 80);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
