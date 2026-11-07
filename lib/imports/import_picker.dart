import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'import_service.dart';

/// A file the reader chose to import.
class ImportFile {
  const ImportFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The server refuses a file over this size, so it is not sent.
const maxImportBytes = 5 * 1024 * 1024;

class ImportTooBig implements Exception {
  const ImportTooBig();
  @override
  String toString() => 'app.import_picker.that_file_is_over_5_mb';
}

/// Choosing the file to import with the system's own picker. Tests hand the harness a fake.
abstract interface class ImportPicker {
  /// The file the reader chose, or null if they backed out. Throws [ImportTooBig] for a file the importer would refuse.
  Future<ImportFile?> pick({List<String>? extensions});
}

class SystemImportPicker implements ImportPicker {
  const SystemImportPicker();

  @override
  Future<ImportFile?> pick({List<String>? extensions}) async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'app.import_picker.choose_a_file_to_import',
      type: FileType.custom,
      allowedExtensions: extensions ?? importExtensions,
    );
    if (f == null) return null;
    final size = await f.length();
    if (size != null && size > maxImportBytes) throw const ImportTooBig();
    final bytes = await f.readAsBytes();
    if (bytes.length > maxImportBytes) throw const ImportTooBig();
    return ImportFile(f.name, bytes);
  }
}
