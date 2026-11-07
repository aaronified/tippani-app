import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/admin/server_files.dart';
import 'package:tippani/screens/admin_backup_screen.dart';
import 'package:tippani/screens/admin_folders_screen.dart';
import 'package:tippani/screens/admin_jobs_screen.dart';
import 'package:tippani/screens/admin_screen.dart';
import 'package:tippani/screens/admin_sources_screen.dart';
import 'package:tippani/screens/admin_update_screen.dart';
import 'package:tippani/screens/admin_users_screen.dart';

import '../support/fake_admin.dart';

Future<void> open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> typeInDialog(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('users', () {
    testWidgets('lists accounts, adds one, and changes who is an admin', (
      tester,
    ) async {
      final admin = FakeAdmin();
      await open(tester, AdminUsersScreen(service: admin, myName: 'alice'));
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('You'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      await tester.tap(find.text('Add a user'));
      await tester.pumpAndSettle();
      await typeInDialog(tester, 'carol');
      await tapButton(tester, 'Next');
      await typeInDialog(tester, 'a-temporary-pass');
      await tapButton(tester, 'Add');
      expect(admin.calls, contains('addUser carol'));
      expect(find.text('carol'), findsOneWidget);

      await tester.tap(find.byTooltip('More').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Make admin');
      expect(admin.calls, contains('setAdmin 2 true'));
    });

    testWidgets('removing asks first and shows the server\'s refusal', (
      tester,
    ) async {
      final admin = FakeAdmin()
        ..refuseDelete = 'cannot delete your own account';
      await open(tester, AdminUsersScreen(service: admin, myName: 'alice'));
      // alice is you and an admin: you can step down, not remove yourself; bob can be made admin or removed
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Step down from admin'), findsOneWidget);
      expect(find.text('Remove this user'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove this user'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Their whole library goes with them'),
        findsOneWidget,
      );
      await tapButton(tester, 'Remove');
      expect(admin.calls, contains('deleteUser 2'));
      expect(find.text('cannot delete your own account'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
    });
  });

  group('jobs', () {
    JobInfo job(
      int id,
      String kind,
      String state, {
      int total = 0,
      int done = 0,
      bool rerunnable = false,
      String error = '',
    }) => JobInfo(
      id: id,
      kind: kind,
      state: state,
      total: total,
      done: done,
      rerunnable: rerunnable,
      error: error,
      subject: 'Walden',
    );

    testWidgets('shows what runs now, stops it, and runs a past one again', (
      tester,
    ) async {
      final admin = FakeAdmin()
        ..current = [job(1, 'covers', 'running', total: 10, done: 4)]
        ..past = [
          job(2, 'fill', 'failed', rerunnable: true, error: 'no key for TMDB'),
        ];
      await open(
        tester,
        AdminJobsScreen(service: admin, pollEvery: const Duration(hours: 1)),
      );
      expect(find.text('Fetch covers'), findsOneWidget);
      expect(find.text('4 of 10'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(admin.calls, contains('stop 1'));
      expect(find.text('Nothing is running or waiting.'), findsOneWidget);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('Fill in missing details'), findsOneWidget);
      expect(find.text('no key for TMDB'), findsOneWidget);
      await tester.tap(find.text('Run again'));
      await tester.pumpAndSettle();
      expect(admin.calls, contains('rerun 2'));
      // the screen reads again on a timer; taking it down cancels that
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'common jobs start with their own parameters, and a log opens',
      (tester) async {
        final admin = FakeAdmin()
          ..common = const [
            CommonJob(
              id: 'covers',
              kind: 'covers',
              params: {'missing_only': false},
            ),
          ]
          ..past = [job(3, 'backup', 'succeeded')];
        await open(
          tester,
          AdminJobsScreen(service: admin, pollEvery: const Duration(hours: 1)),
        );
        await tester.tap(find.text('Common'));
        await tester.pumpAndSettle();
        expect(find.text('Fetch every cover'), findsOneWidget);
        await tester.tap(find.text('Run'));
        await tester.pumpAndSettle();
        expect(admin.calls, contains('start covers'));

        await tester.tap(find.text('Past'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back up the server'));
        await tester.pumpAndSettle();
        expect(find.text('info: started'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('backup', () {
    testWidgets('a wrong password is refused with the server\'s words', (
      tester,
    ) async {
      final admin = FakeAdmin();
      await open(
        tester,
        AdminBackupScreen(service: admin, files: FakeServerFiles()),
      );
      expect(find.text('The server has no backup yet.'), findsOneWidget);
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      await typeInDialog(tester, 'wrong');
      await tapButton(tester, 'Back up');
      expect(find.text('That password is not right.'), findsOneWidget);
      expect(admin.kept, isNull);
    });

    testWidgets('makes a backup and saves it on the phone', (tester) async {
      final admin = FakeAdmin();
      final files = FakeServerFiles();
      await open(
        tester,
        AdminBackupScreen(
          service: admin,
          files: files,
          pollEvery: const Duration(milliseconds: 10),
        ),
      );
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      await typeInDialog(tester, 'secret');
      await tapButton(tester, 'Back up');
      expect(admin.kept, isNotNull);
      expect(
        find.textContaining('sealed with the password of alice'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save on this phone'));
      await tester.pumpAndSettle();
      expect(files.saved.keys, ['tippani-backup.tippani']);
    });

    testWidgets(
      'a restore keeps a safety copy first, then replaces the library',
      (tester) async {
        final admin = FakeAdmin()
          ..kept = const BackupInfo(
            name: 'b.tippani',
            created: '2026-11-01',
            size: 10,
            key: 'password',
            account: 'alice',
          );
        final files = FakeServerFiles();
        await open(
          tester,
          AdminBackupScreen(
            service: admin,
            files: files,
            pollEvery: const Duration(milliseconds: 10),
          ),
        );
        await tester.tap(find.text('Restore the kept backup'));
        await tester.pumpAndSettle();
        await tapButton(tester, 'Continue');
        // the safety copy's password, then the backup's own
        await typeInDialog(tester, 'secret');
        await tapButton(tester, 'Make the copy');
        expect(files.saved.keys, ['safety.tippani']);
        await typeInDialog(tester, 'secret');
        await tapButton(tester, 'Restore');
        expect(
          admin.calls.where(
            (c) => c == 'safety' || c == 'downloadSafety' || c == 'restoreKept',
          ),
          ['safety', 'downloadSafety', 'restoreKept'],
        );
        expect(find.textContaining('The library is restored'), findsOneWidget);
      },
    );

    testWidgets('a safety copy that is not kept stops the restore', (
      tester,
    ) async {
      final admin = FakeAdmin()
        ..kept = const BackupInfo(name: 'b.tippani', key: 'password');
      final files = FakeServerFiles()..accept = false;
      await open(
        tester,
        AdminBackupScreen(
          service: admin,
          files: files,
          pollEvery: const Duration(milliseconds: 10),
        ),
      );
      await tester.tap(find.text('Restore the kept backup'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Continue');
      await typeInDialog(tester, 'secret');
      await tapButton(tester, 'Make the copy');
      expect(admin.calls, isNot(contains('restoreKept')));
      expect(find.textContaining('nothing was restored'), findsOneWidget);
    });

    testWidgets(
      'a backup file from the phone is uploaded after the safety copy',
      (tester) async {
        final admin = FakeAdmin();
        final files = FakeServerFiles()
          ..toPick = ChosenFile('other.tippani', Uint8List.fromList([9]));
        await open(
          tester,
          AdminBackupScreen(
            service: admin,
            files: files,
            pollEvery: const Duration(milliseconds: 10),
          ),
        );
        await tester.tap(find.text('Restore from a file'));
        await tester.pumpAndSettle();
        await tapButton(tester, 'Continue');
        await typeInDialog(tester, 'secret');
        await tapButton(tester, 'Make the copy');
        await typeInDialog(tester, 'whatever');
        await tapButton(tester, 'Restore');
        expect(admin.calls, contains('restoreUpload other.tippani'));
      },
    );
  });

  group('updates', () {
    testWidgets('shows the version, the command to copy and the line chosen', (
      tester,
    ) async {
      final admin = FakeAdmin();
      await open(tester, AdminUpdateScreen(service: admin));
      expect(find.text('An update is ready'), findsOneWidget);
      expect(find.text('docker compose pull'), findsOneWidget);
      expect(find.textContaining('Update to'), findsNothing);
      await tester.tap(find.text('Pre-release'));
      await tester.pumpAndSettle();
      expect(admin.calls, contains('channel prerelease'));
    });

    testWidgets('a server that can update itself offers the button', (
      tester,
    ) async {
      final admin = FakeAdmin()
        ..update = const UpdateInfo(
          current: 'v3.6.0',
          latest: 'v3.7.0',
          available: true,
          canSelfUpdate: true,
        );
      await open(tester, AdminUpdateScreen(service: admin));
      expect(find.text('Update to v3.7.0'), findsOneWidget);
    });
  });

  group('library folders', () {
    testWidgets('adds a folder with an id made from its name, and removes it', (
      tester,
    ) async {
      final admin = FakeAdmin();
      await open(tester, AdminFoldersScreen(service: admin));
      await tester.tap(find.text('Add a folder'));
      await tester.pumpAndSettle();
      await typeInDialog(tester, '/data/My Books');
      await tapButton(tester, 'Next');
      await tapButton(tester, 'Add');
      expect(admin.mounts.single.id, 'my-books');
      expect(admin.mounts.single.path, '/data/My Books');
      expect(find.text('My Books'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Remove');
      expect(admin.mounts, isEmpty);
    });

    testWidgets('tidies unused saved files and switches the backup option', (
      tester,
    ) async {
      final admin = FakeAdmin()..orphans = 3;
      await open(tester, AdminFoldersScreen(service: admin));
      expect(find.textContaining('3 saved files are unused'), findsOneWidget);
      await tester.tap(find.text('Tidy'));
      await tester.pumpAndSettle();
      expect(admin.orphans, 0);
      expect(find.text('Removed 3 saved files.'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(admin.withSources, isTrue);
    });
  });

  group('metadata sources', () {
    testWidgets('tests sources, sets a key and switches page reading', (
      tester,
    ) async {
      final admin = FakeAdmin();
      await open(tester, AdminSourcesScreen(service: admin));
      expect(find.text('TMDB'), findsOneWidget);
      expect(find.textContaining('Needs a key'), findsOneWidget);
      await tester.tap(find.byTooltip('Test TMDB'));
      await tester.pumpAndSettle();
      expect(admin.calls, contains('test tmdb'));
      await tester.tap(find.byTooltip('Test every source'));
      await tester.pumpAndSettle();
      expect(admin.calls, contains('test all'));

      await tester.tap(find.text('TMDB key'));
      await tester.pumpAndSettle();
      await typeInDialog(tester, 'abc123');
      await tapButton(tester, 'Save');
      expect(admin.calls, contains('key tmdb_key=abc123'));
      expect(find.text('Saved'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Read Google Books pages'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(admin.calls, contains('key google_scrape=true'));
    });
  });

  testWidgets('the hub opens each admin screen', (tester) async {
    final admin = FakeAdmin();
    await open(
      tester,
      AdminScreen(service: admin, files: FakeServerFiles(), myName: 'alice'),
    );
    for (final (row, title) in [
      ('Users', 'Add a user'),
      ('Server backup', 'Back up now'),
      ('Library folders', 'Add a folder'),
    ]) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: row);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
