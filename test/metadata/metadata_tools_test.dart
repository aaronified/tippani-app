import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/metadata/metadata_service.dart';
import 'package:tippani/screens/metadata_tools_screen.dart';

import '../support/fake_metadata.dart';

Future<void> open(
  WidgetTester tester,
  FakeMetadata service, {
  bool admin = false,
  VoidCallback? onChanged,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MetadataToolsScreen(
        service: service,
        admin: admin,
        onChanged: onChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

ReverifyItem item({
  int id = 1,
  String title = 'Walden',
  List<FieldDiff>? diffs,
}) => ReverifyItem(
  type: 'book',
  id: id,
  title: title,
  status: 'ok',
  source: 'openlibrary',
  diffs:
      diffs ??
      const [
        FieldDiff(
          field: 'description',
          stored: '',
          fresh: 'A cabin in the woods.',
        ),
        FieldDiff(field: 'published_year', stored: 1850, fresh: 1854),
        FieldDiff(
          field: 'genres',
          stored: <String>[],
          fresh: ['Nature'],
          alts: [
            FieldAlt('openlibrary', ['Nature']),
            FieldAlt('google', ['Essays', 'Nature']),
          ],
        ),
      ],
);

void main() {
  group('the gaps', () {
    testWidgets('lists works with what they lack, and filters by a gap', (
      tester,
    ) async {
      await open(tester, FakeMetadata());
      expect(find.text('Gaps (2)'), findsOneWidget);
      expect(find.text('Walden'), findsOneWidget);
      expect(find.textContaining('Missing: Cover, Synopsis'), findsOneWidget);
      // a work with every detail is not listed
      expect(find.text('Casablanca'), findsNothing);
      await tester.tap(find.text('No Year (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Walden'), findsNothing);
      expect(find.text('Middlemarch'), findsOneWidget);
    });

    testWidgets('a check with nothing new says so, and says why', (
      tester,
    ) async {
      final s = FakeMetadata()
        ..checkResult = const [
          ReverifyItem(
            type: 'book',
            id: 1,
            title: 'Walden',
            status: 'unpinned',
            error: 'no id',
          ),
        ];
      await open(tester, s);
      await tester.tap(find.text('Walden'));
      await tester.pumpAndSettle();
      expect(s.calls, ['check book1']);
      expect(find.textContaining('1 has no id to look up by'), findsOneWidget);
    });

    testWidgets('long press chooses several to re-check together', (
      tester,
    ) async {
      final s = FakeMetadata();
      await open(tester, s);
      await tester.longPress(find.text('Walden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Middlemarch'));
      await tester.pumpAndSettle();
      expect(find.text('2 chosen'), findsOneWidget);
      await tapText(tester, 'Re-check');
      expect(s.calls, ['check book1,book2']);
    });

    testWidgets('the server\'s refusal is shown', (tester) async {
      final s = FakeMetadata()..refuse = 'try later';
      await open(tester, s);
      await tester.tap(find.text('Walden'));
      await tester.pumpAndSettle();
      expect(find.text('try later'), findsOneWidget);
    });

    testWidgets('fill and cover jobs start; covers are for an admin only', (
      tester,
    ) async {
      final s = FakeMetadata();
      await open(tester, s);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Fetch missing covers'), findsNothing);
      await tester.tap(find.text('Fill every work\'s gaps'));
      await tester.pumpAndSettle();
      expect(s.calls, ['fillAll']);

      final a = FakeMetadata();
      await open(tester, a, admin: true);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fetch missing covers'));
      await tester.pumpAndSettle();
      expect(a.calls, ['covers true']);
    });
  });

  group('the review', () {
    testWidgets(
      'empty fields are ticked, ones that would replace something are not, and only the ticked are written with what was shown',
      (tester) async {
        final s = FakeMetadata()..checkResult = [item()];
        var changed = 0;
        await open(tester, s, onChanged: () => changed++);
        await tester.tap(find.text('Walden'));
        await tester.pumpAndSettle();
        expect(find.text('What the web says'), findsOneWidget);
        expect(find.text('Synopsis'), findsOneWidget);
        expect(find.textContaining('A cabin in the woods.'), findsOneWidget);
        // the synopsis and the genres were empty: ticked; the year would replace 1850: not
        expect(find.text('Apply 2'), findsOneWidget);

        await tester.tap(find.text('Year'));
        await tester.pumpAndSettle();
        expect(find.text('Apply 3'), findsOneWidget);
        await tester.tap(find.text('Year'));
        await tester.pumpAndSettle();

        // choose another supplier for the genres
        await tester.tap(find.text('google'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Essays, Nature'), findsOneWidget);

        await tester.tap(find.text('Apply 2'));
        await tester.pumpAndSettle();
        expect(s.calls.last, 'apply 1');
        final sent = s.applied.single;
        expect(sent.type, 'book');
        expect(sent.id, 1);
        expect(sent.set.keys, ['description', 'genres']);
        expect(sent.set['genres'], ['Essays', 'Nature']);
        expect(sent.sources['genres'], 'google');
        expect(sent.sources['description'], 'openlibrary');
        // what the reader was shown as stored goes with it, so a field changed meanwhile is left alone
        expect(sent.expect['description'], '');
        expect(changed, 1);
        expect(find.text('Walden'), findsWidgets);
      },
    );
  });

  group('works saved twice', () {
    testWidgets(
      'are merged into the one kept, which starts as the one with most quotes',
      (tester) async {
        final s = FakeMetadata();
        await open(tester, s);
        await tester.tap(find.text('Saved twice (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Merge 2'));
        await tester.pumpAndSettle();
        expect(find.textContaining('4 quotes · has a cover'), findsOneWidget);
        await tapText(tester, 'Merge');
        expect(s.calls, ['merge book 11 <- 10']);
        expect(find.text('No work looks saved twice.'), findsOneWidget);
      },
    );
  });

  test('values read as words', () {
    expect(valueText(null), '(empty)');
    expect(valueText(''), '(empty)');
    expect(valueText(0), '(empty)');
    expect(valueText(['a', 'b']), 'a, b');
    expect(valueText(<Object?>[]), '(empty)');
    expect(
      valueText([
        {'a': 1},
      ]),
      '1 entries',
    );
    expect(fieldName('published_year'), 'Year');
    expect(fieldName('series_index'), 'Place in the series');
  });
}
