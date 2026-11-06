import 'dart:convert';
import 'dart:typed_data';

import 'files.dart';
import 'version.dart';

/// The backup file's format name and version. A file with another name is not ours; a file with a newer
/// version came from an app that knows more than this one, and is refused rather than half-read.
const backupFormat = 'tippani-app-backup';
const backupVersion = 1;

/// The most a backup file may be, so a wrong file picked by mistake is refused before it is read.
const maxBackupBytes = 8000000;

/// A part of the app that has something worth keeping. The harness registers its own (the settings);
/// each later feature (the offline capture queue, say) registers its own and gets backed up and restored
/// with no change here.
///
/// WHAT NEVER GOES IN A BACKUP: the device token. A backup file is copied to Downloads and may be shared,
/// and a token in it would be a credential lying around. Restoring a backup leaves the phone to pair
/// again, which is one QR scan.
abstract class BackupContributor {
  /// A short stable key, the name of this part's section in the file.
  String get key;

  /// What to keep, as JSON-encodable data.
  Future<Object?> export();

  /// Puts back what [export] gave. Receives null-safe, already-validated JSON of the right top-level
  /// shape for this key only; a contributor still checks its own fields.
  Future<void> restore(Object? data);
}

/// Everything a backup holds, ready to write.
class BackupDocument {
  const BackupDocument({
    required this.createdAt,
    required this.appVersion,
    required this.sections,
  });

  final DateTime createdAt;
  final String appVersion;
  final Map<String, Object?> sections;

  String toText() => const JsonEncoder.withIndent('  ').convert({
    'format': backupFormat,
    'version': backupVersion,
    'app_version': appVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'sections': sections,
  });
}

/// Why a file could not be restored.
enum BackupProblem { tooBig, notJson, notOurs, tooNew, noSections }

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;

  @override
  String toString() => 'BackupException($problem)';
}

/// Reads a backup file's bytes into a document, or says why not.
BackupDocument parseBackup(Uint8List bytes) {
  if (bytes.length > maxBackupBytes) {
    throw const BackupException(BackupProblem.tooBig);
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const BackupException(BackupProblem.notJson);
  }
  if (json is! Map || json['format'] != backupFormat) {
    throw const BackupException(BackupProblem.notOurs);
  }
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const BackupException(BackupProblem.notOurs);
  }
  if (version > backupVersion) {
    throw const BackupException(BackupProblem.tooNew);
  }
  final sections = json['sections'];
  if (sections is! Map || sections.isEmpty) {
    throw const BackupException(BackupProblem.noSections);
  }
  return BackupDocument(
    createdAt:
        DateTime.tryParse('${json['created_at']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    appVersion: json['app_version'] is String
        ? json['app_version'] as String
        : '',
    sections: {for (final e in sections.entries) '${e.key}': e.value},
  );
}

String backupFileName(DateTime when) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'tippani-app-backup-${when.year}${two(when.month)}${two(when.day)}-${two(when.hour)}${two(when.minute)}.json';
}

/// Makes and restores backups from the registered contributors.
class BackupService {
  BackupService(
    this._files, {
    List<BackupContributor> contributors = const [],
    DateTime Function()? clock,
  }) : contributors = [...contributors],
       _clock = clock ?? DateTime.now;

  final AppFiles _files;
  final List<BackupContributor> contributors;
  final DateTime Function() _clock;

  /// Keeps this many of the app's own copies; older ones are removed after a new one is written.
  static const keep = 10;

  Future<BackupDocument> collect() async {
    final sections = <String, Object?>{};
    for (final c in contributors) {
      sections[c.key] = await c.export();
    }
    return BackupDocument(
      createdAt: _clock(),
      appVersion: appVersion,
      sections: sections,
    );
  }

  /// Writes a backup to the app's own storage and to Downloads. Returns the file name and whether the
  /// Downloads copy was made (it is not before Android 10).
  Future<({String name, bool inDownloads})?> backUp() async {
    final doc = await collect();
    final name = backupFileName(doc.createdAt);
    final bytes = Uint8List.fromList(utf8.encode(doc.toText()));
    if (!await _files.writeBackup(name, bytes)) return null;
    final saved = await _files.saveToDownloads(name, bytes);
    final all = await _files.listBackups();
    for (final old in all.skip(keep)) {
      await _files.deleteBackup(old);
    }
    return (name: name, inDownloads: saved != null);
  }

  /// The app's own copies, newest first.
  Future<List<String>> copies() => _files.listBackups();

  Future<Uint8List?> readCopy(String name) => _files.readBackup(name);

  /// Puts back every section of [doc] that a registered contributor owns, and returns the keys it
  /// restored and the keys in the file that nothing here owns (a backup from a build with more features).
  Future<({List<String> restored, List<String> ignored})> restore(
    BackupDocument doc,
  ) async {
    final restored = <String>[];
    final ignored = <String>[];
    for (final e in doc.sections.entries) {
      final owner = contributors.where((c) => c.key == e.key).firstOrNull;
      if (owner == null) {
        ignored.add(e.key);
        continue;
      }
      await owner.restore(e.value);
      restored.add(e.key);
    }
    return (restored: restored, ignored: ignored);
  }
}
