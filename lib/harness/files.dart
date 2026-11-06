import 'package:flutter/services.dart';

/// The app's own files: backups kept inside its private storage, the log, and a copy in the phone's
/// Downloads folder. One narrow interface over a native channel (`MainActivity.kt`), so the log and the
/// backups are tested against a fake that keeps bytes in memory.
///
/// WHY NATIVE AND NOT A PLUGIN: the Downloads copy goes through MediaStore, which needs no storage
/// permission from Android 10 on, and the private folders need nothing at all. A plugin would ask for
/// more than the app uses.
abstract interface class AppFiles {
  /// Writes a backup into the app's private storage.
  Future<bool> writeBackup(String name, Uint8List bytes);

  /// The names of the app's own backups, newest first.
  Future<List<String>> listBackups();

  Future<Uint8List?> readBackup(String name);

  Future<void> deleteBackup(String name);

  /// Copies [bytes] into the Downloads folder as [name]. Returns the name it was saved as, or null where
  /// the phone cannot (before Android 10).
  Future<String?> saveToDownloads(
    String name,
    Uint8List bytes, {
    String mime = 'application/json',
  });

  /// The log's own folder, apart from the backups, which are pruned by age.
  Future<bool> writeLog(String name, Uint8List bytes);

  Future<Uint8List?> readLog(String name);
}

/// The real thing: the channel `MainActivity.kt` answers.
class ChannelAppFiles implements AppFiles {
  const ChannelAppFiles();

  static const channel = MethodChannel('io.github.aaronified.tippani/files');

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> writeBackup(String name, Uint8List bytes) async =>
      await _call<bool>('writeInternal', {'name': name, 'bytes': bytes}) ??
      false;

  @override
  Future<List<String>> listBackups() async {
    final r = await _call<List<Object?>>('listInternal', {});
    return [for (final n in r ?? const []) n.toString()];
  }

  @override
  Future<Uint8List?> readBackup(String name) =>
      _call<Uint8List>('readInternal', {'name': name});

  @override
  Future<void> deleteBackup(String name) async {
    await _call<bool>('deleteInternal', {'name': name});
  }

  @override
  Future<String?> saveToDownloads(
    String name,
    Uint8List bytes, {
    String mime = 'application/json',
  }) => _call<String>('saveToDownloads', {
    'name': name,
    'bytes': bytes,
    'mime': mime,
  });

  @override
  Future<bool> writeLog(String name, Uint8List bytes) async =>
      await _call<bool>('writeLog', {'name': name, 'bytes': bytes}) ?? false;

  @override
  Future<Uint8List?> readLog(String name) =>
      _call<Uint8List>('readLog', {'name': name});
}

/// Bytes in memory, for tests.
class MemoryAppFiles implements AppFiles {
  final backups = <String, Uint8List>{};
  final downloads = <String, Uint8List>{};
  final logs = <String, Uint8List>{};

  /// Set false to see how a caller copes with a phone that cannot write.
  bool writable = true;

  @override
  Future<bool> writeBackup(String name, Uint8List bytes) async {
    if (!writable) return false;
    backups[name] = bytes;
    return true;
  }

  @override
  Future<List<String>> listBackups() async =>
      backups.keys.toList().reversed.toList();

  @override
  Future<Uint8List?> readBackup(String name) async => backups[name];

  @override
  Future<void> deleteBackup(String name) async => backups.remove(name);

  @override
  Future<String?> saveToDownloads(
    String name,
    Uint8List bytes, {
    String mime = 'application/json',
  }) async {
    if (!writable) return null;
    downloads[name] = bytes;
    return name;
  }

  @override
  Future<bool> writeLog(String name, Uint8List bytes) async {
    if (!writable) return false;
    logs[name] = bytes;
    return true;
  }

  @override
  Future<Uint8List?> readLog(String name) async => logs[name];
}
