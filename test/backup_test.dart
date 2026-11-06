import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/harness/backup.dart';
import 'package:tippani/harness/files.dart';
import 'package:tippani/harness/version.dart';
import 'package:tippani/settings/settings_backup.dart';
import 'package:tippani/settings/settings_store.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

class _Part implements BackupContributor {
  _Part(this.key, this.value);
  @override
  final String key;
  Object? value;
  Object? restoredWith;

  @override
  Future<Object?> export() async => value;

  @override
  Future<void> restore(Object? data) async => restoredWith = data;
}

Future<(SettingsStore, MemoryTokenVault)> store([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final vault = MemoryTokenVault();
  return (SettingsStore(await SharedPreferences.getInstance(), vault), vault);
}

void main() {
  final now = DateTime(2026, 11, 6, 9, 5);

  test('the file name carries the date and time', () {
    expect(backupFileName(now), 'tippani-app-backup-20261106-0905.json');
  });

  group('parseBackup', () {
    String doc({
      Object? format = backupFormat,
      Object? version = backupVersion,
      Object? sections = const {'settings': {}},
    }) => jsonEncode({
      'format': format,
      'version': version,
      'app_version': '0.1.0',
      'created_at': '2026-11-06T03:35:00Z',
      'sections': sections,
    });

    test('reads a good file', () {
      final d = parseBackup(
        bytes(
          doc(
            sections: {
              'settings': {'server_url': 'https://q.example.org'},
            },
          ),
        ),
      );
      expect(d.appVersion, '0.1.0');
      expect(d.createdAt.toUtc(), DateTime.utc(2026, 11, 6, 3, 35));
      expect(d.sections['settings'], {'server_url': 'https://q.example.org'});
    });

    BackupProblem? problem(Uint8List b) {
      try {
        parseBackup(b);
        return null;
      } on BackupException catch (e) {
        return e.problem;
      }
    }

    test('refuses a file that is too big before reading it', () {
      expect(problem(Uint8List(maxBackupBytes + 1)), BackupProblem.tooBig);
    });

    test(
      'refuses what is not JSON, not ours, newer than this app, or empty',
      () {
        expect(problem(bytes('not json at all')), BackupProblem.notJson);
        expect(problem(bytes('[1,2,3]')), BackupProblem.notOurs);
        expect(
          problem(bytes(doc(format: 'some-other-backup'))),
          BackupProblem.notOurs,
        );
        expect(problem(bytes(doc(version: 'one'))), BackupProblem.notOurs);
        expect(problem(bytes(doc(version: 0))), BackupProblem.notOurs);
        expect(
          problem(bytes(doc(version: backupVersion + 1))),
          BackupProblem.tooNew,
        );
        expect(
          problem(bytes(doc(sections: const {}))),
          BackupProblem.noSections,
        );
        expect(problem(bytes(doc(sections: 'x'))), BackupProblem.noSections);
      },
    );

    test('a missing date or app version is tolerated', () {
      final d = parseBackup(
        bytes(
          jsonEncode({
            'format': backupFormat,
            'version': 1,
            'sections': {'a': 1},
          }),
        ),
      );
      expect(d.appVersion, '');
      expect(d.createdAt.millisecondsSinceEpoch, 0);
    });
  });

  group('BackupService', () {
    test(
      'backUp writes the same file to the app\'s storage and to Downloads',
      () async {
        final files = MemoryAppFiles();
        final svc = BackupService(
          files,
          contributors: [
            _Part('settings', {'a': 1}),
          ],
          clock: () => now,
        );
        final r = await svc.backUp();
        expect(r?.name, 'tippani-app-backup-20261106-0905.json');
        expect(r?.inDownloads, isTrue);
        expect(files.backups[r!.name], files.downloads[r.name]);
        final doc = parseBackup(files.backups[r.name]!);
        expect(doc.appVersion, appVersion);
        expect(doc.sections['settings'], {'a': 1});
      },
    );

    test('it reports a phone that cannot write, and one that cannot copy to Downloads', () async {
      final unwritable = MemoryAppFiles()..writable = false;
      expect(
        await BackupService(unwritable, contributors: [_Part('a', 1)]).backUp(),
        isNull,
      );
    });

    test('it keeps the newest few copies and removes the older', () async {
      final files = MemoryAppFiles();
      for (var i = 0; i < BackupService.keep + 3; i++) {
        files.backups['old-$i.json'] = bytes('{}');
      }
      final svc = BackupService(
        files,
        contributors: [_Part('a', 1)],
        clock: () => now,
      );
      await svc.backUp();
      expect((await svc.copies()).length, BackupService.keep);
    });

    test('restore gives each contributor its own section and reports what nothing owns', () async {
      final a = _Part('a', null);
      final b = _Part('b', null);
      final svc = BackupService(MemoryAppFiles(), contributors: [a, b]);
      final doc = BackupDocument(
        createdAt: now,
        appVersion: '9.9.9',
        sections: {
          'a': {'x': 1},
          'zzz': 'from a newer build',
        },
      );
      final r = await svc.restore(doc);
      expect(a.restoredWith, {'x': 1});
      expect(
        b.restoredWith,
        isNull,
        reason: 'a part with no section is left alone',
      );
      expect(r.restored, ['a']);
      expect(r.ignored, ['zzz']);
    });

    test('a feature that registers later is backed up and restored with no change to the service', () async {
      final queue = _Part('capture_queue', [1, 2, 3]);
      final svc = BackupService(
        MemoryAppFiles(),
        contributors: [_Part('settings', {})],
      );
      svc.contributors.add(queue);
      final doc = await svc.collect();
      expect(doc.sections.keys, containsAll(['settings', 'capture_queue']));
      queue.value = [];
      await svc.restore(doc);
      expect(queue.restoredWith, [1, 2, 3]);
    });
  });

  group('SettingsBackup', () {
    test('exports the server address and NEVER the token', () async {
      final (s, vault) = await store({'server_url': 'https://q.example.org'});
      await vault.write('super-secret-device-token');
      final svc = BackupService(
        MemoryAppFiles(),
        contributors: [SettingsBackup(s)],
        clock: () => now,
      );
      final text = (await svc.collect()).toText();
      expect(text, contains('https://q.example.org'));
      expect(text, isNot(contains('super-secret-device-token')));
      expect(text, isNot(contains('token')));
    });

    test('restore sets the server and, when it is a different one, forgets the old server\'s token', () async {
      final (s, vault) = await store({'server_url': 'https://old.example.org'});
      await vault.write('old-token');
      var refreshed = false;
      await SettingsBackup(
        s,
        onRestored: () async => refreshed = true,
      ).restore({'server_url': 'https://new.example.org'});
      expect(s.serverUrl, 'https://new.example.org');
      expect(await vault.read(), isNull);
      expect(refreshed, isTrue);
    });

    test('restoring the same server keeps its token', () async {
      final (s, vault) = await store({'server_url': 'https://q.example.org'});
      await vault.write('t');
      await SettingsBackup(s).restore({'server_url': 'https://q.example.org'});
      expect(await vault.read(), 't');
    });

    test('an address in a damaged or hand-edited file is checked as a typed one is', () async {
      final (s, _) = await store({'server_url': 'https://q.example.org'});
      for (final bad in [
        null,
        5,
        '',
        'ftp://nope',
        'javascript:alert(1)',
        '   ',
      ]) {
        await SettingsBackup(s).restore({'server_url': bad});
        expect(s.serverUrl, 'https://q.example.org', reason: '$bad');
      }
      await SettingsBackup(s).restore('not a map');
      await SettingsBackup(s).restore(null);
      expect(s.serverUrl, 'https://q.example.org');
    });

    test('a bare host in a backup is normalised on the way in', () async {
      final (s, _) = await store();
      await SettingsBackup(s).restore({'server_url': 'nas.local:8124/'});
      expect(s.serverUrl, 'https://nas.local:8124');
    });
  });
}
