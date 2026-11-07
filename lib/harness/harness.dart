import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../anthologies/anthologies.dart';
import '../library/cover_cache.dart';
import '../tools/quote_context.dart';
import '../tools/work_details_source.dart';
import '../tools/server_tools.dart';
import '../tools/work_lookup.dart';
import '../app_controller.dart';
import '../library/library_backup.dart';
import '../library/library_store.dart';
import '../sync/auto_sync.dart';
import '../sync/pull_sync.dart';
import '../sync/push_sync.dart';
import '../settings/settings_backup.dart';
import '../settings/settings_store.dart';
import 'apk_install.dart';
import 'app_log.dart';
import 'backup.dart';
import 'changelog.dart';
import 'files.dart';
import 'update_check.dart';
import 'update_controller.dart';
import 'version.dart';

/// A file the reader chose to restore.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Saving and choosing the backup file with the system's own pickers. Tests hand the harness a fake.
abstract interface class BackupPicker {
  /// Saves [bytes] as [fileName] where the reader chooses; true when it was, false when cancelled.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Lets the reader choose a file; null when cancelled. Throws [BackupException] for a file too big.
  Future<PickedFile?> pick();
}

class SystemBackupPicker implements BackupPicker {
  const SystemBackupPicker();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save your backup',
      fileName: fileName,
      bytes: bytes,
    );
    return saved != null;
  }

  @override
  Future<PickedFile?> pick() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choose a Tippani backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (f == null) return null;
    final size = await f.length();
    if (size != null && size > maxBackupBytes) {
      throw const BackupException(BackupProblem.tooBig);
    }
    return PickedFile(f.name, await f.readAsBytes());
  }
}

/// Everything every screen of the app can rely on, built once: the log, the update check, the backups,
/// the changelog. It is the base the feature screens (pairing, capture, quotes) stand on, so a new screen
/// gets a log line, a backup section and an update toast without writing any of them.
class Harness {
  Harness({
    required this.files,
    required this.log,
    required this.updates,
    required this.backup,
    required this.picker,
    required this.settings,
    this.library,
    this.sync,
    this.pull,
    this.auto,
    this.runAutoSync = false,
    this.covers,
    this.details,
    this.contexts,
    this.anthologies,
    this.tools,
    this.lookup,
    Future<List<ChangelogEntry>> Function()? changelogLoader,
    this.showWhatsNew = true,
  }) : _changelogLoader = changelogLoader ?? loadChangelog;

  final AppFiles files;
  final AppLog log;
  final UpdateController updates;
  final BackupService backup;
  final BackupPicker picker;
  final SettingsStore settings;

  /// The phone's own library of works and quotes, which is what lets the app work with no server. Null
  /// only in a test that is about something else.
  final LibraryStore? library;

  /// Sends the library to the paired server. One for the whole app, so leaving its screen mid-push and
  /// coming back cannot start a second push that sends the same items again.
  final PushSync? sync;

  /// Brings the server's library down and sends the phone's edits up. One for the whole app, for the same
  /// reason as [sync].
  final PullSync? pull;

  /// Keeps the phone and the server in step by itself and holds the conflicts it finds. Null in a test that is
  /// about something else.
  final AutoSync? auto;

  /// Whether the app starts [auto] when it opens. Off in tests, where a timer left running fails the test.
  final bool runAutoSync;

  /// Fetches and keeps cover pictures from the paired server. Null in a test that is about something else.
  final CoverSource? covers;

  /// Fetches a work's description, genres and cast from the paired server. Null in a test about something else.
  final WorkDetailsSource? details;

  /// Fetches the stored context of a quote from the paired server. Null in a test about something else.
  final QuoteContextSource? contexts;

  /// The paired server's anthologies. Null in a test that is about something else.
  final AnthologyService? anthologies;

  /// The paired server's bin and statistics. Null in a test that is about something else.
  final ServerTools? tools;

