// Runs the admin code against a real Tippani server, paired as an admin account. Skipped unless
// TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set (a fresh pairing code of an admin), and TIPPANI_LIVE_DIR names a
// folder that exists on that server's computer. It never restores a backup: that would replace the library.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];
final _dir = Platform.environment['TIPPANI_LIVE_DIR'];
final _password = Platform.environment['TIPPANI_LIVE_PASSWORD'] ?? '';

void main() {
  final skip = (_url == null || _code == null || _dir == null)
      ? 'set TIPPANI_LIVE_URL, TIPPANI_LIVE_CODE and TIPPANI_LIVE_DIR'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'users, folders, keys, jobs, backup and updates on a real server',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        log: AppLog(),
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live admin')).ok, isTrue);
      await controller.refresh();
      expect(
        controller.isAdmin,
        isTrue,
        reason: 'the pairing code was an admin\'s',
      );
      final admin = PairedAdminService(controller);
      expect(admin.available, isTrue);

      // users: added, listed, removed. (Making an account an admin is not tried: the server lets only that admin step
      // down again, and will not remove an admin, so the test could not clean up after itself.)
      final name = 'livetmp${DateTime.now().millisecondsSinceEpoch}';
      await admin.addUser(name, 'a-temporary-pass-1');
      var users = await admin.users();
      final tmp = users.firstWhere((u) => u.username == name);
      expect(tmp.isAdmin, isFalse);
      await admin.deleteUser(tmp.id);
      users = await admin.users();
      expect(users.any((u) => u.username == name), isFalse);

      // library folders
      var folders = await admin.folders();
      final before = folders.mounts.length;
      final saved = await admin.saveMounts([
        ...folders.mounts,
        MountInfo(id: 'live-folder', label: 'Live folder', path: _dir ?? ''),
      ]);
      expect(saved.any((m) => m.id == 'live-folder' && m.ok), isTrue);
      folders = await admin.folders();
      expect(folders.mounts.length, before + 1);
      await admin.saveMounts([
        for (final m in folders.mounts)
          if (m.id != 'live-folder') m,
      ]);
      expect((await admin.folders()).mounts.length, before);
      expect(await admin.setBackupSources(true), isTrue);
      expect(await admin.setBackupSources(false), isFalse);
      expect(await admin.tidySources(), greaterThanOrEqualTo(0));

      // metadata keys: written, then cleared, and a secret is only ever reported as set
      var keys = await admin.saveMetadataKey('tvdb_pin', 'abc');
      expect(keys.isSet('tvdb_pin'), isTrue);
      expect(
        keys.raw.containsValue('abc'),
        isFalse,
        reason: 'secrets are never sent back',
      );
      keys = await admin.saveMetadataKey('tvdb_pin', '');
      expect(keys.isSet('tvdb_pin'), isFalse);
      keys = await admin.saveMetadataKey('google_scrape', true);
      expect(keys.flag('google_scrape'), isTrue);
      keys = await admin.saveMetadataKey('google_scrape', false);
      expect(keys.flag('google_scrape'), isFalse);
      expect(await admin.metadataSources(), isNotEmpty);
      await admin.reindexSearch();

      // jobs
      final page = await admin.jobs(view: 'past');
      expect(page.jobs, isA<List<JobInfo>>());
      expect(await admin.commonJobs(), isNotEmpty);

      // backup: a wrong password is refused without unpairing the phone, a right one makes it and it comes down
      await expectLater(
        admin.createBackup(password: 'definitely-wrong'),
        throwsA(isA<Object>()),
      );
      expect(
        controller.paired,
        isTrue,
        reason: 'a wrong password is not an unpairing',
      );
      var job = await admin.createBackup(password: _password);
      expect(job, isNotNull);
      for (var i = 0; i < 60 && (job?.live ?? false); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        job = await admin.job(job!.id);
      }
      expect(job?.state, 'succeeded', reason: job?.error);
      final info = await admin.backup();
      expect(info, isNotNull);
      expect(info!.needsPassword, isTrue);
      final file = await admin.downloadBackup();
      expect(file.bytes.length, greaterThan(100));

      // the safety copy a restore asks for, brought down (the restore itself is never run here)
      var safety = await admin.createSafetyCopy(password: _password);
      for (var i = 0; i < 60 && (safety?.live ?? false); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        safety = await admin.job(safety!.id);
      }
      expect(safety?.state, 'succeeded', reason: safety?.error);
      final copy = await admin.downloadSafetyCopy(safety!.id);
      expect(copy.bytes.length, greaterThan(100));

      // updates
      final check = await admin.updateCheck();
      expect(check.channel, isNotEmpty);
      final other = check.channel == 'stable' ? 'prerelease' : 'stable';
      expect((await admin.setChannel(other)).channel, other);
      expect((await admin.setChannel(check.channel)).channel, check.channel);
      expect(await admin.updatePhase(), isA<String>());
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
