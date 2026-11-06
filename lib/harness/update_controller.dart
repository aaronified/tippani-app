import 'dart:async';

import 'package:flutter/foundation.dart';

import 'apk_install.dart';
import 'app_log.dart';
import 'update_check.dart';

enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  failed,
}

/// Whether a newer version of the app exists, and getting it onto the phone.
///
/// A check on open is silent when it finds nothing and when it cannot ask: an app that complains it is
/// offline every time it opens is worse than one that says nothing. A check the reader asks for (Settings)
/// says what happened either way. The download happens only when the reader presses Download, never on its
/// own.
class UpdateController extends ChangeNotifier {
  UpdateController({required this._check, required this._installer, this._log});

  final ReleaseCheck _check;
  final ApkInstaller _installer;
  final AppLog? _log;

  UpdateStage _stage = UpdateStage.idle;
  ReleaseInfo? _release;
  int _percent = 0;
  InstallFailure? _installFailure;
  CheckFailure? _checkFailure;
  bool _announced = false;
  StreamSubscription<InstallEvent>? _running;

  UpdateStage get stage => _stage;
  ReleaseInfo? get release => _release;
  int get percent => _percent;
  InstallFailure? get installFailure => _installFailure;

  /// Why the last check got no answer, or null.
  CheckFailure? get checkFailure => _checkFailure;

  /// True once, after an automatic check finds an update, so the screen shows its toast a single time per
  /// launch. Reading it clears it.
  bool takeAnnouncement() {
    final was = _announced;
    _announced = false;
    return was;
  }

  /// The check made when the app opens. Silent unless it finds an update.
  Future<void> checkOnOpen() => _run(announce: true);

  /// The check the reader asks for. The result is in [stage] and [checkFailure].
  Future<void> checkNow() => _run(announce: false);

  Future<void> _run({required bool announce}) async {
    if (_stage == UpdateStage.checking ||
        _stage == UpdateStage.downloading ||
        _stage == UpdateStage.installing) {
      return;
    }
    _set(UpdateStage.checking);
    final result = await _check.check();
    switch (result) {
      case UpdateAvailable(:final release):
        _release = release;
        _checkFailure = null;
        _announced = announce;
        _log?.info('update available: ${release.version}');
        _set(UpdateStage.available);
      case UpToDate():
        _release = null;
        _checkFailure = null;
        _log?.info('update check: up to date');
        _set(UpdateStage.upToDate);
      case CheckFailed(:final why):
        _checkFailure = why;
        _log?.warn('update check failed: ${why.name}');
        // An automatic check that failed leaves no mark; a manual one lands on idle with the reason set.
        _set(UpdateStage.idle);
    }
  }

  /// Downloads the update and opens Android's installer on it. If the file is already on the phone and its
  /// checksum is the release's, the download is skipped.
  Future<void> download() async {
    final r = _release;
    if (r == null ||
        _stage == UpdateStage.downloading ||
        _stage == UpdateStage.installing) {
      return;
    }
    _installFailure = null;
    _percent = 0;
    _set(UpdateStage.downloading);
    final kept = await _installer.kept(r.apkName);
    final reuse = kept != null && r.sha256 != null && kept.sha256 == r.sha256;
    _log?.info(
      reuse
          ? 'update ${r.version}: installing the kept download'
          : 'update ${r.version}: downloading',
    );
    final events = reuse
        ? _installer.installFile(r.apkName)
        : _installer.install(r.apkUrl, fileName: r.apkName, sha256: r.sha256);
    final done = Completer<void>();
    _running = events.listen(
      (e) {
        if (e.failure != null) {
          _installFailure = e.failure;
          _log?.warn('update install failed: ${e.failure!.name}');
          _set(UpdateStage.failed);
        } else if (e.installing) {
          _log?.info('update ${r.version}: Android installer opened');
          _set(UpdateStage.installing);
        } else {
          _percent = e.percent ?? _percent;
          notifyListeners();
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    _running = null;
  }

  /// Stops a download in progress.
  Future<void> cancel() async {
    await _installer.cancel();
  }

  /// Back to the screen's resting state after the reader dismisses a failure or a finished install.
  void dismiss() {
    if (_stage == UpdateStage.failed) {
      _set(_release == null ? UpdateStage.idle : UpdateStage.available);
    }
  }

  void _set(UpdateStage s) {
    _stage = s;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_running?.cancel());
    super.dispose();
  }
}
