import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/capture/photo_source.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/cover_cache.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/work_screen.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';
import '../support/memory_library.dart';

// a real 1x1 PNG
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
const name = '0123456789abcdef.png';

class Rig {
  Rig(this.server, this.controller, this.cache, this.dir, this.clock);
  final FakeServer server;
  final AppController controller;
  final CoverCache cache;
  final Directory dir;
  final Clock clock;
}

class Clock {
  DateTime now = DateTime.utc(2026, 11, 7, 12);
  DateTime call() => now;
}

Future<Rig> rig({bool paired = true}) async {
  SharedPreferences.setMockInitialValues({
    'server_url': 'https://q.example.org',
  });
  final server = FakeServer();
  final controller = AppController(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    clientFactory: server.factory,
  );
  await controller.load();
  if (paired) await controller.pair('ABCD2345', 'My phone');
  final dir = await Directory.systemTemp.createTemp('tippani_covers');
  addTearDown(() => dir.delete(recursive: true));
  final clock = Clock();
  return Rig(
    server,
    controller,
    CoverCache(
      controller,
      folder: Directory('${dir.path}/covers'),
      clock: clock.call,
    ),
    dir,
    clock,
  );
}

Work work({
  int? serverId = 3,
  WorkKind kind = WorkKind.book,
  String cover = '',
}) => Work(
  id: 1,
  kind: kind,
  title: 'Walden',
  creator: '',
  year: null,
  language: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  serverId: serverId,
  cover: cover,
);

