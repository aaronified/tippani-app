import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/anthologies_screen.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/quote_screen.dart';
import 'package:tippani/screens/search_screen.dart';
import 'package:tippani/screens/work_screen.dart';

import '../support/fake_anthologies.dart';
import '../support/fake_sharer.dart';
import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  final saved = <String, Uint8List>{};

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<PickedFile?> pick() async => null;
}

/// Every share in the app is the one screen. Each test starts from a different place a reader can press Share and
/// finds the same screen: the Share title, the Format row, and Share / Copy / Save buttons or the picture's.
void main() {
  late MemoryLibrary lib;
  late FakeSharer sharer;
  late _Picker picker;
  late Work walden;

  setUp(() async {
    lib = MemoryLibrary();
    sharer = FakeSharer();
    picker = _Picker();
    walden = await lib.addWork(
      const WorkDraft(title: 'Walden', creator: 'Thoreau'),
    );
    await lib.addQuote(
      QuoteDraft(text: 'Simplify, simplify.', workId: walden.id),
    );
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sharer.around(MaterialApp(home: home)));
    await tester.pumpAndSettle();
    // a picture being drawn leaves a real-time timer; taking the screen down cancels it
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tapTip(WidgetTester tester, String tip) async {
    await tester.tap(find.byTooltip(tip).first);
    await tester.pumpAndSettle();
  }

  /// The one screen: its title, its format row, and (for words) the text box.
  void expectTheShareScreen() {
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Plain text'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
  }

  String shown(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('a quote', () {
    testWidgets('from its card: the screen, with the picture on offer', (
      tester,
    ) async {
      await show(tester, LibraryScreen(store: lib, picker: picker));
      await tapTip(tester, 'Share');
      expectTheShareScreen();
      expect(find.text('Picture'), findsOneWidget);
      // and nothing went to the sheet behind the reader's back
      expect(sharer.texts, isEmpty);
    });

    testWidgets('from its menu on a search result, which has no Share button', (
      tester,
    ) async {
      await show(tester, SearchScreen(store: lib, picker: picker));
      await tester.enterText(find.byType(TextField).first, 'simplify');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tapTip(tester, 'More for this quote');
      await tester.tap(find.text('Share').last);
      await tester.pumpAndSettle();
      expectTheShareScreen();
      expect(find.text('Picture'), findsOneWidget);
    });

    testWidgets('from the quote page', (tester) async {
      final q = (await lib.quotes()).single;
      await show(
        tester,
        QuoteScreen(store: lib, quoteId: q.id, picker: picker),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expectTheShareScreen();
      expect(find.text('Picture'), findsOneWidget);
    });

    testWidgets('as WhatsApp text: what is sent is what the box shows', (
      tester,
    ) async {
      await show(tester, LibraryScreen(store: lib, picker: picker));
      await tapTip(tester, 'Share');
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      final preview = shown(tester);
      expect(preview, contains('Simplify, simplify.'));
      expect(preview, contains('*Thoreau*'), reason: 'WhatsApp bold');
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(sharer.texts.single, preview);
    });

    testWidgets('and a quote can be saved as a file, Copy beside it', (
      tester,
    ) async {
      await show(tester, LibraryScreen(store: lib, picker: picker));
      await tapTip(tester, 'Share');
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Copy'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(picker.saved.keys.single, endsWith('.md'));
      expect(String.fromCharCodes(picker.saved.values.single), contains('> '));
    });
  });

  group('several quotes', () {
    Future<void> second() => lib.addQuote(
      QuoteDraft(text: 'Time is but the stream.', workId: walden.id),
    );

    testWidgets('a selection of one is a quote, with its picture', (
      tester,
    ) async {
      await show(tester, LibraryScreen(store: lib, picker: picker));
      await tester.longPress(find.text('Simplify, simplify.'));
      await tester.pumpAndSettle();
      await tapTip(tester, 'More');
      await tester.tap(find.text('Share').last);
      await tester.pumpAndSettle();
      expectTheShareScreen();
      expect(find.text('Picture'), findsOneWidget);
    });

    testWidgets('a selection of two is the same screen without the picture', (
      tester,
    ) async {
      await second();
      await show(tester, LibraryScreen(store: lib, picker: picker));
      await tester.longPress(find.text('Simplify, simplify.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time is but the stream.'));
      await tester.pumpAndSettle();
      await tapTip(tester, 'More');
      await tester.tap(find.text('Share').last);
      await tester.pumpAndSettle();
      expectTheShareScreen();
      expect(find.text('Picture'), findsNothing);
      expect(find.text('Tippani quotes · 2 quotes'), findsOneWidget);
      final text = shown(tester);
      expect(text, contains('Simplify, simplify.'));
      expect(text, contains('Time is but the stream.'));
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pumpAndSettle();
      expect(sharer.texts.single, text);
      expect(sharer.subjects.single, 'Tippani quotes');
    });

    testWidgets('a work, from its menu, with its name over its quotes', (
      tester,
    ) async {
      await second();
      await show(
        tester,
        WorkScreen(store: lib, workId: walden.id, picker: picker),
      );
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share').last);
      await tester.pumpAndSettle();
      expectTheShareScreen();
      expect(find.text('Picture'), findsNothing);
      expect(find.text('Walden · 2 quotes'), findsOneWidget);
      expect(shown(tester), startsWith('Walden — Thoreau'));
    });
  });

  group('an anthology', () {
    testWidgets('from its bar: the same screen, offering its documents', (
      tester,
    ) async {
      final service = FakeAnthologies();
      final a = service.seed('Openings', intro: 'First lines.');
      await show(tester, AnthologyScreen(service: service, id: a.id));
      await tapTip(tester, 'Share');
      expectTheShareScreen();
      expect(find.text('EPUB book'), findsOneWidget);
      expect(find.text('Picture'), findsNothing);
      expect(shown(tester), startsWith('Openings\n\nFirst lines.'));
    });
  });
}
