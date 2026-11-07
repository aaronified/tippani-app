import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the reader chose.
class ChosenFile {
  const ChosenFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The biggest server backup the phone will carry in memory, either way.
const maxServerFileBytes = 300 * 1024 * 1024;

class ServerFileTooBig implements Exception {
  const ServerFileTooBig();
  @override
  String toString() =>
      'That file is too big for the phone to carry (over 300 MB). Use the server itself.';
}

/// The system's own pickers for the big files of server administration (backups). Tests hand the harness a fake.
abstract interface class ServerFiles {
  /// Saves [bytes] as [fileName] where the reader chooses; true when it was, false when cancelled.
  Future<bool> save(String fileName, Uint8List bytes, {String title});

  /// Lets the reader choose a backup file; null when cancelled. Throws [ServerFileTooBig] for one over the limit.
  Future<ChosenFile?> pick();
}

class SystemServerFiles implements ServerFiles {
  const SystemServerFiles();

  @override
  Future<bool> save(
    String fileName,
    Uint8List bytes, {
    String title = 'Save the backup',
  }) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
    );
    return saved != null;
  }

  @override
  Future<ChosenFile?> pick() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choose a backup from the server',
      type: FileType.any,
    );
    if (f == null) return null;
    final size = await f.length();
    if (size != null && size > maxServerFileBytes) {
      throw const ServerFileTooBig();
    }
    return ChosenFile(f.name, await f.readAsBytes());
  }
}
