import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/server_call.dart';
import '../app_controller.dart';
import '../l10n/l10n.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
String _s(Object? v) => v == null ? '' : '$v';
bool _b(Object? v) => v == true;

/// One account on the server.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    this.createdAt = '',
  });

  final int id;
  final String username;
  final bool isAdmin;
  final String createdAt;

  static AdminUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = _s(j['username']);
    if (name.isEmpty) return null;
    return AdminUser(
      id: _int(j['id']),
      username: name,
      isAdmin: _b(j['is_admin']),
      createdAt: _s(j['created_at']),
    );
  }
}

/// One job the server queue ran, is running or has waiting.
class JobInfo {
  const JobInfo({
    required this.id,
    required this.kind,
    required this.state,
    this.subject = '',
    this.error = '',
    this.total = 0,
    this.done = 0,
    this.ahead = 0,
    this.username = '',
    this.own = false,
    this.rerunnable = false,
    this.createdAt,
    this.finishedAt,
    this.counts = const {},
  });

  final int id;
  final String kind, state, subject, error, username;
  final int total, done, ahead;
  final bool own, rerunnable;
  final DateTime? createdAt, finishedAt;
  final Map<String, int> counts;

  bool get live => state == 'queued' || state == 'running';

  static DateTime? _ms(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static JobInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['counts'];
    return JobInfo(
      id: _int(j['id']),
      kind: _s(j['kind']),
      state: _s(j['state']),
      subject: _s(j['subject']),
      error: _s(j['error']),
      total: _int(j['total']),
      done: _int(j['done']),
      ahead: _int(j['ahead']),
      username: _s(j['username']),
      own: _b(j['own']),
      rerunnable: _b(j['rerunnable']),
      createdAt: _ms(j['created_at']),
      finishedAt: _ms(j['finished_at']),
      counts: c is Map
          ? {
              for (final e in c.entries)
                if (e.value is num) '${e.key}': (e.value as num).toInt(),
            }
          : const {},
    );
  }
}

/// A page of jobs, with how many are running and waiting overall.
class JobsPage {
  const JobsPage(this.jobs, {this.running = 0, this.waiting = 0});
  final List<JobInfo> jobs;
  final int running, waiting;
}

/// A job the reader can start from the Common jobs list: its own name, what it runs with, and its last and current run.
class CommonJob {
  const CommonJob({
    required this.id,
    required this.kind,
    required this.params,
    this.adminOnly = false,
    this.last,
    this.current,
  });

  final String id, kind;
  final Map<String, Object?> params;
  final bool adminOnly;
  final JobInfo? last, current;

  static CommonJob? fromJson(Object? j) {
    if (j is! Map) return null;
    return CommonJob(
      id: _s(j['id']),
      kind: _s(j['kind']),
      params: j['params'] is Map
          ? Map<String, Object?>.from(j['params'] as Map)
          : const {},
      adminOnly: _b(j['admin_only']),
      last: JobInfo.fromJson(j['last']),
      current: JobInfo.fromJson(j['current']),
    );
  }
}

/// The backup the server keeps.
class BackupInfo {
  const BackupInfo({
    required this.name,
    this.created = '',
    this.size = 0,
    this.key = '',
    this.account = '',
  });

  final String name, created, key, account;
  final int size;

  /// What the archive is sealed with: 'password', 'passphrase', 'none' or 'unknown'.
  bool get needsPassword => key == 'password';
  bool get needsPassphrase => key == 'passphrase';

  static BackupInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = _s(j['name']);
    if (name.isEmpty) return null;
    return BackupInfo(
      name: name,
      created: _s(j['created']),
      size: _int(j['size']),
      key: _s(j['key']),
      account: _s(j['account']),
    );
  }
}

/// What a check for a new server version found.
class UpdateInfo {
  const UpdateInfo({
    this.current = '',
    this.latest = '',
    this.available = false,
    this.channel = 'stable',
    this.canSelfUpdate = false,
    this.guidedCommand = '',
    this.notesUrl = '',
    this.releaseName = '',
    this.publishedAt = '',
  });

  final String current, latest, channel, guidedCommand, notesUrl, releaseName;
  final String publishedAt;
  final bool available, canSelfUpdate;

