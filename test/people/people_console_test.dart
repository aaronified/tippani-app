import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/capture/photo_source.dart';
import 'package:tippani/people/people_console.dart';
import 'package:tippani/people/people_service.dart';
import 'package:tippani/screens/people_console_screen.dart';
import 'package:tippani/screens/person_screen.dart';

import '../support/fake_console.dart';

class _Service implements PeopleService {
  @override
  bool get available => true;

  PersonDetail personRow = const PersonDetail(
    id: 1,
    name: 'Ursula Le Guin',
    kinds: ['author'],
    aliases: ['U. K. Le Guin'],
  );
  CharacterDetail characterRow = const CharacterDetail(
    id: 7,
    name: 'Rick Blaine',
    description: 'Runs a bar.',
    image: '0123456789abcdef.png',
    aliases: ['Richard'],
  );

  @override
  Future<PersonDetail?> person(int id) async => personRow;

  @override
  Future<CharacterDetail?> character(int id) async => characterRow;

  @override
  Future<PersonDetail?> save(int id, PersonEdit edit) async => personRow;

  @override
  Future<void> uploadPortrait(int id, Uint8List bytes, String fileName) async {}

  @override
  Future<void> clearPortrait(int id) async {}

  @override
  Future<String> fetch(int id) async => 'Done.';

  @override
  Future<void> uploadSignature(
    int id,
    Uint8List bytes,
    String fileName,
  ) async {}

  @override
  Future<void> clearSignature(int id) async {}
}

class _Photos implements PhotoSource {
  _Photos(this.path);
  final String path;
  @override
  Future<String?> take() async => path;
  @override
  Future<String?> choose() async => path;
}

