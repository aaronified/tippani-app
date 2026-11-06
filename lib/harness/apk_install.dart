import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';

import 'files.dart';

/// Why an install did not happen.
enum InstallFailure {
  /// The download did not finish.
  download,

  /// The file is not the one the release published (its SHA-256 differs).
  checksum,

  /// Android would not let the app install: "install unknown apps" is off for it.
  notAllowed,

  /// Android's installer would not open.
  install,

  /// The reader stopped it.
  cancelled,

  /// Something in the plugin went wrong.
  internal,
}

/// One step of getting an update onto the phone.
class InstallEvent {
  const InstallEvent.downloading(int this.percent)
    : installing = false,
      failure = null;
  const InstallEvent.installing()
    : percent = null,
      installing = true,
      failure = null;
  const InstallEvent.failed(InstallFailure this.failure)
    : percent = null,
      installing = false;

  /// 0 to 100 while downloading.
  final int? percent;

  /// Android's installer is open on the file.
  final bool installing;
  final InstallFailure? failure;
}

/// Downloads an APK and hands it to Android's installer. Narrow enough that tests fake it.
abstract interface class ApkInstaller {
  Stream<InstallEvent> install(
    String url, {
    required String fileName,
    String? sha256,
  });

  /// The size and checksum of an update already downloaded, so the app can open the installer on it
  /// again instead of downloading it twice.
  Future<({int size, String? sha256})?> kept(String fileName);

  /// Opens the installer on an update already downloaded.
  Stream<InstallEvent> installFile(String fileName);

  Future<void> cancel();
}

/// An installer for a platform that has none (a test, a desktop run).
class NullApkInstaller implements ApkInstaller {
  const NullApkInstaller();

  @override
  Stream<InstallEvent> install(
    String url, {
    required String fileName,
    String? sha256,
  }) => Stream.value(const InstallEvent.failed(InstallFailure.internal));

  @override
  Future<({int size, String? sha256})?> kept(String fileName) async => null;

  @override
  Stream<InstallEvent> installFile(String fileName) =>
      Stream.value(const InstallEvent.failed(InstallFailure.internal));

  @override
  Future<void> cancel() async {}
}

/// An installer that plays back fixed events, for tests.
class FixedApkInstaller implements ApkInstaller {
  FixedApkInstaller(this.events, {this.keptFile});

  final List<InstallEvent> events;
  ({int size, String? sha256})? keptFile;
  final asked = <({String url, String fileName, String? sha256})>[];
  int installFileCalls = 0;
  int cancels = 0;

  @override
  Stream<InstallEvent> install(
    String url, {
    required String fileName,
    String? sha256,
  }) async* {
    asked.add((url: url, fileName: fileName, sha256: sha256));
    for (final e in events) {
      yield e;
    }
  }

  @override
  Future<({int size, String? sha256})?> kept(String fileName) async => keptFile;

  @override
  Stream<InstallEvent> installFile(String fileName) async* {
    installFileCalls++;
    yield const InstallEvent.installing();
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// [ApkInstaller] through ota_update. It downloads into `files/ota_update/<fileName>` in the app's own
/// storage, which needs no storage permission, and opens Android's installer on it through a
/// FileProvider (declared in AndroidManifest.xml).
///
/// ota_update's stream can go quiet without ending: 7.1.0 drops a download the server resets without a
/// status and leaves the stream open. So a download that says nothing for [stall] has failed.
class OtaApkInstaller implements ApkInstaller {
  OtaApkInstaller({this.stall = const Duration(seconds: 60)});

  final Duration stall;
  void Function()? _cancel;

  @override
  Future<({int size, String? sha256})?> kept(String fileName) async {
    try {
      final r = await ChannelAppFiles.channel.invokeMapMethod<String, Object?>(
        'keptApk',
        {'name': fileName},
      );
      final size = r?['size'];
      if (size is! int) return null;
      return (size: size, sha256: r?['sha256'] as String?);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<InstallEvent> installFile(String fileName) async* {
    try {
      final opened = await ChannelAppFiles.channel.invokeMethod<bool>(
        'installApk',
        {'name': fileName},
      );
      yield opened ?? false
          ? const InstallEvent.installing()
          : const InstallEvent.failed(InstallFailure.install);
    } on PlatformException {
      yield const InstallEvent.failed(InstallFailure.install);
    } on MissingPluginException {
      yield const InstallEvent.failed(InstallFailure.internal);
    }
  }

  @override
  Stream<InstallEvent> install(
    String url, {
    required String fileName,
    String? sha256,
  }) {
    final out = StreamController<InstallEvent>();
    StreamSubscription<OtaEvent>? listening;
    Timer? watchdog;
    void end([InstallEvent? last]) {
      if (out.isClosed) return;
      watchdog?.cancel();
      unawaited(listening?.cancel());
      _cancel = null;
      if (last != null) out.add(last);
      unawaited(out.close());
    }

    void watch() {
      watchdog?.cancel();
      watchdog = Timer(stall, () {
        unawaited(_stopPlugin());
        end(const InstallEvent.failed(InstallFailure.download));
      });
    }

    _cancel = () => end(const InstallEvent.failed(InstallFailure.cancelled));
    try {
      final events = OtaUpdate().execute(
        url,
        destinationFilename: fileName,
        sha256checksum: sha256,
      );
      watch();
      listening = events.listen(
        (event) {
          final next = _eventOf(event);
          if (next == null) return;
          if (next.installing || next.failure != null) {
            end(next);
          } else {
            out.add(next);
            watch();
          }
        },
        onError: (Object _) =>
            end(const InstallEvent.failed(InstallFailure.internal)),
        onDone: end,
      );
    } on Exception {
      end(const InstallEvent.failed(InstallFailure.internal));
    }
    return out.stream;
  }

  @override
  Future<void> cancel() async {
    final cancel = _cancel;
    if (cancel == null) return;
    await _stopPlugin();
    cancel();
  }

  Future<void> _stopPlugin() async {
    try {
      await OtaUpdate().cancel();
    } on Exception {
      // nothing to cancel, or no plugin: the stream ends either way
    }
  }

  static InstallEvent? _eventOf(OtaEvent event) => switch (event.status) {
    OtaStatus.DOWNLOADING => InstallEvent.downloading(
      (int.tryParse(event.value ?? '') ?? 0).clamp(0, 100),
    ),
    OtaStatus.INSTALLING => const InstallEvent.installing(),
    OtaStatus.INSTALLATION_DONE => null,
    OtaStatus.PERMISSION_NOT_GRANTED_ERROR => const InstallEvent.failed(
      InstallFailure.notAllowed,
    ),
    OtaStatus.DOWNLOAD_ERROR => const InstallEvent.failed(
      InstallFailure.download,
    ),
    OtaStatus.CHECKSUM_ERROR => const InstallEvent.failed(
      InstallFailure.checksum,
    ),
    // ota_update 7.1.0's Java and Dart list these two in opposite orders, so either may be the other;
    // both mean Android did not start installing
    OtaStatus.ALREADY_RUNNING_ERROR || OtaStatus.INSTALLATION_ERROR =>
      const InstallEvent.failed(InstallFailure.install),
    OtaStatus.INTERNAL_ERROR => const InstallEvent.failed(
      InstallFailure.internal,
    ),
    OtaStatus.CANCELED => const InstallEvent.failed(InstallFailure.cancelled),
  };
}
