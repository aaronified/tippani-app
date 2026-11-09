import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_widgets.dart';
import 'package:tippani/speech/quote_speech.dart';
import 'package:tippani/speech/speaker.dart';
import 'package:tippani/widgets/edge_fade_row.dart';

class _Voice implements Speaker {
  final said = <String>[];
  var stopped = 0;
  @override
  Future<bool> speak(String text, String language) async {
    said.add(text);
    return true;
  }

  @override
  Future<void> stop() async => stopped++;
  @override
  Future<List<SpeechVoice>> voices() async => const [];
}

Quote _quote({List<String> tags = const []}) => Quote(
  id: 7,
  workId: 1,
  text: 'You\'re gonna need a bigger boat.',
  translation: '',
  language: '',
  speaker: '',
  chapter: '',
  location: '01:12:40',
  note: '',
  color: 'blue',
  favorite: false,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: tags,
);

final _work = Work(
  id: 1,
  kind: WorkKind.film,
  title: 'Jaws',
  creator: 'Steven Spielberg',
  year: 1975,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Widget _tile(Quote q, List<String> shared) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 360,
      child: QuoteTile(
        quote: q,
        work: _work,
        onTap: () {},
        onFavourite: () {},
        share: (t, s) async => shared.add(t),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'the card names the work, the maker and where, and has its actions',
    (tester) async {
      await tester.pumpWidget(_tile(_quote(tags: const ['quotable']), []));
      expect(find.text('Jaws'), findsOneWidget);
      expect(find.text('Steven Spielberg · 01:12:40'), findsOneWidget);
      expect(find.text('#quotable'), findsOneWidget);
      for (final tip in [
        'Copy',
        'Read aloud',
        'Share',
        'More for this quote',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
    },
  );

  testWidgets('Speak reads the quote and the same button stops it', (
    tester,
  ) async {
    final voice = _Voice();
    QuoteSpeech.instance = QuoteSpeech(voice);
    await tester.pumpWidget(_tile(_quote(), []));
    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    expect(voice.said, ['You\'re gonna need a bigger boat.']);
  });

  testWidgets('Share hands over the quote with its credit', (tester) async {
    final shared = <String>[];
    await tester.pumpWidget(_tile(_quote(), shared));
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(shared.single, contains('bigger boat'));
    expect(shared.single, contains('Jaws'));
  });

  testWidgets('a long run of tags scrolls and fades at the edge it runs past', (
    tester,
  ) async {
    final tags = [for (var i = 0; i < 20; i++) 'tag number $i'];
    await tester.pumpWidget(_tile(_quote(tags: tags), []));
    await tester.pump();
    await tester.pump();
    final fade = tester.widget<ShaderMask>(
      find.descendant(
        of: find.byType(EdgeFadeRow),
        matching: find.byType(ShaderMask),
      ),
    );
    expect(fade, isNotNull);
    final scroll = find.descendant(
      of: find.byType(EdgeFadeRow),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: scroll, matching: find.byType(Scrollable)),
          )
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    await tester.drag(scroll, const Offset(-200, 0));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: scroll, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      greaterThan(0),
    );
  });
}
