import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/backup.dart';
import 'package:tippani/harness/backup_screen.dart';
import 'package:tippani/harness/changelog.dart';
import 'package:tippani/harness/files.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/harness/log_screen.dart';
import 'package:tippani/harness/version.dart';
import 'package:tippani/settings/settings_store.dart';

class _Picker implements BackupPicker {
  _Picker({this.file});
  PickedFile? file;
  Object? throws;
  final saved = <String, Uint8List>{};

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<PickedFile?> pick() async {
    if (throws != null) throw throws!;
    return file;
  }
}

final entries = parseChangelog('''
## [Unreleased]

### Added

- Not out yet.

## [$appVersion] - 2026-11-06

### Added

- The new thing everyone wanted.

### Fixed

- The old bug.

## [0.0.1] - 2026-10-01

### Added

- The beginning.
''');

class Rig {
  Rig(this.store, this.controller, this.harness, this.files, this.log);
  final SettingsStore store;
  final AppController controller;
  final Harness harness;
  final MemoryAppFiles files;
  final AppLog log;
}

Future<Rig> rig({
  Map<String, Object> saved = const {},
  bool showWhatsNew = false,
  BackupPicker? picker,
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final files = MemoryAppFiles();
  final log = AppLog(files: files, writeDelay: null);
  await log.start(version: appVersion);
  final controller = AppController(store, log: log);
  final harness = Harness.fake(
    store,
    controller: controller,
    files: files,
    log: log,
    changelog: entries,
    showWhatsNew: showWhatsNew,
    picker: picker,
  );
  return Rig(store, controller, harness, files, log);
}

Future<void> open(WidgetTester tester, Rig r) async {
  await tester.pumpWidget(
    TippaniApp(controller: r.controller, harness: r.harness),
  );
  await tester.pumpAndSettle();
}

Future<void> goSettings(WidgetTester tester, String entry) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

void main() {
  group('what is new after an update', () {
    testWidgets('shows this version\'s entry once, after an update', (
      tester,
    ) async {
      final r = await rig(
        saved: {'last_seen_version': '0.0.1'},
        showWhatsNew: true,
      );
      await open(tester, r);
      expect(find.text('New in $appVersion'), findsOneWidget);
      expect(
        find.textContaining('The new thing everyone wanted.'),
        findsOneWidget,
      );
      expect(find.textContaining('The old bug.'), findsOneWidget);
      expect(
        find.textContaining('Not out yet.'),
        findsNothing,
        reason: 'only this version\'s entry',
      );
      expect(r.store.lastSeenVersion, appVersion);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // a second start of the same version shows nothing
      await open(
        tester,
        await rig(saved: {'last_seen_version': appVersion}, showWhatsNew: true),
      );
      expect(find.text('New in $appVersion'), findsNothing);
    });

    testWidgets(
      'shows nothing on a first install, and still records the version',
      (tester) async {
        final r = await rig(showWhatsNew: true);
        await open(tester, r);
        expect(find.textContaining('New in'), findsNothing);
        expect(r.store.lastSeenVersion, appVersion);
      },
    );

    testWidgets(
      'the What\'s new screen in Settings lists every version, this one open',
      (tester) async {
        await open(tester, await rig());
        await goSettings(tester, "What's new");
        expect(find.text('Unreleased'), findsOneWidget);
        expect(find.text(appVersion), findsOneWidget);
        expect(find.text('0.0.1'), findsOneWidget);
        expect(
          find.textContaining('The new thing everyone wanted.'),
          findsOneWidget,
          reason: 'the running version starts open',
        );
        expect(
          find.textContaining('The beginning.'),
          findsNothing,
          reason: 'older ones start folded',
        );
        await tester.tap(find.text('0.0.1'));
        await tester.pumpAndSettle();
        expect(find.textContaining('The beginning.'), findsOneWidget);
      },
    );
  });

  group('the log screen', () {
    testWidgets('shows what the app did, and Settings reaches it', (
      tester,
    ) async {
      final r = await rig();
      r.log.warn('something went a bit wrong');
      await open(tester, r);
      await goSettings(tester, 'App log');
      expect(find.textContaining('something went a bit wrong'), findsOneWidget);
    });

    testWidgets('Share hands the log to the share sheet, flushed first', (
      tester,
    ) async {
      final r = await rig();
      r.log.info('a line to share');
      String? shared;
      String? subject;
      await tester.pumpWidget(
        MaterialApp(
          home: LogScreen(
            log: r.log,
            share: (text, s) async {
              shared = text;
              subject = s;
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(shared, contains('a line to share'));
      expect(subject, 'Tippani log');
      expect(
        utf8.decode(r.files.logs[AppLog.currentFile]!),
        contains('a line to share'),
        reason: 'it was written before sharing',
      );
    });

    testWidgets('Clear asks first, then empties the log', (tester) async {
      final r = await rig();
      r.log.info('to be cleared');
      await tester.pumpWidget(MaterialApp(home: LogScreen(log: r.log)));
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('to be cleared'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(find.text('The log is empty.'), findsOneWidget);
      expect(r.log.length, 0);
    });

    testWidgets('an empty log has nothing to copy or share', (tester) async {
      await tester.pumpWidget(MaterialApp(home: LogScreen(log: AppLog())));
      expect(find.text('The log is empty.'), findsOneWidget);
      final share = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.share),
      );
      expect(share.onPressed, isNull);
    });
  });

  group('the backup screen', () {
    testWidgets(
      'Back up now writes a copy to the app and to Downloads, and lists it',
      (tester) async {
        final r = await rig(saved: {'server_url': 'https://q.example.org'});
        await open(tester, r);
        await goSettings(tester, 'Backup and restore');
        expect(find.text('None yet.'), findsOneWidget);
        await tester.tap(find.text('Back up now'));
        await tester.pumpAndSettle();
        expect(r.files.backups, hasLength(1));
        expect(r.files.downloads, hasLength(1));
        expect(
          find.textContaining('here and in your Downloads folder'),
          findsOneWidget,
        );
        expect(find.text('None yet.'), findsNothing);
        final text = utf8.decode(r.files.backups.values.single);
        expect(text, contains('https://q.example.org'));
      },
    );

    testWidgets(
      'restoring a copy asks first, then puts the server back and says to pair again',
      (tester) async {
        final r = await rig(saved: {'server_url': 'https://old.example.org'});
        final other = await rig(
          saved: {'server_url': 'https://new.example.org'},
        );
        await other.harness.backup.backUp();
        r.files.backups.addAll(other.files.backups);

        await open(tester, r);
        await goSettings(tester, 'Backup and restore');
        await tester.tap(find.text('Restore').first);
        await tester.pumpAndSettle();
        expect(find.text('Restore this backup?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          r.store.serverUrl,
          'https://old.example.org',
          reason: 'Cancel changes nothing',
        );

        await tester.tap(find.text('Restore').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
        await tester.pumpAndSettle();
        expect(r.store.serverUrl, 'https://new.example.org');
        expect(find.textContaining('Pair this phone again'), findsOneWidget);
      },
    );

    testWidgets(
      'a file that is not a backup is refused with a sentence, and nothing changes',
      (tester) async {
        final picker = _Picker(
          file: PickedFile(
            'x.json',
            Uint8List.fromList(utf8.encode('{"hello":1}')),
          ),
        );
        final r = await rig(
          saved: {'server_url': 'https://q.example.org'},
          picker: picker,
        );
        await open(tester, r);
        await goSettings(tester, 'Backup and restore');
        await tester.tap(find.text('Restore from a file…'));
        await tester.pumpAndSettle();
        expect(
          find.text(backupProblemText(BackupProblem.notOurs)),
          findsOneWidget,
        );
        expect(r.store.serverUrl, 'https://q.example.org');
      },
    );

    testWidgets('a file that is too big is refused before it is read', (
      tester,
    ) async {
      final picker = _Picker()
        ..throws = const BackupException(BackupProblem.tooBig);
      final r = await rig(picker: picker);
      await open(tester, r);
      await goSettings(tester, 'Backup and restore');
      await tester.tap(find.text('Restore from a file…'));
      await tester.pumpAndSettle();
      expect(
        find.text(backupProblemText(BackupProblem.tooBig)),
        findsOneWidget,
      );
    });

    testWidgets('a backup from a newer app is refused by name', (tester) async {
      final newer = jsonEncode({
        'format': backupFormat,
        'version': backupVersion + 1,
        'sections': {'settings': {}},
      });
      final picker = _Picker(
        file: PickedFile('n.json', Uint8List.fromList(utf8.encode(newer))),
      );
      final r = await rig(picker: picker);
      await open(tester, r);
      await goSettings(tester, 'Backup and restore');
      await tester.tap(find.text('Restore from a file…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('newer version of the app'), findsOneWidget);
    });

    testWidgets('Save a copy somewhere hands the picker the same document', (
      tester,
    ) async {
      final picker = _Picker();
      final r = await rig(
        saved: {'server_url': 'https://q.example.org'},
        picker: picker,
      );
      await open(tester, r);
      await goSettings(tester, 'Backup and restore');
      await tester.tap(find.text('Save a copy somewhere…'));
      await tester.pumpAndSettle();
      expect(picker.saved, hasLength(1));
      expect(picker.saved.keys.single, startsWith('tippani-app-backup-'));
      expect(
        utf8.decode(picker.saved.values.single),
        contains('https://q.example.org'),
      );
      expect(find.text('Backup saved.'), findsOneWidget);
    });

    testWidgets('a phone that cannot write says so', (tester) async {
      final r = await rig();
      r.files.writable = false;
      await open(tester, r);
      await goSettings(tester, 'Backup and restore');
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      expect(find.text('The backup could not be written.'), findsOneWidget);
    });
  });

  test('every backup problem has a sentence', () {
    for (final p in BackupProblem.values) {
      expect(backupProblemText(p), isNotEmpty);
    }
  });
}
