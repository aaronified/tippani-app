import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../admin/admin_service.dart';
import '../admin/server_files.dart';
import '../checks/checks_service.dart';
import '../imports/import_picker.dart';
import '../imports/import_service.dart';
import '../account/account_service.dart';
import '../account/preferences.dart';
import '../l10n/l10n.dart';
import '../metadata/metadata_service.dart';
import '../people/people_console.dart';
import '../people/people_directory.dart';
import '../tools/cover_search.dart';
import '../sources/source_picker.dart';
import '../sources/sources_service.dart';
import '../people/people_service.dart';
import '../quiz/quiz.dart';
import '../share/share_people.dart';
import '../anthologies/anthologies.dart';
import '../anthologies/offline_anthologies.dart';
import '../boards/board_service.dart';
import '../library/cover_cache.dart';
import '../tools/context_store.dart';
import '../tools/quote_context.dart';
import '../tools/work_details_source.dart';
import '../search/search_service.dart';
import '../tags/tag_service.dart';
import '../tools/server_tools.dart';
import '../tools/work_lookup.dart';
import '../app_controller.dart';
import '../library/library_backup.dart';
import '../library/library_store.dart';
import '../sync/auto_sync.dart';
import '../sync/fingerprint.dart';
import '../sync/pull_sync.dart';
import '../sync/push_sync.dart';
import '../settings/settings_backup.dart';
import '../settings/settings_store.dart';
import '../theme/theme_choice.dart';
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
      dialogTitle: tx('app.harness.save_your_backup'),
      fileName: fileName,
      bytes: bytes,
    );
    return saved != null;
  }

  @override
  Future<PickedFile?> pick() async {
    final f = await FilePicker.pickFile(
      dialogTitle: tx('app.harness.choose_a_tippani_backup'),
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
    this.people,
    this.directory,
    this.imports,
    this.checks,
    this.importPicker = const SystemImportPicker(),
    this.prefs,
    this.l10n,
    this.localeFetch,
    this.account,
    this.contextRules,
    this.peopleService,
    this.coverSearch,
    this.metadata,
    this.sources,
    this.sourcePicker = const SystemSourcePicker(),
    this.peopleConsole,
    this.admin,
    this.serverFiles = const SystemServerFiles(),
    this.quiz,
    this.details,
    this.contexts,
    this.anthologies,
    this.tools,
    this.tags,
    this.search,
    this.lookup,
    this.boards,
    Future<List<ChangelogEntry>> Function()? changelogLoader,
    this.showWhatsNew = true,
  }) : _changelogLoader = changelogLoader ?? loadChangelog;

  final AppFiles files;
  final AppLog log;
  final UpdateController updates;
  final BackupService backup;
  final BackupPicker picker;
  final SettingsStore settings;

  /// Where the app's colours come from (the phone's, a photo, or a palette); kept on this phone.
  late final ThemeChoice themeChoice = ThemeChoice(settings);

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

  /// Where the pictures of people (portraits, characters, signatures) for a shared quote come from.
  final SharePeopleSource? people;

  /// Everyone with a face on the server, kept on the phone, for the round portraits on a quote's chips.
  final PeopleDirectory? directory;

  /// Importing files on the server and reviewing what they staged. Null in a test about something else.
  final ImportService? imports;

  /// The server's checks: stray marks, corrections, times and places. Null in a test about something else.
  final ChecksService? checks;

  /// Choosing a file to import with the system's picker.
  final ImportPicker importPicker;

  /// The account's preferences (text size, colours, sections, language...), kept in step with the server's. Null
  /// in a test about something else.
  final PreferencesSource? prefs;

  /// The app's words in the language the reader chose. Null in a test about something else (English).
  final L10n? l10n;

  /// Reads the server's language files (`GET /locales`).
  final Future<Object?> Function()? localeFetch;

  /// The reader's account on the server: avatar, password, notifications, widget key.
  final AccountService? account;

  /// How much of a quote's source is shown around it, for everything and for one work.
  final ContextRules? contextRules;

  /// The pages of people and characters (and edits to a person) from the paired server.
  final PeopleService? peopleService;

  /// Finds pictures that could be a work's cover or poster, online. Null in a test about something else.
  final CoverSearch? coverSearch;

  /// What the server could still find out about the library's works, and the works saved twice. Null in a test
  /// about something else.
  final MetadataService? metadata;

  /// The source files (ebooks, subtitles) works' quotes were found in, on the paired server. Null in a test about
  /// something else.
  final SourcesService? sources;

  /// Choosing a source file from the phone.
  final SourcePicker sourcePicker;

  /// Every person and character the server keeps, for the metadata console and the editing on their pages.
  final PeopleConsole? peopleConsole;

  /// Running the server (users, jobs, backups, updates, folders, sources), for an admin account. Null in a test about
  /// something else.
  final AdminService? admin;

  /// The system's file pickers for the server's big backup files.
  final ServerFiles serverFiles;

  /// Fetches a work's description, genres and cast from the paired server. Null in a test about something else.
  final WorkDetailsSource? details;

  /// Fetches the stored context of a quote from the paired server. Null in a test about something else.
  final QuoteContextSource? contexts;

  /// The paired server's Daily Quiz and Practice. Null in a test that is about something else; without it the app
  /// has no Home tab.
  final QuizService? quiz;

  /// The paired server's anthologies. Null in a test that is about something else.
  final AnthologyService? anthologies;

  /// The paired server's bin and statistics. Null in a test that is about something else.
  final ServerTools? tools;

  /// The server's tags (their colours and styles) for the Tags page. Null in a test about something else.
  final TagService? tags;

  /// The server's search (it forgives typos). Null in a test about something else: the page then searches the phone.
  final ServerSearch? search;

  /// Finds a work's details through the paired server. Null in a test that is about something else.
  final WorkLookup? lookup;

  /// What the server holds for a board beyond its name and colour (picture, kind, order, hidden). Null in a test
  /// about something else.
  final BoardService? boards;

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
    final covers = CoverCache(controller);
    final directory = PairedPeopleDirectory(controller, covers);
    pull?.onFaces = directory.rememberFaces;
    final prefs = PairedPreferences(controller, settings);
    final anthologies = OfflineAnthologies(
      ServerAnthologies(controller),
      controller.offline,
      settings,
      lookup: library == null
          ? null
          : (kind, id) => _passageOf(library, kind, id),
    );
    final contextStore = FileContextStore(
      () async => Directory(
        '${(await getApplicationSupportDirectory()).path}/contexts',
      ),
    );
    controller.offline.whenCleared.add(contextStore.clear);
    // answers given with no server belong to the account that gave them
    controller.offline.whenCleared.add(() => settings.setQuizAnswers(''));
    final contexts = PairedQuoteContext(controller, store: contextStore);
    final l10n = L10n()..use(prefs.prefs.locale);
    Tr.current = l10n; // code with no screen (a service wording an error) speaks in the same language
    prefs.addListener(() => l10n.use(prefs.prefs.locale));
    final auto = push == null || pull == null
        ? null
        : AutoSync(
            push: push,
            pull: pull,
            controller: controller,
            log: appLog,
            after: [
              prefs.flush,
              anthologies.flush,
              () => keepContexts(library!, contexts),
            ],
          );
    // a change made with no server counts as something to send, so it goes up when the server next answers
    // and not only when the library changed
    void queued() {
      if (anthologies.pending.value > 0 || prefs.hasPending) {
        auto?.queueChanged();
      }
    }

    anthologies.pending.addListener(queued);
    prefs.addListener(queued);
    // a queue left by the last run is sent at this one's start too
    queued();
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
          SettingsBackup(
            settings,
            onRestored: controller.refresh,
            forget: controller.forget,
          ),
          if (library != null) LibraryBackup(library),
        ],
      ),
      picker: const SystemBackupPicker(),
      settings: settings,
      library: library,
      sync: push,
      pull: pull,
      auto: auto,
      runAutoSync: true,
      covers: covers,
      people: PairedSharePeople(controller, directory),
      directory: directory,
      imports: PairedImportService(controller),
      checks: PairedChecksService(controller),
      prefs: prefs,
      l10n: l10n,
      localeFetch: () =>
          controller.withClient<Object?>((c) => c.getJson('/locales')),
      account: PairedAccount(controller),
      contextRules: PairedContextRules(controller),
      peopleService: PairedPeopleService(controller),
      coverSearch: PairedCoverSearch(controller),
      metadata: PairedMetadataService(controller),
      sources: PairedSourcesService(controller),
      peopleConsole: PairedPeopleConsole(controller),
      admin: PairedAdminService(controller),
      quiz: ServerQuiz(controller, settings),
      details: PairedWorkDetails(controller),
      contexts: contexts,
      anthologies: anthologies,
      tools: PairedServerTools(controller),
      tags: PairedTagService(controller),
      search: PairedSearch(controller),
      lookup: PairedWorkLookup(controller),
      boards: library == null ? null : ServerBoards(controller, library),
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
    SharePeopleSource? people,
    PeopleDirectory? directory,
    ImportService? imports,
    ChecksService? checks,
    ImportPicker? importPicker,
    PreferencesSource? prefs,
    L10n? l10n,
    AccountService? account,
    ContextRules? contextRules,
    PeopleService? peopleService,
    CoverSearch? coverSearch,
    MetadataService? metadata,
    SourcesService? sources,
    SourcePicker? sourcePicker,
    PeopleConsole? peopleConsole,
    AdminService? admin,
    ServerFiles? serverFiles,
    QuizService? quiz,
    WorkDetailsSource? details,
    QuoteContextSource? contexts,
    AnthologyService? anthologies,
    ServerTools? tools,
    TagService? tags,
    ServerSearch? search,
    WorkLookup? lookup,
    BoardService? boards,
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
          SettingsBackup(
            settings,
            onRestored: controller?.refresh,
            forget: controller?.forget,
          ),
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
      people: people,
      directory: directory,
      imports: imports,
      checks: checks,
      importPicker: importPicker ?? const SystemImportPicker(),
      prefs: prefs,
      l10n: l10n,
      account: account,
      contextRules: contextRules,
      peopleService: peopleService,
      coverSearch: coverSearch,
      metadata: metadata,
      sources: sources,
      sourcePicker: sourcePicker ?? const SystemSourcePicker(),
      peopleConsole: peopleConsole,
      admin: admin,
      serverFiles: serverFiles ?? const SystemServerFiles(),
      quiz: quiz,
      details: details,
      contexts: contexts,
      anthologies: anthologies,
      tools: tools,
      tags: tags,
      search: search,
      lookup: lookup,
      boards: boards,
      changelogLoader: () async => changelog ?? const [],
      showWhatsNew: showWhatsNew,
    );
  }

  /// Opens the log's run and notes the version; called once from `main`.
  Future<void> start() => log.start(version: appVersion, files: files);

  /// Reads the account's preferences and the server's language files again (the app does this as it opens, and
  /// after pairing). A server that cannot be reached leaves what the phone holds.
  Future<void> refreshAccountSettings() async {
    await prefs?.refresh();
    final fetch = localeFetch;
    if (l10n != null && fetch != null) {
      try {
        l10n!.useServerFiles(await fetch());
      } on Object {
        // the languages the app ships are enough
      }
    }
  }
}

class _NoPicker implements BackupPicker {
  const _NoPicker();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;

  @override
  Future<PickedFile?> pick() async => null;
}

/// What the phone knows about the quote the server calls [serverId] in its [kind] table, drawn the way an
/// anthology's passage is, so one added with no server shows its words at once (ADR-0022).
Future<Map<String, Object?>?> _passageOf(
  LibraryStore library,
  String kind,
  int serverId,
) async {
  for (final q in await library.quotes()) {
    if (q.serverId != serverId) continue;
    final w = q.workId == null ? null : await library.work(q.workId!);
    if (entryKindOf(realmOfQuote(w)) != kind) continue;
    return {
      'quote': q.text,
      'color': q.color,
      'language': q.language,
      'favorite': q.favorite,
      'source': w?.title ?? '',
      'credit': w?.creator ?? '',
    };
  }
  return null;
}