  /// Finds a work's details through the paired server. Null in a test that is about something else.
  final WorkLookup? lookup;

  /// Whether the first start of a new version shows what changed. Tests that are about something else
  /// turn it off so a dialog does not cover the screen under test.
  final bool showWhatsNew;

  final Future<List<ChangelogEntry>> Function() _changelogLoader;
  List<ChangelogEntry>? _changelog;

  Future<List<ChangelogEntry>> changelog() async =>
      _changelog ??= await _changelogLoader();

  /// The real harness, for the app.
  static Harness open(
    SettingsStore settings,
    AppController controller, {
    LibraryStore? library,
  }) {
    const files = ChannelAppFiles();
    final push = library == null
        ? null
        : PushSync(library, controller, log: appLog);
    final pull = library == null
        ? null
        : PullSync(library, controller, log: appLog);
    return Harness(
      files: files,
      log: appLog,
      updates: UpdateController(
        check: GitHubReleaseCheck(client: http.Client()),
        installer: OtaApkInstaller(),
        log: appLog,
      ),
      backup: BackupService(
        files,
        contributors: [
          SettingsBackup(settings, onRestored: controller.refresh),
          if (library != null) LibraryBackup(library),
        ],
      ),
      picker: const SystemBackupPicker(),
      settings: settings,
      library: library,
      sync: push,
      pull: pull,
      auto: push == null || pull == null
          ? null
          : AutoSync(
              push: push,
              pull: pull,
              controller: controller,
              log: appLog,
            ),
      runAutoSync: true,
      covers: CoverCache(controller),
      details: PairedWorkDetails(controller),
      contexts: PairedQuoteContext(controller),
      anthologies: ServerAnthologies(controller),
      tools: PairedServerTools(controller),
      lookup: PairedWorkLookup(controller),
    );
  }

  /// A harness with nothing real in it, for tests: bytes in memory, an update check that finds nothing, an
  /// installer that does nothing, and no "what is new" dialog.
  factory Harness.fake(
    SettingsStore settings, {
    AppController? controller,
    AppFiles? files,
    AppLog? log,
    ReleaseCheck? check,
    ApkInstaller? installer,
    BackupPicker? picker,
    LibraryStore? library,
    CoverSource? covers,
    WorkDetailsSource? details,
    QuoteContextSource? contexts,
    AnthologyService? anthologies,
    ServerTools? tools,
    WorkLookup? lookup,
    List<ChangelogEntry>? changelog,
    bool showWhatsNew = false,
  }) {
    final f = files ?? MemoryAppFiles();
    final l = log ?? AppLog();
    final push = library == null || controller == null
        ? null
        : PushSync(library, controller, log: l);
    final pull = library == null || controller == null
        ? null
        : PullSync(library, controller, log: l);
    return Harness(
      files: f,
      log: l,
      updates: UpdateController(
        check: check ?? FixedReleaseCheck(const UpToDate()),
        installer: installer ?? const NullApkInstaller(),
        log: l,
      ),
      backup: BackupService(
        f,
        contributors: [
          SettingsBackup(settings, onRestored: controller?.refresh),
          if (library != null) LibraryBackup(library),
        ],
      ),
      picker: picker ?? const _NoPicker(),
      settings: settings,
      library: library,
      sync: push,
      pull: pull,
      auto: push == null || pull == null || controller == null
          ? null
          : AutoSync(push: push, pull: pull, controller: controller, log: l),
      covers: covers,
      details: details,
      contexts: contexts,
      anthologies: anthologies,
      tools: tools,
      lookup: lookup,
      changelogLoader: () async => changelog ?? const [],
      showWhatsNew: showWhatsNew,
    );
  }

  /// Opens the log's run and notes the version; called once from `main`.
  Future<void> start() => log.start(version: appVersion, files: files);
}

class _NoPicker implements BackupPicker {
  const _NoPicker();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;

  @override
  Future<PickedFile?> pick() async => null;
}
