import 'dart:typed_data';

import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/admin/server_files.dart';
import 'package:tippani/api/server_call.dart';

/// A server's administration kept in memory, so the admin screens can be tested without one.
class FakeAdmin implements AdminService {
  FakeAdmin();

  @override
  bool available = true;

  final calls = <String>[];

  final usersList = <AdminUser>[
    const AdminUser(id: 1, username: 'alice', isAdmin: true),
    const AdminUser(id: 2, username: 'bob', isAdmin: false),
  ];
  String? refuseDelete;

  List<JobInfo> current = [];
  List<JobInfo> past = [];
  List<CommonJob> common = [];
  List<String> log = ['info: started'];

  BackupInfo? kept;
  String rightSecret = 'secret';
  bool safetyMade = false;
  final saved = <String>[];
  Uint8List backupBytes = Uint8List.fromList([1, 2, 3]);

  UpdateInfo update = const UpdateInfo(
    current: 'v3.6.0',
    latest: 'v3.7.0',
    available: true,
    canSelfUpdate: false,
    guidedCommand: 'docker compose pull',
  );

  List<MountInfo> mounts = [];
  bool withSources = false;
  int orphans = 0;

  Map<String, Object?> keys = {
    'tmdb_key_set': false,
    'google_scrape': false,
    'amazon_domain': '',
  };
  List<MetadataSourceRow> sources = const [
    MetadataSourceRow(source: 'tmdb', state: 'needed', areas: ['films']),
    MetadataSourceRow(
      source: 'openlibrary',
      state: 'builtin',
      areas: ['books'],
    ),
  ];
  int tested = 0;

  @override
  Future<List<AdminUser>> users() async => List.of(usersList);

  @override
  Future<void> addUser(String username, String password) async {
    calls.add('addUser $username');
    usersList.add(
      AdminUser(id: usersList.length + 1, username: username, isAdmin: false),
    );
  }

  @override
  Future<void> setAdmin(int id, bool admin) async {
    calls.add('setAdmin $id $admin');
    final i = usersList.indexWhere((u) => u.id == id);
    final u = usersList[i];
    usersList[i] = AdminUser(id: u.id, username: u.username, isAdmin: admin);
  }

  @override
  Future<void> deleteUser(int id) async {
    calls.add('deleteUser $id');
    if (refuseDelete != null) throw ServerException(refuseDelete!);
    usersList.removeWhere((u) => u.id == id);
  }

  @override
  Future<JobsPage> jobs({
    String view = 'past',
    String state = '',
    int limit = 40,
  }) async => view == 'current'
      ? JobsPage(
          current,
          running: current.where((j) => j.state == 'running').length,
        )
      : JobsPage(past);

  @override
  Future<List<CommonJob>> commonJobs() async => common;

  @override
  Future<JobInfo?> job(int id) async {
    for (final j in [...current, ...past]) {
      if (j.id == id) return j;
    }
    return null;
  }

  @override
  Future<List<String>> jobLog(int id) async => log;

  @override
  Future<void> stopJob(int id) async {
    calls.add('stop $id');
    current = [
      for (final j in current)
        if (j.id != id) j,
    ];
  }

  @override
  Future<void> stopAll() async {
    calls.add('stopAll');
    current = [];
  }

  @override
  Future<JobInfo?> rerun(int id) async {
    calls.add('rerun $id');
    return null;
  }

  @override
  Future<JobInfo?> startJob(String kind, Map<String, Object?> params) async {
    calls.add('start $kind');
    return null;
  }

  @override
  Future<BackupInfo?> backup() async => kept;

  @override
  Future<JobInfo?> createBackup({
    String password = '',
    String passphrase = '',
  }) async {
    calls.add('backup');
    if ((password.isEmpty ? passphrase : password) != rightSecret) {
      throw const ServerException('That password is not right.');
    }
    kept = const BackupInfo(
      name: 'tippani-backup.tippani',
      created: '2026-11-07',
      size: 2048,
      key: 'password',
      account: 'alice',
    );
    return const JobInfo(id: 90, kind: 'backup', state: 'succeeded');
  }

  @override
  Future<({String name, Uint8List bytes})> downloadBackup() async {
    calls.add('download');
    return (name: kept!.name, bytes: backupBytes);
  }

  @override
  Future<JobInfo?> createSafetyCopy({
    String password = '',
    String passphrase = '',
  }) async {
    calls.add('safety');
    if ((password.isEmpty ? passphrase : password) != rightSecret) {
      throw const ServerException('That password is not right.');
    }
    return const JobInfo(id: 91, kind: 'backup.safety', state: 'succeeded');
  }

  @override
  Future<({String name, Uint8List bytes})> downloadSafetyCopy(int jobId) async {
    calls.add('downloadSafety');
    safetyMade = true;
    return (name: 'safety.tippani', bytes: backupBytes);
  }

  @override
  Future<void> restoreKept({
    String password = '',
    String passphrase = '',
  }) async {
    calls.add('restoreKept');
    if (!safetyMade) throw const ServerException('Make a safety copy first.');
    if ((password.isEmpty ? passphrase : password) != rightSecret) {
      throw const ServerException('That password is not right.');
    }
  }

  @override
  Future<void> restoreUpload(
    Uint8List bytes,
    String fileName, {
    String password = '',
    String passphrase = '',
  }) async {
    calls.add('restoreUpload $fileName');
    if (!safetyMade) throw const ServerException('Make a safety copy first.');
  }

  @override
  Future<UpdateInfo> updateCheck() async => update;

  @override
  Future<UpdateInfo> setChannel(String channel) async {
    calls.add('channel $channel');
    update = UpdateInfo(
      current: update.current,
      latest: update.latest,
      available: update.available,
      channel: channel,
      guidedCommand: update.guidedCommand,
    );
    return update;
  }

  @override
  Future<void> applyUpdate() async => calls.add('apply');

  @override
  Future<String> updatePhase() async => '';

  @override
  Future<LibraryFolders> folders() async => LibraryFolders(
    mounts: mounts,
    backupWithSources: withSources,
    orphanFiles: orphans,
    orphanBytes: orphans * 1000,
  );

  @override
  Future<List<MountInfo>> saveMounts(List<MountInfo> next) async {
    calls.add('mounts ${next.map((m) => m.id).join(',')}');
    mounts = next;
    return next;
  }

  @override
  Future<bool> setBackupSources(bool include) async {
    withSources = include;
    return include;
  }

  @override
  Future<int> tidySources() async {
    final n = orphans;
    orphans = 0;
    return n;
  }

  @override
  Future<MetadataKeys> metadataKeys() async => MetadataKeys(keys);

  @override
  Future<MetadataKeys> saveMetadataKey(String field, Object value) async {
    calls.add('key $field=$value');
    if (value is bool) {
      keys[field] = value;
    } else {
      keys['${field}_set'] = '$value'.isNotEmpty;
    }
    return MetadataKeys(keys);
  }

  @override
  Future<List<MetadataSourceRow>> metadataSources() async => sources;

  @override
  Future<void> testSources([String? source]) async {
    tested++;
    calls.add('test ${source ?? 'all'}');
  }

  @override
  Future<void> reindexSearch() async => calls.add('reindex');
}

/// File pickers kept in memory.
class FakeServerFiles implements ServerFiles {
  final saved = <String, Uint8List>{};
  bool accept = true;
  ChosenFile? toPick;

  @override
  Future<bool> save(String fileName, Uint8List bytes, {String? title}) async {
    if (accept) saved[fileName] = bytes;
    return accept;
  }

  @override
  Future<ChosenFile?> pick() async => toPick;
}
