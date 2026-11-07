import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/work_screen.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

Future<MemoryLibrary> _open(
  WidgetTester tester, {
  LibrarySection section = LibrarySection.quotes,
  Future<void> Function(MemoryLibrary lib)? seed,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lib = MemoryLibrary();
  if (seed != null) await seed(lib);
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(store: lib, picker: _Picker(), section: section),
    ),
  );
  await tester.pumpAndSettle();
  return lib;
}

Future<void> _longPress(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> three(MemoryLibrary lib) async {
    for (final t in ['One', 'Two', 'Three']) {
      await lib.addQuote(QuoteDraft(text: t));
    }
  }

  testWidgets('a long press starts selecting, a tap adds, close ends it', (
    tester,
  ) async {
    await _open(tester, seed: three);
    expect(find.text('1 selected'), findsNothing);
    await _longPress(tester, 'One');
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    // a tap on a selected one takes it out again
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsNothing);
    expect(find.text('Add a quote'), findsOneWidget);
  });

  testWidgets('recolouring the selected changes only those', (tester) async {
    final lib = await _open(tester, seed: three);
    await _longPress(tester, 'One');
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('blue'));
    await tester.pumpAndSettle();
    final by = {for (final q in await lib.quotes()) q.text: q.color};
    expect(by, {'One': 'blue', 'Two': 'blue', 'Three': 'yellow'});
    expect(find.text('2 recoloured.'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing, reason: 'selecting is over');
  });

  testWidgets('a tag is added to the selected, and star favourites them', (
    tester,
  ) async {
    final lib = await _open(tester, seed: three);
    await _longPress(tester, 'Three');
    await tester.tap(find.byTooltip('Tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wisdom');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect((await lib.quotes()).firstWhere((q) => q.text == 'Three').tags, [
      'wisdom',
    ]);
    await _longPress(tester, 'One');
    await tester.tap(find.byTooltip('Favourite them'));
    await tester.pumpAndSettle();
    expect(
      (await lib.quotes()).firstWhere((q) => q.text == 'One').favorite,
      isTrue,
    );
  });

  testWidgets('delete asks, then Undo brings the quotes back', (tester) async {
    final lib = await _open(tester, seed: three);
    await _longPress(tester, 'One');
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 quotes?'), findsOneWidget);
    await tester.tap(find.text('Keep them'));
    await tester.pumpAndSettle();
    expect(await lib.quotes(), hasLength(3));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await lib.quotes()).map((q) => q.text), ['Three']);
    expect(find.text('2 quotes deleted.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await lib.quotes()).map((q) => q.text).toSet(), {
      'One',
      'Two',
      'Three',
    });
  });

  testWidgets('works are selected too, and merged into one', (tester) async {
    final lib = await _open(
      tester,
      section: LibrarySection.books,
      seed: (lib) async {
        final a = await lib.addWork(const WorkDraft(title: 'Walden'));
        final b = await lib.addWork(const WorkDraft(title: 'Walden (copy)'));
        await lib.addQuote(QuoteDraft(text: 'from a', workId: a.id));
        await lib.addQuote(QuoteDraft(text: 'from b', workId: b.id));
      },
    );
    await _longPress(tester, 'Walden');
    await tester.tap(find.text('Walden (copy)'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Merge into one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walden').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    final works = await lib.works();
    expect(works.map((w) => w.title), ['Walden']);
    expect((await lib.quotes(workId: works.single.id)), hasLength(2));
  });

  testWidgets('a work\'s own page selects its quotes too', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = MemoryLibrary();
    final w = await lib.addWork(const WorkDraft(title: 'Walden'));
    await lib.addQuote(QuoteDraft(text: 'First line', workId: w.id));
    await lib.addQuote(QuoteDraft(text: 'Second line', workId: w.id));
    await tester.pumpWidget(
      MaterialApp(
        home: WorkScreen(store: lib, workId: w.id, picker: _Picker()),
      ),
    );
    await tester.pumpAndSettle();
    await _longPress(tester, 'First line');
    await tester.tap(find.text('Second line'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pink'));
    await tester.pumpAndSettle();
    expect((await lib.quotes()).every((q) => q.color == 'pink'), isTrue);
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('the back button leaves selecting before it leaves the screen', (
    tester,
  ) async {
    await _open(tester, seed: three);
    await _longPress(tester, 'One');
    expect(find.text('1 selected'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('One'), findsOneWidget);
  });
}
