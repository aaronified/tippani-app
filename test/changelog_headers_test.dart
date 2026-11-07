import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/harness/changelog.dart';
import 'package:tippani/harness/changelog_screen.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/harness/version.dart';
import 'package:tippani/settings/settings_store.dart';

void main() {
  group('a change\'s header', () {
    test('a title before a colon is the header', () {
      expect(
        changeHeader(
          'Sync conflicts has its own place: Settings > Sync conflicts, and a badge, where they wait.',
        ),
        'Sync conflicts has its own place',
      );
      expect(
        changeHeader(
          'Look up details (needs your server): when you add or edit a work, it asks the server.',
        ),
        'Look up details (needs your server)',
      );
    });

    test('a short change with no title is shown as it is', () {
      expect(changeHeader('The second new thing.'), 'The second new thing.');
      expect(changeHeader('  A bug.  '), 'A bug.');
    });

    test('a long one is cut at its first sentence', () {
      const text =
          'Deleting now syncs both ways, for quotes and works alike. The rest follows, at length, with many more words so that the whole is over a hundred characters.';
      expect(
        changeHeader(text),
        'Deleting now syncs both ways, for quotes and works alike',
      );
    });

    test('a long one with no early full stop is cut at a hundred characters with an ellipsis', () {
      final text = '${'word ' * 40}and on';
      final h = changeHeader(text);
      expect(h.length, lessThanOrEqualTo(100));
      expect(h, endsWith('…'));
    });

    test('a colon too far in does not make a header of half a sentence', () {
      final text = '${'a ' * 45}: and then more words that go on';
      expect(changeHeader(text), isNot(contains(': and then')));
    });

    test('the details are never in a header', () {
      expect(
        changeHeader(
          'Boards, on the phone: shelves for standalone quotes. Make, rename, colour and delete them.',
        ),
        'Boards, on the phone',
      );
    });
  });

  group('the changelog screen', () {
    const detail =
        'Settle one, some or none whenever you like, and the rest keeps syncing.';
    final entries = [
      ChangelogEntry(
        version: appVersion,
        date: '2026-11-08',
        sections: {
          'Added': [
            'Sync conflicts has its own place: $detail',
            'A short change.',
          ],
        },
      ),
    ];

    Future<List<Uri>> open(WidgetTester tester, {bool opens = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final harness = Harness.fake(store, changelog: entries);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ChangelogScreen(
            harness: harness,
            openLink: (u) async {
              opened.add(u);
              return opens;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('shows each change by its header only', (tester) async {
      await open(tester);
      expect(find.text('• Sync conflicts has its own place'), findsOneWidget);
      expect(find.text('• A short change.'), findsOneWidget);
      expect(find.textContaining('Settle one'), findsNothing);
    });

    testWidgets('has a link to the full changelog on GitHub', (tester) async {
      final opened = await open(tester);
      await tester.scrollUntilVisible(
        find.text('Full changelog on GitHub'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Full changelog on GitHub'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), changelogUrl);
      expect(
        changelogUrl,
        'https://github.com/aaronified/tippani-app/blob/main/CHANGELOG.md',
      );
    });

    testWidgets('a link that cannot be opened is said, not thrown', (
      tester,
    ) async {
      await open(tester, opens: false);
      await tester.scrollUntilVisible(
        find.text('Full changelog on GitHub'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Full changelog on GitHub'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be opened'), findsOneWidget);
    });
  });
}
