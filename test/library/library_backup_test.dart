import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/backup.dart';
import 'package:tippani/harness/backup_screen.dart';
import 'package:tippani/harness/files.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/library_backup.dart';
import 'package:tippani/library/library_store.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/settings/settings_backup.dart';
import 'package:tippani/settings/settings_store.dart';

Future<(SettingsStore, SqliteLibraryStore, BackupService)> rig(
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final library = await SqliteLibraryStore.open(
    inMemoryDatabasePath,
    singleInstance: false,
  );
  final service = BackupService(
    MemoryAppFiles(),
    contributors: [SettingsBackup(settings), LibraryBackup(library)],
  );
  return (settings, library, service);
}

/// A library with no I/O, for the widget tests: real SQLite work cannot be driven by a widget test's fake
/// clock (its futures never complete), so the screens are tested against this and the store itself against
/// real SQLite in `library_store_test.dart`. It validates exactly as the real one does.
class _MemoryLibrary implements LibraryStore {
  _MemoryLibrary([Map<String, Object?>? data])
    : data = data ?? {'version': 1, 'works': [], 'quotes': []};
  Map<String, Object?> data;

  List<Object?> get quoteList => data['quotes']! as List<Object?>;

  @override
  Future<Map<String, Object?>> exportAll() async => data;

  @override
  Future<void> replaceAll(Map<String, Object?> d) async {
    SqliteLibraryStore.validate(d);
    data = d;
  }

  // What the library tab reads when it opens: it is not what these tests are about, so it shows nothing.
  @override
  Future<List<Work>> works({WorkKind? kind, String query = ''}) async => [];

  @override
  Future<List<Quote>> quotes({
    int? workId,
    String query = '',
    bool favouritesOnly = false,
    String? tag,
    int? boardId,
    bool unfiled = false,
    int limit = 200,
    int offset = 0,
  }) async => [];

  @override
  Future<List<Board>> boards() async => [];

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<LibraryCounts> counts() async =>
      const LibraryCounts(works: 0, quotes: 0, favourites: 0, tags: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Uint8List asBytes(BackupDocument d) =>
    Uint8List.fromList(utf8.encode(d.toText()));

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'a backup carries the library, and the library comes back from it',
    () async {
      final (_, a, svcA) = await rig({'server_url': 'https://a.example.org'});
      final w = await a.addWork(
        const WorkDraft(title: 'Walden', creator: 'Thoreau'),
      );
      await a.addQuote(
        QuoteDraft(
          text: 'I went to the woods',
          workId: w.id,
          tags: const ['nature'],
        ),
      );
      final doc = parseBackup(asBytes(await svcA.collect()));
      expect(doc.sections.keys, containsAll(['settings', 'library']));

      final (_, b, svcB) = await rig({});
      await b.addQuote(const QuoteDraft(text: 'will be replaced'));
      final r = await svcB.restore(doc);
      expect(r.restored, containsAll(['settings', 'library']));
      expect((await b.quotes()).map((q) => q.text), ['I went to the woods']);
      expect((await b.works()).map((x) => x.title), ['Walden']);
    },
  );

  test('a backup that holds no library leaves the library alone', () async {
    final (_, lib, svc) = await rig({});
    await lib.addQuote(const QuoteDraft(text: 'keep me'));
    final doc = BackupDocument(
      createdAt: DateTime.now(),
      appVersion: '0.0.1',
      sections: {
        'settings': {'server_url': 'https://x.example.org'},
      },
    );
    await svc.restore(doc);
    expect((await lib.quotes()).map((q) => q.text), ['keep me']);
  });

