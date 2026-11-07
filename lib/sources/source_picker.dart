import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the reader chose as a source.
class SourceFile {
  const SourceFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The server refuses a source over this size, so it is not sent.
const maxSourceBytes = 25 * 1024 * 1024;

class SourceTooBig implements Exception {
  const SourceTooBig();
  @override
  String toString() => 'app.source_picker.that_file_is_over_25_mb';
}

/// Choosing a source file with the system's own picker. Tests hand the harness a fake.
abstract interface class SourcePicker {
  /// The file chosen, or null if they backed out. Throws [SourceTooBig] for a file the server would refuse.
  Future<SourceFile?> pick();
}

class SystemSourcePicker implements SourcePicker {
  const SystemSourcePicker();

  @override
  Future<SourceFile?> pick() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'app.source_picker.choose_an_ebook_or_a_subtitle',
      type: FileType.any,
    );
    if (f == null) return null;
    final size = await f.length();
    if (size != null && size > maxSourceBytes) throw const SourceTooBig();
    final bytes = await f.readAsBytes();
    if (bytes.length > maxSourceBytes) throw const SourceTooBig();
    return SourceFile(f.name, bytes);
  }
}
