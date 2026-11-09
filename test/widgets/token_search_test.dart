import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/widgets/token_search.dart';

const _sources = SearchSources(
  tags: ['sea', 'search', 'life'],
  people: ['Herman Melville', 'Jane Austen'],
  works: ['Moby-Dick', 'Walden'],
);

void main() {
  group('taking a search apart', () {
    test('free words and tokens are told apart', () {
      final q = parseSearch('whale tag:sea by:"Herman Melville" in:Moby-Dick');
      expect(q.text, 'whale');
      expect(q.tag, 'sea');
      expect(q.by, 'Herman Melville');
      expect(q.inWork, 'Moby-Dick');
    });

    test('words around a token keep their order, and a token with no value is ignored', () {
      expect(parseSearch('call tag:sea me by:').text, 'call me');
      expect(parseSearch('call tag:sea me by:').by, isNull);
      expect(parseSearch('').isEmpty, isTrue);
    });

    test('the last of a repeated token wins, and the key may be any case', () {
      expect(parseSearch('tag:a TAG:b').tag, 'b');
    });
  });

  group('suggesting', () {
    List<String> shown(String raw) => [
      for (final s in suggestFor(raw, _sources)) s.value ?? '${s.key}:',
    ];

    test('the start of a key offers the keys', () {
      expect(shown('whale t'), ['tag:']);
      expect(shown('b'), ['by:']);
      expect(shown('i'), ['in:']);
      expect(shown(''), isEmpty);
    });

    test('a token being typed offers its values, best match first', () {
      expect(shown('tag:se'), ['sea', 'search']);
      expect(shown('by:mel'), ['Herman Melville']);
      expect(shown('in:wal'), ['Walden']);
    });

    test('a value typed in full leaves nothing to suggest', () {
      expect(shown('tag:life'), isEmpty);
    });

    test(
      'a value with spaces is quoted when chosen, and replaces the typing',
      () {
        final s = suggestFor('hello by:aus', _sources).single;
        expect(s.token, 'by:"Jane Austen"');
        expect(applySuggestion('hello by:aus', s), 'hello by:"Jane Austen" ');
        final k = suggestFor('hello t', _sources).single;
        expect(applySuggestion('hello t', k), 'hello tag:');
      },
    );
  });

  testWidgets(
    'the box suggests tokens as you type, and choosing one fills it in',
    (tester) async {
      final c = TextEditingController();
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: TokenSearchField(
                controller: c,
                hintText: 'Search',
                sources: () => _sources,
                onChanged: () => changes++,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'tag:se');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'sea'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'search'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'sea'));
      await tester.pumpAndSettle();
      expect(c.text, 'tag:sea ');
      expect(changes, greaterThan(0));
    },
  );
}
