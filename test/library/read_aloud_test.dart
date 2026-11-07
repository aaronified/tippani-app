import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/quote_screen.dart';
import 'package:tippani/screens/work_read_screen.dart';
import 'package:tippani/speech/speaker.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<PickedFile?> pick() async => null;
}

/// Says nothing; records what it was asked, and holds each utterance open until the test finishes it.
class FakeSpeaker implements Speaker {
  final said = <(String, String)>[];
  final _open = <Completer<void>>[];
  bool hasVoice = true;
  bool boom = false;
  int stops = 0;

  @override
  Future<bool> speak(String text, String language) async {
    if (boom) throw Exception('engine gone');
    if (!hasVoice) return false;
    said.add((text, language));
    final c = Completer<void>();
    _open.add(c);
    await c.future;
    return true;
  }

  void finish() => _open.removeAt(0).complete();

  @override
  Future<List<SpeechVoice>> voices() async => const [];

  @override
  Future<void> stop() async {
    stops++;
    for (final c in _open) {
      c.complete();
    }
    _open.clear();
  }
}

Work work(String language) => Work(
  id: 1,
  kind: WorkKind.book,
  title: 'Walden',
  creator: '',
  year: null,
  language: language,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Quote quote(int id, String text, {String language = ''}) => Quote(
  id: id,
  workId: 1,
  text: text,
  translation: '',
  language: language,
  speaker: '',
  chapter: '',
  location: '',
  note: '',
  color: 'yellow',
  favorite: false,
  notedAt: DateTime.utc(2026, 1, id),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: const [],
);

void main() {
  testWidgets(
    'the quote screen reads the quote in its own language, and Stop ends it',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = MemoryLibrary();
      final w = await lib.addWork(
        const WorkDraft(title: 'Walden', language: 'en'),
      );
      final q = await lib.addQuote(
        QuoteDraft(text: 'namaste', workId: w.id, language: 'hi'),
      );
      final fake = FakeSpeaker();
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteScreen(
            store: lib,
            quoteId: q.id,
            picker: _Picker(),
            speaker: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read aloud'));
      await tester.pump();
      expect(fake.said.single, ('namaste', 'hi'));
      expect(find.text('Stop'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Read aloud'), findsOneWidget);
      expect(fake.stops, greaterThan(0));
    },
  );

  testWidgets(
    'a quote with no language uses its work\'s; no voice is said in words',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final lib = MemoryLibrary();
      final w = await lib.addWork(
        const WorkDraft(title: 'Walden', language: 'fr'),
      );
      final q = await lib.addQuote(QuoteDraft(text: 'bonjour', workId: w.id));
      final fake = FakeSpeaker()..hasVoice = false;
      await tester.pumpWidget(
        MaterialApp(
          home: QuoteScreen(
            store: lib,
            quoteId: q.id,
            picker: _Picker(),
            speaker: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read aloud'));
      await tester.pumpAndSettle();
      expect(find.text('This phone has no voice for "fr".'), findsOneWidget);
      expect(find.text('Read aloud'), findsOneWidget);
    },
  );

  testWidgets('a failing engine is said, not thrown', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = MemoryLibrary();
    final q = await lib.addQuote(const QuoteDraft(text: 'x'));
    final fake = FakeSpeaker()..boom = true;
    await tester.pumpWidget(
      MaterialApp(
        home: QuoteScreen(
          store: lib,
          quoteId: q.id,
          picker: _Picker(),
          speaker: fake,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pumpAndSettle();
    expect(find.text('The quote could not be read aloud.'), findsOneWidget);
  });

  group('the Read screen', () {
    Future<FakeSpeaker> open(WidgetTester tester) async {
      final fake = FakeSpeaker();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkReadScreen(
            work: work('en'),
            quotes: [
              quote(1, 'one'),
              quote(2, 'two', language: 'hi'),
              quote(3, 'three'),
            ],
            speaker: fake,
          ),
        ),
      );
      return fake;
    }

    testWidgets('reads every quote in turn, then goes back to Read aloud', (
      tester,
    ) async {
      final fake = await open(tester);
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      expect(fake.said, [('one', 'en')]);
      fake.finish();
      await tester.pump();
      expect(fake.said.last, ('two', 'hi'));
      fake.finish();
      await tester.pump();
      expect(fake.said.last, ('three', 'en'));
      fake.finish();
      await tester.pumpAndSettle();
      expect(fake.said.length, 3);
      expect(find.byTooltip('Read aloud'), findsOneWidget);
    });

    testWidgets('stopping part-way does not go on to the next quote', (
      tester,
    ) async {
      final fake = await open(tester);
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      await tester.tap(find.byTooltip('Stop reading'));
      await tester.pumpAndSettle();
      expect(fake.said.length, 1);
      expect(find.byTooltip('Read aloud'), findsOneWidget);
    });
  });
}
