import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/share_screen.dart';
import 'package:tippani/share/share_people.dart';

/// A 1x1 PNG, so a face has real bytes.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _People implements SharePeopleSource {
  _People(this.people);

  final SharePeople people;

  @override
  bool get available => true;
  int asked = 0;

  @override
  Future<SharePeople> forQuote(Quote quote, Work? work) async {
    asked++;
    return people;
  }
}

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

Quote _quote({int? workId = 1}) => Quote(
  id: 7,
  workId: workId,
  text: 'Simplify, simplify.',
  translation: '',
  language: '',
  speaker: '',
  chapter: '',
  location: '',
  note: '',
  color: 'blue',
  favorite: false,
  notedAt: DateTime.utc(2026, 11, 6, 12),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

Work _walden() => Work(
  id: 1,
  kind: WorkKind.book,
  title: 'Walden',
  creator: 'Thoreau',
  year: 1854,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> _open(WidgetTester tester, SharePeopleSource? source) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PeopleScope(
        source: source,
        child: ShareScreen(
          quote: _quote(),
          work: _walden(),
          share: (t, s) async {},
          shareImage: (png, name, text) async {},
          picker: _Picker(),
          copy: (t) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('credited names are split on commas, semicolons, & and and', () {
    expect(splitCredits('Ann Lee, Bo Kim & Cy Doe and Di Fox'), [
      'Ann Lee',
      'Bo Kim',
      'Cy Doe',
      'Di Fox',
    ]);
    expect(splitCredits('  '), isEmpty);
    expect(splitCredits('Ann; ann'), ['Ann']);
  });

  testWidgets('with nothing on the server there are no portrait options', (
    tester,
  ) async {
    await _open(tester, _People(SharePeople.none));
    expect(find.widgetWithText(FilterChip, 'Backdrop'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Swap'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Signature'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Quote colour'), findsOneWidget);
  });

  testWidgets('with no people source the picture still opens', (tester) async {
    await _open(tester, null);
    expect(find.text('“Simplify, simplify.”'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Backdrop'), findsNothing);
  });

  testWidgets('a portrait and a signature offer Backdrop, Swap and Signature', (
    tester,
  ) async {
    final people = _People(
      SharePeople(
        faces: [ShareFace('Thoreau', _png)],
        signature: ShareFace('Thoreau', _png),
      ),
    );
    await _open(tester, people);
    expect(people.asked, 1);
    expect(find.widgetWithText(FilterChip, 'Backdrop'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Swap'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Signature'), findsOneWidget);
    // no characters, so no Actor / Character switch
    expect(find.text('Character'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Backdrop'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Backdrop'))
          .selected,
      isTrue,
    );
  });

  testWidgets('switching the author off takes the portrait options with it', (
    tester,
  ) async {
    final people = _People(SharePeople(faces: [ShareFace('Thoreau', _png)]));
    await _open(tester, people);
    expect(find.widgetWithText(FilterChip, 'Backdrop'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Author'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Backdrop'), findsNothing);
  });

  testWidgets('actor and character pictures offer the switch', (tester) async {
    final people = _People(
      SharePeople(
        faces: [ShareFace('Actor', _png)],
        characterFaces: [ShareFace('Role', _png)],
      ),
    );
    await _open(tester, people);
    // a book has no cast, but the source answered with both, so the switch is offered
    expect(find.text('Actor'), findsOneWidget);
    expect(find.text('Character'), findsOneWidget);
  });
}