  test('a damaged library section refuses the whole restore: the settings are not restored either', () async {
    final (settings, lib, svc) = await rig({
      'server_url': 'https://old.example.org',
    });
    await lib.addQuote(const QuoteDraft(text: 'keep me'));
    final doc = BackupDocument(
      createdAt: DateTime.now(),
      appVersion: '0.0.1',
      sections: {
        'settings': {'server_url': 'https://new.example.org'},
        'library': {
          'version': 1,
          'works': [],
          'quotes': [
            {'id': 1, 'text': '   '},
          ],
        },
      },
    );
    await expectLater(
      svc.restore(doc),
      throwsA(
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.damaged,
        ),
      ),
    );
    expect(
      settings.serverUrl,
      'https://old.example.org',
      reason: 'checked before anything was written',
    );
    expect((await lib.quotes()).map((q) => q.text), ['keep me']);
  });

  test('a library section that is not a map, or is from a newer app, is damaged too', () async {
    final (_, _, svc) = await rig({});
    for (final bad in <Object?>[
      'text',
      5,
      null,
      {'version': 99, 'works': [], 'quotes': []},
    ]) {
      final doc = BackupDocument(
        createdAt: DateTime.now(),
        appVersion: '',
        sections: {'library': bad},
      );
      await expectLater(
        svc.restore(doc),
        throwsA(isA<BackupException>()),
        reason: '$bad',
      );
    }
  });

  test(
    'the device token is still never in a backup that carries a library',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'https://q.example.org',
      });
      final vault = MemoryTokenVault();
      await vault.write('super-secret-device-token');
      final settings = SettingsStore(
        await SharedPreferences.getInstance(),
        vault,
      );
      final lib = await SqliteLibraryStore.open(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      await lib.addQuote(const QuoteDraft(text: 'a quote'));
      final text = (await BackupService(
        MemoryAppFiles(),
        contributors: [SettingsBackup(settings), LibraryBackup(lib)],
      ).collect()).toText();
      expect(text, isNot(contains('super-secret-device-token')));
    },
  );

  group('on the backup screen', () {
    Future<void> open(
      WidgetTester tester,
      SettingsStore settings,
      LibraryStore lib,
      MemoryAppFiles files,
    ) async {
      final controller = AppController(settings);
      await tester.pumpWidget(
        TippaniApp(
          controller: controller,
          harness: Harness.fake(
            settings,
            controller: controller,
            files: files,
            library: lib,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Backup and restore'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Backup and restore'));
      await tester.pumpAndSettle();
    }

    Map<String, Object?> libraryWith(String text) => {
      'version': 1,
      'works': [],
      'quotes': [
        {'id': 1, 'text': text},
      ],
    };

    testWidgets(
      'the confirmation says the library is replaced, and a restore brings it back',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        );
        final lib = _MemoryLibrary(libraryWith('from the backup'));
        final files = MemoryAppFiles();
        await open(tester, settings, lib, files);
        await tester.tap(find.text('Back up now'));
        await tester.pumpAndSettle();
        lib.data = libraryWith('made after the backup');

        await tester.tap(find.text('Restore').first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('replaces the settings and the library'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
        await tester.pumpAndSettle();
        expect((lib.quoteList.single! as Map)['text'], 'from the backup');
      },
    );

    testWidgets(
      'a backup whose library is damaged says so and changes nothing',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'server_url': 'https://old.example.org',
        });
        final settings = SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        );
        final lib = _MemoryLibrary(libraryWith('keep me'));
        final files = MemoryAppFiles();
        final bad = BackupDocument(
          createdAt: DateTime.now(),
          appVersion: '0.0.1',
          sections: {
            'settings': {'server_url': 'https://new.example.org'},
            'library': {
              'version': 1,
              'works': [],
              'quotes': [
                {'id': 1, 'text': ''},
              ],
            },
          },
        );
        files.backups['tippani-app-backup-bad.json'] = asBytes(bad);
        await open(tester, settings, lib, files);
        await tester.tap(find.text('Restore').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
        await tester.pumpAndSettle();
        expect(
          find.text(backupProblemText(BackupProblem.damaged)),
          findsOneWidget,
        );
        expect(settings.serverUrl, 'https://old.example.org');
        expect((lib.quoteList.single! as Map)['text'], 'keep me');
      },
    );
  });
}