  static UpdateInfo fromJson(Map<Object?, Object?> j) => UpdateInfo(
    current: _s(j['current']),
    latest: _s(j['latest']),
    available: _b(j['update_available']),
    channel: _s(j['channel']).isEmpty ? 'stable' : _s(j['channel']),
    canSelfUpdate: _b(j['can_self_update']),
    guidedCommand: _s(j['guided_command']),
    notesUrl: _s(j['notes_url']),
    releaseName: _s(j['release_name']),
    publishedAt: _s(j['published_at']),
  );
}

/// A folder of the server's disk that its library is read from.
class MountInfo {
  const MountInfo({
    required this.id,
    required this.label,
    required this.path,
    this.ok = true,
    this.error = '',
  });

  final String id, label, path, error;
  final bool ok;

  static MountInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    return MountInfo(
      id: _s(j['id']),
      label: _s(j['label']),
      path: _s(j['path']),
      ok: j['ok'] != false,
      error: _s(j['error']),
    );
  }
}

/// The folders, and what a tidy-up of their saved files would do.
class LibraryFolders {
  const LibraryFolders({
    this.mounts = const [],
    this.backupWithSources = false,
    this.orphanFiles = 0,
    this.orphanBytes = 0,
    this.missingFiles = 0,
  });

  final List<MountInfo> mounts;
  final bool backupWithSources;
  final int orphanFiles, orphanBytes, missingFiles;
}

/// The keys and switches the metadata sources use; a secret is only ever reported as set or not.
class MetadataKeys {
  const MetadataKeys(this.raw);
  final Map<String, Object?> raw;

  bool isSet(String field) => _b(raw['${field}_set']);
  bool flag(String field) => _b(raw[field]);
  String text(String field) => _s(raw[field]);
}

/// One source the server asks for metadata, with how it stands.
class MetadataSourceRow {
  const MetadataSourceRow({
    required this.source,
    required this.state,
    this.areas = const [],
    this.works = 0,
    this.people = 0,
  });

  final String source, state;
  final List<String> areas;
  final int works, people;
}

/// Where the server's administration comes from. An interface so a test can stand in for the server. Every call
/// throws a [ServerException] (with words for the reader) when it cannot be done.
abstract class AdminService {
  bool get available;

  Future<List<AdminUser>> users();
  Future<void> addUser(String username, String password);
  Future<void> setAdmin(int id, bool admin);
  Future<void> deleteUser(int id);

  Future<JobsPage> jobs({
    String view = 'past',
    String state = '',
    int limit = 40,
  });
  Future<List<CommonJob>> commonJobs();
  Future<JobInfo?> job(int id);

  /// What a job logged, oldest first, as "level: line".
  Future<List<String>> jobLog(int id);
  Future<void> stopJob(int id);
  Future<void> stopAll();
  Future<JobInfo?> rerun(int id);
  Future<JobInfo?> startJob(String kind, Map<String, Object?> params);

  Future<BackupInfo?> backup();

  /// Makes a backup (a job), sealed with the account's [password] or a [passphrase]. Returns the job.
  Future<JobInfo?> createBackup({String password = '', String passphrase = ''});
  Future<({String name, Uint8List bytes})> downloadBackup();

  /// Makes the copy of the current library a restore asks for first, and brings it to the phone.
  Future<JobInfo?> createSafetyCopy({
    String password = '',
    String passphrase = '',
  });
  Future<({String name, Uint8List bytes})> downloadSafetyCopy(int jobId);

  /// Replaces the server's library with the kept backup.
  Future<void> restoreKept({String password = '', String passphrase = ''});

  /// Replaces the server's library with a backup file from the phone.
  Future<void> restoreUpload(
    Uint8List bytes,
    String fileName, {
    String password = '',
    String passphrase = '',
  });

  Future<UpdateInfo> updateCheck();
  Future<UpdateInfo> setChannel(String channel);
  Future<void> applyUpdate();
  Future<String> updatePhase();

  Future<LibraryFolders> folders();
  Future<List<MountInfo>> saveMounts(List<MountInfo> mounts);
  Future<bool> setBackupSources(bool include);
  Future<int> tidySources();

