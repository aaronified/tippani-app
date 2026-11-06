import '../harness/backup.dart';
import 'library_store.dart';

/// What a backup keeps of the library: every work, quote and tag. A restore REPLACES the library with the
/// file's, which is why the restore dialog says so in words. It is checked before anything is touched
/// ([check]), and written in one transaction, so a damaged file changes nothing.
class LibraryBackup implements BackupContributor {
  LibraryBackup(this._store, {this.onRestored});

  final LibraryStore _store;
  final Future<void> Function()? onRestored;

  @override
  String get key => 'library';

  @override
  Future<Object?> export() => _store.exportAll();

  Map<String, Object?>? _asMap(Object? data) =>
      data is Map ? Map<String, Object?>.from(data) : null;

  @override
  Future<void> check(Object? data) async {
    final map = _asMap(data);
    if (map == null) throw const BackupException(BackupProblem.damaged);
    try {
      SqliteLibraryStore.validate(map);
    } on LibraryException {
      throw const BackupException(BackupProblem.damaged);
    }
  }

  @override
  Future<void> restore(Object? data) async {
    final map = _asMap(data);
    if (map == null) throw const BackupException(BackupProblem.damaged);
    try {
      await _store.replaceAll(map);
    } on LibraryException {
      throw const BackupException(BackupProblem.damaged);
    }
    await onRestored?.call();
  }
}