void main() {
  group('fetching a cover', () {
    test(
      'is fetched once, kept on the phone, and read from there after',
      () async {
        final r = await rig();
        r.server.covers[name] = png;

        final a = await r.cache.fileFor(name);
        final b = await r.cache.fileFor(name);

        expect(a, isNotNull);
        expect(await a!.readAsBytes(), png);
        expect(b!.path, a.path);
        expect(r.server.coverReads, [name]);
        expect(
          Directory('${r.dir.path}/covers')
              .listSync()
              .map((e) => e.path.split(RegExp(r'[\\/]')).last),
          [name],
          reason: 'no half-written file is left behind',
        );
      },
    );

    test('a picture chosen on the phone is kept under a server-shaped name and drawn without the server', () async {
      final r = await rig(paired: false);
      final kept = await r.cache.keepLocal(png, 'My Photo.PNG');
      expect(kept, matches(coverName));
      expect(kept, endsWith('.png'));
      expect(await r.cache.kept(kept), isTrue);
      final file = await r.cache.fileFor(kept);
      expect(await file!.readAsBytes(), png);
      expect(r.server.coverReads, isEmpty);
      expect(await r.cache.keepLocal(png, 'noextension'), endsWith('.jpg'));
    });

    test('two askers at once share one request', () async {
      final r = await rig();
      r.server.covers[name] = png;
      await Future.wait([r.cache.fileFor(name), r.cache.fileFor(name)]);
      expect(r.server.coverReads, hasLength(1));
    });

    test(
      'a name that is not one of the server\'s own is never fetched',
      () async {
        final r = await rig();
        for (final bad in [
          '../secret.png',
          'ABCDEF0123456789.png',
          'cover.png',
          '0123456789abcdef.exe',
          '',
          '0123456789abcdef.png/../x',
        ]) {
          expect(await r.cache.fileFor(bad), isNull, reason: bad);
        }
        expect(r.server.coverReads, isEmpty);
      },
    );

    test('a cover the server does not have, or cannot give, is nothing, and is not asked for again at once', () async {
      final r = await rig();
      expect(await r.cache.fileFor(name), isNull);
      expect(await r.cache.fileFor(name), isNull);
      expect(r.server.coverReads, hasLength(1));

      r.clock.now = r.clock.now.add(const Duration(minutes: 3));
      r.server.covers[name] = png;
      expect(await r.cache.fileFor(name), isNotNull);
      expect(r.server.coverReads, hasLength(2));
    });

    test('with no server paired, nothing is fetched', () async {
      final r = await rig(paired: false);
      expect(await r.cache.fileFor(name), isNull);
      expect(r.server.coverReads, isEmpty);
    });
  });

  group('choosing a cover', () {
    test(
      'sends the picture as a form and returns the name the server gave it',
      () async {
        final r = await rig();
        r.server.seed('/books', {'title': 'Walden', 'author': 'T'}, id: 3);

        final got = await r.cache.upload(
          work(),
          Uint8List.fromList(png),
          'me.png',
        );

        expect(got, isNotNull);
        expect(r.server.coverUploads, ['/books/3/cover']);
        expect(r.server.covers[got], isNotNull);
      },
    );

    test('a film\'s picture is its poster', () async {
      final r = await rig();
      r.server.seed('/movies', {'title': 'Casablanca', 'director': 'C'}, id: 4);
      final got = await r.cache.upload(
        work(serverId: 4, kind: WorkKind.film),
        Uint8List.fromList(png),
        'me.png',
      );
      expect(got, isNotNull);
      expect(r.server.coverUploads, ['/movies/4/cover']);
    });

    test('a work not on the server yet has nowhere to put one', () async {
      final r = await rig();
      expect(
        await r.cache.upload(
          work(serverId: null),
          Uint8List.fromList(png),
          'a.png',
        ),
        isNull,
      );
      expect(r.server.coverUploads, isEmpty);
    });

    test('a refusal is nothing, not an error', () async {
      final r = await rig();
      r.server.seed('/books', {'title': 'Walden', 'author': 'T'}, id: 3);
      r.server.failCoversWith = 400;
      expect(
        await r.cache.upload(work(), Uint8List.fromList(png), 'a.png'),
        isNull,
      );
    });
  });

  group('showing it', () {
    late Directory dir;
    late File file;

    // synchronous: a widget test's clock does not drive real file work
    setUp(() {
      dir = Directory.systemTemp.createTempSync('tippani_cover_widget');
      file = File('${dir.path}/$name')..writeAsBytesSync(png);
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows keeps a picture the test showed open for a moment; the temp folder is cleared later
        }
      });
    });

    Widget app(Widget child, {CoverSource? source}) => MaterialApp(
      home: CoverScope(
        source: source,
        child: Scaffold(body: child),
      ),
    );

    testWidgets('a cover shows as a picture; no cover shows the fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WorkCover(
            work: work(cover: name),
            fallback: const Text('none'),
          ),
          source: _Source(file),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('none'), findsNothing);

      await tester.pumpWidget(
        app(
          WorkCover(work: work(), fallback: const Text('none')),
          source: _Source(file),
        ),
      );
      await tester.pump();
      expect(find.text('none'), findsOneWidget);
    });

    testWidgets(
      'with no source, or a source with nothing, the fallback shows',
      (tester) async {
        await tester.pumpWidget(
          app(
            WorkCover(
              work: work(cover: name),
              fallback: const Text('none'),
            ),
          ),
        );
        expect(find.text('none'), findsOneWidget);
        await tester.pumpWidget(
          app(
            WorkCover(
              work: work(cover: name),
              fallback: const Text('none'),
            ),
            source: _Source(null),
          ),
        );
        await tester.pump();
        expect(find.text('none'), findsOneWidget);
      },
    );

    group('on a work\'s page', () {
      late MemoryLibrary lib;
      late _Source source;
      late int workId;

      Future<void> open(
        WidgetTester tester, {
        bool synced = true,
        String cover = '',
      }) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        lib = MemoryLibrary();
        source = _Source(file)..uploadName = '0000000000000009.png';
        final w = await lib.addWork(const WorkDraft(title: 'Walden'));
        workId = w.id;
        if (synced) await lib.setWorkServerId(w.id, 3);
        if (cover.isNotEmpty) await lib.setWorkCover(w.id, cover);
        await tester.pumpWidget(
          CoverScope(
            source: source,
            child: MaterialApp(
              home: WorkScreen(
                store: lib,
                workId: w.id,
                picker: _NoPicker(),
                photos: _Photos(file.path),
                readBytes: (_) async => Uint8List.fromList(png),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('a work with a cover shows it', (tester) async {
        await open(tester, cover: name);
        expect(find.byType(Image), findsOneWidget);
      });

      testWidgets('a work with none shows no picture', (tester) async {
        await open(tester);
        expect(find.byType(Image), findsNothing);
      });

      testWidgets(
        'Choose a cover is offered only for a work that is on the server',
        (tester) async {
          await open(tester, synced: false);
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          expect(find.text('Choose a cover'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await open(tester);
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          expect(find.text('Choose a cover'), findsOneWidget);
        },
      );

      testWidgets(
        'choosing one sends it and the work keeps the name the server gave',
        (tester) async {
          await open(tester);
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Choose a cover'));
          await tester.pumpAndSettle();
          expect(source.uploads, 1);
          expect((await lib.work(workId))!.cover, '0000000000000009.png');
        },
      );

      testWidgets(
        'a server that does not take it is said, and the cover is unchanged',
        (tester) async {
          await open(tester);
          source.uploadName = null;
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Choose a cover'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('did not take that picture'),
            findsOneWidget,
          );
          expect((await lib.work(workId))!.cover, '');
        },
      );
    });
  });
}

class _Source implements CoverSource {
  _Source(this.file);
  final File? file;
  String? uploadName;
  int uploads = 0;

  @override
  Future<File?> fileFor(String name) async => file;

  @override
  Future<String?> upload(Work work, Uint8List bytes, String fileName) async {
    uploads++;
    return uploadName;
  }
}

class _Photos implements PhotoSource {
  _Photos(this.path);
  final String path;
  @override
  Future<String?> take() async => path;
  @override
  Future<String?> choose() async => path;
}

class _NoPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
  @override
  Future<PickedFile?> pick() async => null;
}
