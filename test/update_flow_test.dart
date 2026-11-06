import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/apk_install.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/harness/update_check.dart';
import 'package:tippani/harness/update_controller.dart';
import 'package:tippani/harness/update_ui.dart';
import 'package:tippani/settings/settings_store.dart';

const sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const info = ReleaseInfo(
  version: '0.2.0',
  apkUrl: 'https://example.org/tippani-app-v0.2.0.apk',
  apkName: 'tippani-app-v0.2.0.apk',
  sha256: sha,
  notes: 'A better thing.',
);

UpdateController controller(
  ReleaseCheck check, [
  ApkInstaller? installer,
  AppLog? log,
]) => UpdateController(
  check: check,
  installer: installer ?? FixedApkInstaller(const []),
  log: log,
);

Future<(AppController, Harness)> app({
  required ReleaseCheck check,
  ApkInstaller? installer,
  Map<String, Object> saved = const {},
  bool showWhatsNew = false,
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store);
  return (
    c,
    Harness.fake(
      store,
      controller: c,
      check: check,
      installer: installer,
      showWhatsNew: showWhatsNew,
    ),
  );
}

void main() {
  group('UpdateController', () {
    test('finds an update, remembers it, and announces it once on an automatic check', () async {
      final u = controller(FixedReleaseCheck(const UpdateAvailable(info)));
      await u.checkOnOpen();
      expect(u.stage, UpdateStage.available);
      expect(u.release?.version, '0.2.0');
      expect(u.takeAnnouncement(), isTrue);
      expect(u.takeAnnouncement(), isFalse, reason: 'one toast per find');
    });

    test('a check the reader asks for is not announced as a toast', () async {
      final u = controller(FixedReleaseCheck(const UpdateAvailable(info)));
      await u.checkNow();
      expect(u.stage, UpdateStage.available);
      expect(u.takeAnnouncement(), isFalse);
    });

    test('up to date is a state of its own', () async {
      final u = controller(FixedReleaseCheck(const UpToDate()));
      await u.checkNow();
      expect(u.stage, UpdateStage.upToDate);
      expect(u.release, isNull);
    });

    test('a failed check says why and leaves nothing marked', () async {
      final u = controller(
        FixedReleaseCheck(const CheckFailed(CheckFailure.rateLimited)),
      );
      await u.checkOnOpen();
      expect(u.stage, UpdateStage.idle);
      expect(u.checkFailure, CheckFailure.rateLimited);
      expect(u.takeAnnouncement(), isFalse);
    });

    test('download asks the installer for the release\'s file with its digest, and reaches installing', () async {
      final installer = FixedApkInstaller(const [
        InstallEvent.downloading(40),
        InstallEvent.downloading(100),
        InstallEvent.installing(),
      ]);
      final u = controller(
        FixedReleaseCheck(const UpdateAvailable(info)),
        installer,
      );
      await u.checkOnOpen();
      await u.download();
      expect(installer.asked.single.url, info.apkUrl);
      expect(installer.asked.single.fileName, info.apkName);
      expect(installer.asked.single.sha256, sha);
      expect(u.stage, UpdateStage.installing);
    });

    test('a download that fails is a failure with its reason, and Try again is possible', () async {
      final installer = FixedApkInstaller(const [
        InstallEvent.downloading(10),
        InstallEvent.failed(InstallFailure.checksum),
      ]);
      final u = controller(
        FixedReleaseCheck(const UpdateAvailable(info)),
        installer,
      );
      await u.checkOnOpen();
      await u.download();
      expect(u.stage, UpdateStage.failed);
      expect(u.installFailure, InstallFailure.checksum);
      u.dismiss();
      expect(
        u.stage,
        UpdateStage.available,
        reason: 'the update is still on offer',
      );
    });

    test('an update already on the phone with the published checksum is installed without downloading again', () async {
      final installer = FixedApkInstaller(
        const [],
        keptFile: (size: 1000, sha256: sha),
      );
      final u = controller(
        FixedReleaseCheck(const UpdateAvailable(info)),
        installer,
      );
      await u.checkOnOpen();
      await u.download();
      expect(installer.asked, isEmpty);
      expect(installer.installFileCalls, 1);
      expect(u.stage, UpdateStage.installing);
    });

    test(
      'a kept file with a different checksum is downloaded afresh',
      () async {
        final installer = FixedApkInstaller(
          const [InstallEvent.installing()],
          keptFile: (size: 1000, sha256: 'f' * 64),
        );
        final u = controller(
          FixedReleaseCheck(const UpdateAvailable(info)),
          installer,
        );
        await u.checkOnOpen();
        await u.download();
        expect(installer.installFileCalls, 0);
        expect(installer.asked, hasLength(1));
      },
    );

    test(
      'it writes what happened to the log, and never the download address',
      () async {
        final log = AppLog();
        final u = controller(
          FixedReleaseCheck(const UpdateAvailable(info)),
          FixedApkInstaller(const [InstallEvent.installing()]),
          log,
        );
        await u.checkOnOpen();
        await u.download();
        final text = log.text();
        expect(text, contains('update available: 0.2.0'));
        expect(text, contains('Android installer opened'));
        expect(text, isNot(contains('example.org')));
      },
    );
  });

  group('the toast', () {
    testWidgets(
      'an update on open shows a toast with Download, and Download starts the download',
      (tester) async {
        final installer = FixedApkInstaller(const [
          InstallEvent.downloading(50),
          InstallEvent.installing(),
        ]);
        final (c, h) = await app(
          check: FixedReleaseCheck(const UpdateAvailable(info)),
          installer: installer,
        );
        await tester.pumpWidget(TippaniApp(controller: c, harness: h));
        await tester.pump();
        // the SnackBar slides in over about 250 ms; tapping it before then misses
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Version 0.2.0 is available'), findsOneWidget);
        expect(
          installer.asked,
          isEmpty,
          reason: 'nothing downloads until Download is pressed',
        );

        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(installer.asked.single.fileName, 'tippani-app-v0.2.0.apk');
        expect(find.text('Ready to install'), findsOneWidget);
      },
    );

    testWidgets('no update, no toast', (tester) async {
      final (c, h) = await app(check: FixedReleaseCheck(const UpToDate()));
      await tester.pumpWidget(TippaniApp(controller: c, harness: h));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a check that cannot reach GitHub on open says nothing', (
      tester,
    ) async {
      final (c, h) = await app(
        check: FixedReleaseCheck(const CheckFailed(CheckFailure.offline)),
      );
      await tester.pumpWidget(TippaniApp(controller: c, harness: h));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed install says why in words and offers Try again', (
      tester,
    ) async {
      final installer = FixedApkInstaller(const [
        InstallEvent.failed(InstallFailure.notAllowed),
      ]);
      final (c, h) = await app(
        check: FixedReleaseCheck(const UpdateAvailable(info)),
        installer: installer,
      );
      await tester.pumpWidget(TippaniApp(controller: c, harness: h));
      await tester.pump();
      // the SnackBar slides in over about 250 ms; tapping it before then misses
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('The update did not install'), findsOneWidget);
      expect(find.textContaining('Install unknown apps'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'Settings: Check for updates reports up to date, and finds one on demand',
      (tester) async {
        final check = FixedReleaseCheck(const UpToDate());
        final (c, h) = await app(check: check);
        await tester.pumpWidget(TippaniApp(controller: c, harness: h));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(check.asked, 1, reason: 'the check on open');
        await tester.tap(find.text('Check for updates'));
        await tester.pumpAndSettle();
        expect(check.asked, 2);
        expect(
          find.textContaining('You have the latest version'),
          findsOneWidget,
        );

        check.result = const UpdateAvailable(info);
        await tester.tap(find.text('Check for updates'));
        await tester.pumpAndSettle();
        expect(find.text('Version 0.2.0 is available'), findsOneWidget);
        expect(
          find.text('A better thing.'),
          findsOneWidget,
          reason: 'the dialog shows the release notes',
        );
      },
    );
  });

  test('every install failure has a sentence', () {
    for (final f in InstallFailure.values) {
      expect(installFailureText(f), isNotEmpty);
    }
  });
}
