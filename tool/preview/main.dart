// A browser build of the app over made-up data, for looking at every screen without a phone:
//
//   flutter build web -t tool/preview/main.dart
//
// Nothing here is the real app's storage. The library is the in-memory one the tests use, filled with a few
// books, films and quotes, and nothing talks to a server. See docs/wiki/Developing.md.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_store.dart';

import '../../test/support/memory_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(prefs, MemoryTokenVault());
  final controller = AppController(settings);
  await controller.load();
  final lib = MemoryLibrary();
  await _seed(lib);
  final harness = Harness.fake(settings, controller: controller, library: lib);
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
