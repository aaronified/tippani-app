import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/checks/checks_service.dart';
import 'package:tippani/imports/import_picker.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/screens/checks_screen.dart';
import 'package:tippani/screens/staging_screen.dart';

import '../support/fake_checks.dart';
import '../support/memory_library.dart';

Future<void> _open(
  WidgetTester tester, {
  FakeImports? imports,
  FakeChecks? checks,
  MemoryLibrary? library,
  FakePicker? picker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChecksScreen(
        imports: imports,
        checks: checks,
        library: library,
        picker: picker ?? FakePicker(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Staging _queue() => const Staging(
  pending: 2,
  total: 2,
  batches: [
    StagedBatch(
      id: 1,
      source: 'kindle_clippings',
      filename: 'My Clippings.txt',
      works: 1,
      quotes: 2,
    ),
  ],
  works: [
    StagedWork(
      id: 4,
      batchId: 1,
      kind: 'book',
      title: 'Walden',
      author: 'Thoreau',
      year: 1854,
      quotes: 2,
      targetId: 0,
      targetTitle: '',
      targetYear: 0,
      ambiguous: false,
      pinned: false,
    ),
  ],
  quotes: [
    StagedQuote(
      id: 11,
      workId: 4,
      text: 'Simplify, simplify.',
      note: '',
      translation: '',
      color: 'yellow',
      favorite: false,
      chapter: '',
      location: 'p.8',
      character: '',
      actor: '',
      timestamp: '',
      tags: [],
    ),
    StagedQuote(
      id: 12,
      workId: 4,
      text: 'The mass of men.',
      note: 'mine',
      translation: '',
      color: 'blue',
      favorite: true,
      chapter: '',
      location: 'p.9',
      character: '',
      actor: '',
      timestamp: '',
      tags: ['life'],
    ),
  ],
);

CleanupScan _marks() => const CleanupScan(
  rules: ['double-space', 'edge-space'],
  open: 1,
  ignored: 0,
  truncated: false,
  items: [
    CleanupItem(
      kind: 'book',
      id: 5,
      workId: 2,
      workTitle: 'Walden',
      findings: [
        CleanupFinding(
          rule: 'double-space',
          field: 'quote',
          snippet: 'Simplify,«  »simplify.',
          afterSnippet: 'Simplify,« »simplify.',
          count: 1,
          hash: 'abc',
          ignored: false,
        ),
      ],
    ),
  ],
);

Correction _correction({bool edited = false}) => Correction(
  kind: 'book',
  id: 8,
  workId: 2,
  workTitle: 'Walden',
  quote: 'I went to the woods',
  proposed: 'I went to the woods,',
  from: '',
  to: ',',
  bucket: 'punctuation',
  edited: edited,
);

LocatorProposal _locator({String bucket = 'exact'}) => LocatorProposal(
  kind: 'dialogue',
  id: 3,
  quote: 'Play it again.',
  workId: 1,
  workTitle: 'Casablanca',
  season: 0,
  episode: 0,
  current: '',
  currentEnd: '',
  proposed: '00:41:10',
  proposedEnd: '',
  evidence: 'Play it, Sam.',
  bucket: bucket,
  currentChapter: '',
  proposedChapter: '',
);

void main() {
  group('the checks screen', () {
    testWidgets('names each tab with what waits in it', (tester) async {
      final imports = FakeImports()..staging = _queue();
      final checks = FakeChecks()
        ..count = const CheckCounts(strayMarks: 4, corrections: 3, locators: 7);
      await _open(tester, imports: imports, checks: checks);

      expect(find.text('Imports'), findsOneWidget);
      expect(find.text('Stray marks'), findsOneWidget);
      expect(find.text('Corrections'), findsOneWidget);
      expect(find.text('Times and places'), findsOneWidget);
      expect(find.widgetWithText(Badge, '2'), findsOneWidget);
      expect(find.widgetWithText(Badge, '3'), findsOneWidget);
      expect(find.widgetWithText(Badge, '4'), findsOneWidget);
      expect(find.widgetWithText(Badge, '7'), findsOneWidget);
    });

    testWidgets('with no server only the local Markdown import is offered', (
      tester,
    ) async {
      final library = MemoryLibrary();
      await _open(
        tester,
        imports: FakeImports(available: false),
        library: library,
      );

      expect(find.text('Import a file'), findsNothing);
      expect(
        find.text('Importing to a server needs a paired server'),
        findsOneWidget,
      );
      expect(find.text('Import Markdown into this phone'), findsOneWidget);
      expect(find.text('Stray marks'), findsNothing);
    });
  });

  group('importing', () {
    testWidgets('a chosen file is sent and the outcome said in words', (
      tester,
    ) async {
      final imports = FakeImports();
      final picker = FakePicker()
        ..next = ImportFile('My Clippings.txt', Uint8List(3));
      await _open(tester, imports: imports, picker: picker);

      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();

      expect(imports.imported, [('My Clippings.txt', null)]);
      expect(
        find.textContaining('Read as My Clippings. 2 quotes from 1 work'),
        findsOneWidget,
      );
    });

    testWidgets('a file nothing claims lets the reader name its format', (
      tester,
    ) async {
      final imports = FakeImports()
        ..outcome = const ImportOutcome(
          ok: false,
          message: 'Nothing in this file says what it is.',
          unknownFormat: true,
        );
      final picker = FakePicker()..next = ImportFile('q.html', Uint8List(3));
      await _open(tester, imports: imports, picker: picker);
      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();
      expect(find.text('Read this as…'), findsOneWidget);

      imports.outcome = const ImportOutcome(
        ok: true,
        source: 'goodreads_html',
        staged: 4,
        works: 1,
        pending: 4,
      );
      await tester.tap(find.text('Read this as…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goodreads').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read it'));
      await tester.pumpAndSettle();

      expect(imports.imported.last, ('q.html', 'goodreads-html'));
      expect(find.textContaining('Read as Goodreads'), findsOneWidget);
      expect(find.text('Read this as…'), findsNothing);
    });

    testWidgets('a file over the limit is refused before it is sent', (
      tester,
    ) async {
      final imports = FakeImports();
      final picker = FakePicker()..tooBig = true;
      await _open(tester, imports: imports, picker: picker);
      await tester.tap(find.text('Choose a file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('over 5 MB'), findsOneWidget);
      expect(imports.imported, isEmpty);
    });

    testWidgets('a Markdown file goes straight into this phone', (
      tester,
    ) async {
      final library = MemoryLibrary();
      final md = utf8.encode(
        '---\ntitle: Walden\nauthor: Thoreau\ntype: book\n---\n\n> Simplify.\n',
      );
      final picker = FakePicker()
        ..next = ImportFile('mine.md', Uint8List.fromList(md));
      await _open(
        tester,
        imports: FakeImports(available: false),
        library: library,
        picker: picker,
      );

      await tester.tap(find.text('Choose a Markdown file'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Added 1 quote and 1 new work'),
        findsOneWidget,
      );
      expect((await library.quotes()).single.text, 'Simplify.');
      expect(picker.asked.single, ['md', 'markdown', 'txt']);
    });

    testWidgets('a file that is not Markdown says why', (tester) async {
      final picker = FakePicker()
        ..next = ImportFile('x.md', Uint8List.fromList(utf8.encode('hello')));
      await _open(
        tester,
        imports: FakeImports(available: false),
        library: MemoryLibrary(),
        picker: picker,
      );
      await tester.tap(find.text('Choose a Markdown file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not Tippani Markdown'), findsOneWidget);
    });

    testWidgets('each format lists its steps', (tester) async {
      // a tall screen, so the whole page is built and nothing is below the fold
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, imports: FakeImports());
      await tester.tap(find.text('How to get a file from…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Clippings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Plug the Kindle in by USB'), findsOneWidget);
      expect(find.textContaining('undocumented'), findsOneWidget);
    });
  });

  group('the queue', () {
    Future<(FakeImports, List<int>)> open(WidgetTester tester) async {
      final imports = FakeImports()..staging = _queue();
      final pulled = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StagingScreen(
            service: imports,
            onApproved: () async => pulled.add(1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (imports, pulled);
    }

    testWidgets('shows where each group will go and its quotes', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Walden'), findsOneWidget);
      expect(find.text('Will be added as a new book'), findsOneWidget);
      expect(find.text('Simplify, simplify.'), findsOneWidget);
      expect(find.text('2 quotes waiting'), findsOneWidget);
    });

    testWidgets('approving the selected quotes sends them and then pulls', (
      tester,
    ) async {
      final (imports, pulled) = await open(tester);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Approve 1'));
      await tester.pumpAndSettle();

      expect(imports.approved.single.ids, [11]);
      expect(pulled, [1]);
      expect(find.text('1 added'), findsOneWidget);
    });

    testWidgets('a whole group is selected from its checkbox', (tester) async {
      final (imports, _) = await open(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(imports.discarded.single.ids, [11, 12]);
    });

    testWidgets('a colour is set on the selection', (tester) async {
      final (imports, _) = await open(tester);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Make it pink'));
      await tester.pumpAndSettle();
      expect(imports.edits.single.$1.ids, [11]);
      expect(imports.edits.single.$2.color, 'pink');
    });

    testWidgets('a quote is edited from its row', (tester) async {
      final (imports, _) = await open(tester);
      await tester.tap(find.text('Simplify, simplify.'));
      await tester.pumpAndSettle();
      expect(find.text('Edit staged quote'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Chapter'),
        'Economy',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(imports.edits.single.$1.ids, [11]);
      expect(imports.edits.single.$2.chapter, 'Economy');
      expect(imports.edits.single.$2.location, isNull);
    });

    testWidgets('a group is moved onto a book in the library', (tester) async {
      final imports = FakeImports()
        ..staging = _queue()
        ..places = const [WorkChoice('book', 9, 'Walden', 1854, 'Thoreau')];
      await tester.pumpWidget(
        MaterialApp(home: StagingScreen(service: imports)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('This group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to another work…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thoreau · 1854').last);
      await tester.pumpAndSettle();

      expect(imports.moves.single.$2!.id, 9);
      expect(imports.moves.single.$1.workIds, [4]);
    });

    testWidgets('an empty queue says so', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StagingScreen(service: FakeImports())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing waiting.'), findsOneWidget);
    });

    testWidgets('a refused approval is said and the queue is kept', (
      tester,
    ) async {
      final imports = FakeImports()
        ..staging = _queue()
        ..approval = const ApprovalOutcome(ok: false, message: 'Disk is full.');
      await tester.pumpWidget(
        MaterialApp(home: StagingScreen(service: imports)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve 1'));
      await tester.pumpAndSettle();
      expect(find.text('Disk is full.'), findsOneWidget);
      expect(find.text('Simplify, simplify.'), findsOneWidget);
    });
  });

  group('stray marks', () {
    testWidgets('a mark is shown, fixed, and the phone pulls', (tester) async {
      final checks = FakeChecks()
        ..scan = _marks()
        ..count = const CheckCounts(strayMarks: 1);
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Stray marks'));
      await tester.pumpAndSettle();

      expect(find.text('Double spaces · Quote'), findsOneWidget);
      expect(find.text('Walden'), findsOneWidget);
      await tester.tap(find.text('Fix'));
      await tester.pumpAndSettle();

      expect(checks.accepted.single.single.finding.rule, 'double-space');
      expect(find.text('Updated 1 quote'), findsOneWidget);
    });

    testWidgets('a mark can be ignored instead', (tester) async {
      final checks = FakeChecks()..scan = _marks();
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Stray marks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();
      expect(checks.ignoredTargets.single.$2, isTrue);
      expect(find.text('Ignored 1'), findsOneWidget);
    });

    testWidgets('nothing found says so', (tester) async {
      await _open(tester, checks: FakeChecks(), imports: FakeImports());
      await tester.tap(find.text('Stray marks'));
      await tester.pumpAndSettle();
      expect(find.text('No stray marks.'), findsOneWidget);
    });
  });

  group('corrections', () {
    testWidgets('the file’s words are offered and can be used', (tester) async {
      final checks = FakeChecks()
        ..corrected = CorrectionsScan(
          proposals: [_correction()],
          wrongFile: const [],
        );
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Corrections'));
      await tester.pumpAndSettle();

      expect(find.text('Punctuation and quote marks'), findsWidgets);
      expect(find.textContaining('I went to the woods'), findsWidgets);
      await tester.tap(find.text('Use the file’s'));
      await tester.pumpAndSettle();

      final sent = checks.correctionsAccepted.single;
      expect(sent.$1, 'punctuation');
      expect(sent.$2.single.id, 8);
      expect(sent.$3, isFalse);
    });

    testWidgets('accepting a whole bucket asks first and goes in bulk', (
      tester,
    ) async {
      final checks = FakeChecks()
        ..corrected = CorrectionsScan(
          proposals: [_correction(), _correction(edited: true)],
          wrongFile: const [],
        );
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Corrections'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept all 2'));
      await tester.pumpAndSettle();
      expect(find.text('Accept all 2?'), findsOneWidget);
      expect(find.textContaining('1 you edited yourself'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept all'));
      await tester.pumpAndSettle();

      expect(checks.correctionsAccepted.single.$3, isTrue);
      expect(checks.correctionsAccepted.single.$2, hasLength(2));
    });

    testWidgets('a work whose file is probably the wrong one is called out', (
      tester,
    ) async {
      final checks = FakeChecks()
        ..corrected = CorrectionsScan(
          proposals: const [],
          wrongFile: const [WrongFile('book', 2, 'Walden', 9, 10)],
        );
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Corrections'));
      await tester.pumpAndSettle();
      expect(find.textContaining('9 of 10 quotes differ'), findsOneWidget);
    });
  });

  group('times and places', () {
    testWidgets('a proposed time can be taken or ignored', (tester) async {
      final checks = FakeChecks()..located = [_locator()];
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Times and places'));
      await tester.pumpAndSettle();

      expect(find.text('Exact matches (1)'), findsOneWidget);
      expect(find.textContaining('00:41:10'), findsOneWidget);
      await tester.tap(find.text('Use this time'));
      await tester.pumpAndSettle();

      expect(checks.locatorsAccepted.single.$1, 'exact');
      expect(checks.locatorsAccepted.single.$2.single.proposed, '00:41:10');
    });

    testWidgets('a near match shows what the file said', (tester) async {
      final checks = FakeChecks()..located = [_locator(bucket: 'review')];
      await _open(tester, checks: checks, imports: FakeImports());
      await tester.tap(find.text('Times and places'));
      await tester.pumpAndSettle();
      expect(find.text('Worth a look (1)'), findsOneWidget);
      expect(find.textContaining('Play it, Sam.'), findsOneWidget);
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();
      expect(checks.locatorsIgnored, hasLength(1));
    });
  });

  testWidgets('a server that cannot be read says so and can be retried', (
    tester,
  ) async {
    final checks = FakeChecks()..fail = const ServerException('Down.');
    await _open(tester, checks: checks, imports: FakeImports());
    await tester.tap(find.text('Stray marks'));
    await tester.pumpAndSettle();
    expect(find.text('Down.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
