import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/source_files_screen.dart';
import 'package:tippani/sources/source_picker.dart';
import 'package:tippani/sources/sources_service.dart';

import '../support/fake_sources.dart';
import '../support/memory_library.dart';

Future<({FakeSources sources, FakeSourcePicker picker, MemoryLibrary library})>
open(
  WidgetTester tester, {
  void Function(FakeSources s)? setup,
  Future<void> Function(MemoryLibrary l)? seed,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final library = MemoryLibrary();
  // two works that are on the server (server ids 11 and 12), and one that is not
  final walden = await library.addWork(
    const WorkDraft(title: 'Walden', creator: 'Thoreau'),
  );
  final film = await library.addWork(
    const WorkDraft(title: 'Casablanca', kind: WorkKind.film),
  );
  await library.addWork(const WorkDraft(title: 'Unsynced', creator: 'Nobody'));
  await library.setWorkServerId(walden.id, 11);
  await library.setWorkServerId(film.id, 12);
  if (seed != null) await seed(library);
  final sources = FakeSources();
  setup?.call(sources);
  final picker = FakeSourcePicker();
  await tester.pumpWidget(
    MaterialApp(
      home: SourceFilesScreen(
        service: sources,
        library: library,
        picker: picker,
        pollEvery: const Duration(milliseconds: 50),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (sources: sources, picker: picker, library: library);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  group('attached files', () {
    testWidgets('shows each file under its work, and the state it is in', (
      tester,
    ) async {
      await open(
        tester,
        setup: (s) => s.attachedList = const [
          AttachedSource(
            id: 1,
            subject: 'book',
            workId: 11,
            name: 'walden.epub',
            format: 'epub',
            bytes: 3 * 1024 * 1024,
            origin: 'upload',
            state: 'file',
            withContext: 4,
          ),
          AttachedSource(
            id: 2,
            subject: 'screen',
            workId: 12,
            name: 'casablanca.srt',
            format: 'srt',
            origin: 'mount',
            state: 'missing',
          ),
        ],
      );
      expect(find.text('Attached (2)'), findsOneWidget);
      expect(find.text('Walden'), findsOneWidget);
      expect(find.textContaining('3.0 MB · uploaded'), findsOneWidget);
      expect(find.textContaining('4 quotes with surroundings'), findsOneWidget);
      expect(find.text('Casablanca'), findsOneWidget);
      expect(find.textContaining('missing on the server'), findsOneWidget);
    });

    testWidgets('read again, free the space (after a preview) and remove', (
      tester,
    ) async {
      final r = await open(
        tester,
        setup: (s) => s.attachedList = const [
          AttachedSource(
            id: 1,
            subject: 'book',
            workId: 11,
            name: 'walden.epub',
            format: 'epub',
            bytes: 3 * 1024 * 1024,
            origin: 'upload',
            state: 'file',
          ),
        ],
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read it again'));
      await tester.pumpAndSettle();
      expect(r.sources.calls, ['rescan 1']);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Free the space'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2.0 MB'), findsOneWidget);
      expect(
        find.textContaining('3 quotes keep its surroundings'),
        findsOneWidget,
      );
      await tapText(tester, 'Free the space');
      expect(r.sources.calls.last, 'prune 1');

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove the file'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Remove');
      expect(r.sources.calls.last, 'remove 1');
      expect(find.text('Attached (0)'), findsOneWidget);
    });

    testWidgets('a mounted file offers no pruning', (tester) async {
      await open(
        tester,
        setup: (s) => s.attachedList = const [
          AttachedSource(
            id: 2,
            subject: 'screen',
            workId: 12,
            name: 'c.srt',
            origin: 'mount',
            state: 'mounted',
          ),
        ],
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Free the space'), findsNothing);
      expect(find.text('Read it again'), findsOneWidget);
    });
  });

  group('found files', () {
    FoundFile found(String token, String bucket, String title) => FoundFile(
      token: token,
      rel: 'films/$title.srt',
      format: 'srt',
      subject: 'screen',
      workId: 12,
      title: title,
      how: bucket == 'exact' ? 'id' : 'title',
      bucket: bucket,
    );

    testWidgets('a scan runs, then exact matches attach in one press', (
      tester,
    ) async {
      final r = await open(
        tester,
        setup: (s) => s.foundList = [
          found('t1', 'exact', 'Casablanca'),
          found('t2', 'exact', 'Walden film'),
          found('t3', 'review', 'Maybe this'),
        ],
      );
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Exact matches (2)'), findsOneWidget);
      expect(find.text('To look over (1)'), findsOneWidget);

      await tester.tap(find.text('Scan'));
      await tester.pump();
      expect(r.sources.calls, ['scan books']);
      expect(find.textContaining('Looking…'), findsOneWidget);
      // the screen asks again on a timer and sees the scan finished
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('10 files read, 2 fit a work'),
        findsOneWidget,
      );

      await tester.tap(find.text('Attach all'));
      await tester.pumpAndSettle();
      expect(r.sources.calls.last, 'attachFound exact t1,t2');
      expect(find.textContaining('2 attached'), findsOneWidget);
    });

    testWidgets('a proposal is attached or turned down on its own', (
      tester,
    ) async {
      final r = await open(
        tester,
        setup: (s) => s.foundList = [
          found('t3', 'review', 'Maybe this'),
          found('t4', 'review', 'And this'),
        ],
      );
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attach').first);
      await tester.pumpAndSettle();
      expect(r.sources.calls.last, 'attachFound review t3');
      await tester.tap(find.text('Not this one'));
      await tester.pumpAndSettle();
      expect(r.sources.calls.last, 'ignoreFound t4');
      expect(find.text('Attach'), findsNothing);
    });

    testWidgets('the server\'s refusal is shown', (tester) async {
      final r = await open(
        tester,
        setup: (s) => s.foundList = [found('t3', 'review', 'Maybe this')],
      );
      r.sources.refuse = 'this work already has a file';
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attach').first);
      await tester.pumpAndSettle();
      expect(find.text('this work already has a file'), findsOneWidget);
    });

    testWidgets('without a folder on the server it says so', (tester) async {
      await open(tester, setup: (s) => s.mountList = const []);
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.textContaining('no folder to look in'), findsOneWidget);
    });
  });

  group('adding by hand', () {
    testWidgets('a file from the phone goes to the work chosen', (
      tester,
    ) async {
      final r = await open(tester);
      r.picker.file = SourceFile('walden.epub', Uint8List.fromList([1, 2]));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From this phone'));
      await tester.pumpAndSettle();
      // only works that are on the server are offered
      expect(find.text('Unsynced'), findsNothing);
      await tester.tap(find.text('Walden').last);
      await tester.pumpAndSettle();
      expect(r.sources.calls, ['upload walden.epub book 11 ']);
      expect(find.text('Attached (0)'), findsOneWidget);
    });

    testWidgets('a file that is too big is refused before it is sent', (
      tester,
    ) async {
      final r = await open(tester);
      r.picker.tooBig = true;
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From this phone'));
      await tester.pumpAndSettle();
      expect(find.textContaining('over 25 MB'), findsOneWidget);
      expect(r.sources.calls, isEmpty);
    });

    testWidgets('a file is chosen by walking the server\'s folders', (
      tester,
    ) async {
      final r = await open(
        tester,
        setup: (s) => s.folders = {
          '': const [
            FolderEntry(name: 'films', rel: 'films', dir: true),
            FolderEntry(name: 'readme.txt', rel: 'readme.txt', dir: false),
          ],
          'films': const [
            FolderEntry(
              name: 'casablanca.srt',
              rel: 'films/casablanca.srt',
              dir: false,
              size: 52000,
            ),
          ],
        },
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From a folder on the server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('films'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('casablanca.srt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Casablanca').last);
      await tester.pumpAndSettle();
      expect(r.sources.calls, [
        'attachMounted books films/casablanca.srt screen 12 ',
      ]);
    });
  });
}