Widget _app(FakeConsole console, Widget home, {_Service? service}) =>
    MaterialApp(
      builder: (context, page) => PeopleConsoleScope(
        console: console,
        child: PeopleServiceScope(service: service ?? _Service(), child: page!),
      ),
      home: home,
    );

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('More').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {});

  group('the console', () {
    Future<FakeConsole> open(WidgetTester tester, {int start = 0}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final console = FakeConsole();
      await tester.pumpWidget(
        _app(
          console,
          PeopleConsoleScreen(console: console, onFilter: (_) {}, start: start),
        ),
      );
      await tester.pumpAndSettle();
      return console;
    }

    testWidgets('lists people with their counts, and searches spellings too', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('People (3)'), findsOneWidget);
      expect(find.text('Humphrey Bogart'), findsOneWidget);
      expect(find.textContaining('2 works · 5 quotes'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), 'u. k.');
      await tester.pumpAndSettle();
      // a spelling of the first one finds it, and the others fall away
      expect(find.text('Ursula Le Guin'), findsOneWidget);
      expect(find.text('Humphrey Bogart'), findsNothing);
    });

    testWidgets('filters to those with no photo and by kind', (tester) async {
      await open(tester);
      expect(find.text('No photo (2)'), findsOneWidget);
      await tester.tap(find.text('No photo (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Ursula K. Le Guin'), findsNothing);
      expect(find.text('Humphrey Bogart'), findsOneWidget);
      await tester.tap(find.text('No photo (2)'));
      await tester.tap(find.text('Actors'));
      await tester.pumpAndSettle();
      expect(find.text('Humphrey Bogart'), findsOneWidget);
      expect(find.text('Ursula Le Guin'), findsNothing);
    });

    testWidgets('two records chosen can be merged, keeping the one picked', (
      tester,
    ) async {
      final console = await open(tester);
      await tester.longPress(find.text('Ursula Le Guin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ursula K. Le Guin'));
      await tester.pumpAndSettle();
      expect(find.text('2 chosen'), findsOneWidget);
      await _tapText(tester, 'Merge');
      // the second is the one to keep
      await tester.tap(find.text('Ursula K. Le Guin').last);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Merge');
      expect(console.calls, ['mergePeople 2 1']);
      expect(find.text('People (2)'), findsOneWidget);
    });

    testWidgets('the server\'s refusal is shown and nothing changes', (
      tester,
    ) async {
      final console = await open(tester);
      console.refuse = 'you cannot merge a record into itself';
      await tester.longPress(find.text('Ursula Le Guin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Humphrey Bogart'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Merge');
      await _tapText(tester, 'Merge');
      expect(
        find.text('you cannot merge a record into itself'),
        findsOneWidget,
      );
      expect(find.text('People (3)'), findsOneWidget);
    });

    testWidgets('a spelling box saves every line, first line first', (
      tester,
    ) async {
      final console = await open(tester);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Names and spellings'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Ursula Le Guin\nU. K. Le Guin\nUrsula Kroeber',
      );
      await _tapText(tester, 'Save');
      expect(console.calls, [
        'setNames p1 Ursula Le Guin|U. K. Le Guin|Ursula Kroeber',
      ]);
    });

    testWidgets('removing asks first', (tester) async {
      final console = await open(tester);
      // the rows' menus come first, the bar's menu last: this is the third row's
      await tester.tap(find.byTooltip('More').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.textContaining('goes to the Bin'), findsOneWidget);
      await _tapText(tester, 'Remove');
      expect(console.calls, ['deletePerson 3']);
      expect(find.text('Humphrey Bogart'), findsNothing);
    });

    testWidgets('characters: add one, and the unused are tidied away', (
      tester,
    ) async {
      final console = await open(tester, start: 1);
      expect(find.text('Rick Blaine'), findsOneWidget);
      expect(find.textContaining('Casablanca'), findsOneWidget);
      await tester.tap(find.text('Add a character'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Ilsa Lund',
      );
      await _tapText(tester, 'Add');
      expect(console.calls, ['createCharacter Ilsa Lund']);
      expect(find.text('Ilsa Lund'), findsOneWidget);

      await tester.tap(find.byTooltip('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove what nothing uses (3)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 person and 2 characters'), findsOneWidget);
      await _tapText(tester, 'Remove');
      expect(console.calls.last, 'prune');
    });

    testWidgets('asks the server to fetch what is missing', (tester) async {
      final console = await open(tester);
      await tester.tap(find.byTooltip('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fetch missing photos and details'));
      await tester.pumpAndSettle();
      expect(console.calls, ['fetchMissing']);
      expect(find.textContaining('fetching photos'), findsOneWidget);
    });
  });

  group('on a person\'s page', () {
    Future<FakeConsole> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final console = FakeConsole();
      await tester.pumpWidget(
        _app(
          console,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PersonScreen(
                      id: 1,
                      name: 'Ursula Le Guin',
                      onFilter: (_) {},
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
      return console;
    }

    testWidgets('a spelling is made a record of its own after asking', (
      tester,
    ) async {
      final console = await open(tester);
      await tester.tap(find.text('U. K. Le Guin'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Split it out');
      expect(console.calls, ['split p1 U. K. Le Guin']);
    });

    testWidgets('merging into another person closes the page', (tester) async {
      final console = await open(tester);
      await _menu(tester, 'Merge into another person');
      await tester.tap(find.text('Humphrey Bogart'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Merge');
      expect(console.calls, ['mergePeople 1 3']);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('removing the person asks, then closes the page', (
      tester,
    ) async {
      final console = await open(tester);
      await _menu(tester, 'Remove this person');
      await _tapText(tester, 'Remove');
      expect(console.calls, ['deletePerson 1']);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('on a character\'s page', () {
    Future<FakeConsole> open(WidgetTester tester, {PhotoSource? photos}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final console = FakeConsole();
      await tester.pumpWidget(
        _app(
          console,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => CharacterScreen(
                      id: 7,
                      name: 'Rick Blaine',
                      onFilter: (_) {},
                      photos: photos,
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
      return console;
    }

    testWidgets('details are edited in a form and saved', (tester) async {
      final console = await open(tester);
      await _menu(tester, 'Edit details');
      expect(find.widgetWithText(TextField, 'Rick Blaine'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Runs a bar.'),
        'Runs a bar in Casablanca.',
      );
      await _tapText(tester, 'Save');
      expect(console.calls.single, startsWith('saveCharacter 7'));
      expect(console.calls.single, contains('Runs a bar in Casablanca.'));
    });

    testWidgets('the picture is chosen from the phone, or taken away', (
      tester,
    ) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('tippani_char'),
      );
      addTearDown(() async {
        try {
          await dir!.delete(recursive: true);
        } on FileSystemException {
          // nothing to do
        }
      });
      final file = File('${dir!.path}/still.png');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
      final console = await open(tester, photos: _Photos(file.path));
      await _menu(tester, 'Choose a picture');
      // the file is read outside the test's clock
      for (var i = 0; i < 40 && console.calls.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(console.calls, ['uploadCharacterImage 7 still.png']);
      await _menu(tester, 'Remove the picture');
      expect(console.calls.last, 'clearCharacterImage 7');
    });

    testWidgets('a spelling can be split out, and the character removed', (
      tester,
    ) async {
      final console = await open(tester);
      await tester.tap(find.text('Richard'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Split it out');
      expect(console.calls, ['split c7 Richard']);
      await _menu(tester, 'Remove this character');
      await _tapText(tester, 'Remove');
      expect(console.calls.last, 'deleteCharacter 7');
      expect(find.text('open'), findsOneWidget);
    });
  });
}