  Future<MetadataKeys> metadataKeys();
  Future<MetadataKeys> saveMetadataKey(String field, Object value);
  Future<List<MetadataSourceRow>> metadataSources();
  Future<void> testSources([String? source]);
  Future<void> reindexSearch();
}

/// The paired server's administration.
class PairedAdminService implements AdminService {
  PairedAdminService(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired && _controller.isAdmin;

  /// A call where a 401 means "the password you gave is wrong", not "this phone was unpaired".
  Future<T> _credentialed<T>(Future<T> Function(ApiClient c) run) async {
    if (!_controller.paired) {
      throw const ServerException('This phone is not paired with a server.');
    }
    final c = _controller.authedClient();
    if (c == null) {
      throw const ServerException('This phone is not paired with a server.');
    }
    try {
      return await run(c);
    } on ApiException catch (e) {
      throw ServerException(switch (e.failure) {
        ApiFailure.unauthorised => tx(
          'app.admin_service.that_password_is_not_right',
        ),
        ApiFailure.network => tx(
          'app.admin_service.the_server_could_not_be_reached',
        ),
        ApiFailure.timeout => tx(
          'app.admin_service.the_server_took_too_long_to',
        ),
        _ => e.detail.isNotEmpty ? e.detail : 'The server could not do that.',
      });
    } finally {
      c.close();
    }
  }

  Map<String, Object?> _creds(String password, String passphrase) => {
    if (password.isNotEmpty) 'password': password,
    if (passphrase.isNotEmpty) 'passphrase': passphrase,
  };

  /// What a restore sends. A backup from before 1.4.1 carries no key, so the server asks for the word
  /// `RESTORE` as well, to stand for intent; a sealed backup ignores the field. It goes every time, because
  /// the screen already made the reader press Restore on a danger dialog, and what the reader typed does not
  /// say whether the backup was sealed.
  Map<String, Object?> _restoreCreds(String password, String passphrase) => {
    ..._creds(password, passphrase),
    'confirm': 'RESTORE',
  };

  @override
  Future<List<AdminUser>> users() => serverCall(_controller, (c) async {
    final r = await c.getJson('/admin/users');
    final list = r is Map ? r['users'] : null;
    return [
      if (list is List)
        for (final u in list)
          if (AdminUser.fromJson(u) != null) AdminUser.fromJson(u)!,
    ];
  });

  @override
  Future<void> addUser(String username, String password) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/admin/users', {
          'username': username,
          'password': password,
        });
      });

  @override
  Future<void> setAdmin(int id, bool admin) =>
      serverCall<void>(_controller, (c) async {
        await c.patchJson('/admin/users/$id', {'is_admin': admin});
      });

  @override
  Future<void> deleteUser(int id) => serverCall<void>(_controller, (c) async {
    await c.delete('/admin/users/$id');
  });

  @override
  Future<JobsPage> jobs({
    String view = 'past',
    String state = '',
    int limit = 40,
  }) => serverCall(_controller, (c) async {
    final q = <String, String>{
      'view': view,
      if (state.isNotEmpty) 'state': state,
      'limit': '$limit',
    };
    final r = await c.getJson('/jobs?${Uri(queryParameters: q).query}');
    final m = r is Map ? r : const {};
    final list = m['jobs'];
    return JobsPage(
      [
        if (list is List)
          for (final j in list)
            if (JobInfo.fromJson(j) != null) JobInfo.fromJson(j)!,
      ],
      running: _int(m['running']),
      waiting: _int(m['waiting']),
    );
  });

  @override
  Future<List<CommonJob>> commonJobs() => serverCall(_controller, (c) async {
    final r = await c.getJson('/jobs/common');
    final list = r is Map ? r['jobs'] : null;
    return [
      if (list is List)
        for (final j in list)
          if (CommonJob.fromJson(j) != null) CommonJob.fromJson(j)!,
    ];
  });

  @override
  Future<JobInfo?> job(int id) => serverCall(_controller, (c) async {
    final r = await c.getJson('/jobs/$id');
    return r is Map ? JobInfo.fromJson(r['job']) : null;
  });

  @override
  Future<List<String>> jobLog(int id) => serverCall(_controller, (c) async {
    final r = await c.getJson('/jobs/$id?log_after=0');
    final lines = r is Map ? r['lines'] : null;
    return [
      if (lines is List)
        for (final l in lines)
          if (l is Map) '${_s(l['level'])}: ${_s(l['line'])}',
    ];
  });

  @override
  Future<void> stopJob(int id) => serverCall<void>(_controller, (c) async {
    await c.postJson('/jobs/$id/stop', const {});
  });

  @override
  Future<void> stopAll() => serverCall<void>(_controller, (c) async {
    await c.postJson('/jobs/stop-all', const {});
  });

  @override
  Future<JobInfo?> rerun(int id) => serverCall(_controller, (c) async {
    final r = await c.postJson('/jobs/$id/rerun', const {});
    return r is Map ? JobInfo.fromJson(r['job']) : null;
  });

  @override
  Future<JobInfo?> startJob(String kind, Map<String, Object?> params) =>
      serverCall(_controller, (c) async {
        final r = await c.postJson('/jobs', {'kind': kind, 'params': params});
        return r is Map ? JobInfo.fromJson(r['job']) : null;
      });

  @override
  Future<BackupInfo?> backup() => serverCall(_controller, (c) async {
    final r = await c.getJson('/admin/backup');
    return r is Map ? BackupInfo.fromJson(r['backup']) : null;
  });

  @override
  Future<JobInfo?> createBackup({
    String password = '',
    String passphrase = '',
  }) => _credentialed((c) async {
    final r = await c.postJson('/admin/backup', _creds(password, passphrase));
    return r is Map ? JobInfo.fromJson(r['job']) : null;
  });

  @override
  Future<({String name, Uint8List bytes})> downloadBackup() =>
      serverCall(_controller, (c) async {
        final info = await c.getJson('/admin/backup');
        final b = info is Map ? BackupInfo.fromJson(info['backup']) : null;
        if (b == null) {
          throw const ServerException(
            'There is no backup on the server yet. Make one first.',
          );
        }
        final bytes = await c.getBytes('/admin/backup/download');
        return (name: b.name, bytes: bytes);
      });

  @override
  Future<JobInfo?> createSafetyCopy({
    String password = '',
    String passphrase = '',
  }) => _credentialed((c) async {
    final r = await c.postJson(
      '/admin/backup/safety',
      _creds(password, passphrase),
    );
    return r is Map ? JobInfo.fromJson(r['job']) : null;
  });

  @override
  Future<({String name, Uint8List bytes})> downloadSafetyCopy(int jobId) =>
      serverCall(_controller, (c) async {
        final r = await c.getJson('/jobs/$jobId/result');
        final m = r is Map ? (r['result'] is Map ? r['result'] as Map : r) : {};
        final url = _s(m['url']);
        final name = _s(m['name']);
        if (url.isEmpty) {
          throw const ServerException(
            'The server did not say where the safety copy is.',
          );
        }
        // the bare API path the server gave; taking it is what tells the server the copy was fetched
        final path = url.replaceFirst(RegExp(r'^/?api'), '');
        final bytes = await c.getBytes(path);
        return (
          name: name.isEmpty ? 'safety-copy.tippani' : name,
          bytes: bytes,
        );
      });

  @override
  Future<void> restoreKept({String password = '', String passphrase = ''}) =>
      _credentialed<void>((c) async {
        await c.postJson('/admin/restore', _restoreCreds(password, passphrase));
      });

  @override
  Future<void> restoreUpload(
    Uint8List bytes,
    String fileName, {
    String password = '',
    String passphrase = '',
  }) => _credentialed<void>((c) async {
    await c.postFile(
      '/admin/restore/upload',
      'file',
      bytes,
      fileName,
      fields: _restoreCreds(
        password,
        passphrase,
      ).map((k, v) => MapEntry(k, '$v')),
    );
  });

  @override
  Future<UpdateInfo> updateCheck() => serverCall(_controller, (c) async {
    final r = await c.getJson('/admin/update/check');
    return UpdateInfo.fromJson(r is Map ? r : const {});
  });

  @override
  Future<UpdateInfo> setChannel(String channel) =>
      serverCall(_controller, (c) async {
        await c.postJson('/admin/update/channel', {'channel': channel});
        final r = await c.getJsonLive('/admin/update/check');
        return UpdateInfo.fromJson(r is Map ? r : const {});
      });

  @override
  Future<void> applyUpdate() => serverCall<void>(_controller, (c) async {
    await c.postJson('/admin/update/apply', {'confirm': 'UPDATE'});
  });

  @override
  Future<String> updatePhase() => serverCall(_controller, (c) async {
    final r = await c.getJson('/admin/update/state');
    return r is Map ? _s(r['phase']) : '';
  });

  @override
  Future<LibraryFolders> folders() => serverCall(_controller, (c) async {
    final m = await c.getJson('/admin/mounts');
    final b = await c.getJson('/admin/backup/sources');
    final o = await c.getJson('/admin/maintenance/sources');
    final list = m is Map ? m['mounts'] : null;
    return LibraryFolders(
      mounts: [
        if (list is List)
          for (final x in list)
            if (MountInfo.fromJson(x) != null) MountInfo.fromJson(x)!,
      ],
      backupWithSources: b is Map && _b(b['include']),
      orphanFiles: o is Map ? _int(o['orphan_files']) : 0,
      orphanBytes: o is Map ? _int(o['orphan_bytes']) : 0,
      missingFiles: o is Map ? _int(o['missing_files']) : 0,
    );
  });

  @override
  Future<List<MountInfo>> saveMounts(List<MountInfo> mounts) =>
      serverCall(_controller, (c) async {
        final r = await c.putJson('/admin/mounts', {
          'mounts': [
            for (final m in mounts)
              {'id': m.id, 'label': m.label, 'path': m.path},
          ],
        });
        final list = r is Map ? r['mounts'] : null;
        return [
          if (list is List)
            for (final x in list)
              if (MountInfo.fromJson(x) != null) MountInfo.fromJson(x)!,
        ];
      });

  @override
  Future<bool> setBackupSources(bool include) => serverCall(_controller, (
    c,
  ) async {
    final r = await c.putJson('/admin/backup/sources', {'include': include});
    return r is Map && _b(r['include']);
  });

  @override
  Future<int> tidySources() => serverCall(_controller, (c) async {
    final r = await c.postJson('/admin/maintenance/sources/sweep', const {});
    return r is Map ? _int(r['removed']) : 0;
  });

  @override
  Future<MetadataKeys> metadataKeys() => serverCall(_controller, (c) async {
    final r = await c.getJson('/admin/metadata-keys');
    return MetadataKeys(asMap(r));
  });

  @override
  Future<MetadataKeys> saveMetadataKey(String field, Object value) =>
      serverCall(_controller, (c) async {
        await c.putJson('/admin/metadata-keys', {field: value});
        final r = await c.getJsonLive('/admin/metadata-keys');
        return MetadataKeys(asMap(r));
      });

  @override
  Future<List<MetadataSourceRow>> metadataSources() =>
      serverCall(_controller, (c) async {
        final r = await c.getJson('/metadata/status');
        final list = r is Map ? r['sources'] : null;
        return [
          if (list is List)
            for (final x in list)
              if (x is Map)
                MetadataSourceRow(
                  source: _s(x['source']),
                  state: _s(x['state']),
                  areas: [
                    if (x['areas'] is List)
                      for (final a in x['areas'] as List) '$a',
                  ],
                  works: _int(x['works']),
                  people: _int(x['people']),
                ),
        ];
      });

  @override
  Future<void> testSources([String? source]) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/admin/metadata/test', {'source': ?source});
      });

  @override
  Future<void> reindexSearch() => serverCall<void>(_controller, (c) async {
    await c.postJson('/admin/search/reindex', const {});
  });
}

/// Gives the screens below it the [AdminService].
class AdminServiceScope extends InheritedWidget {
  const AdminServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final AdminService? service;

  static AdminService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminServiceScope>()?.service;

  @override
  bool updateShouldNotify(AdminServiceScope old) => old.service != service;
}
