import 'dart:typed_data';

import 'package:tippani/api/server_call.dart';
import 'package:tippani/sources/source_picker.dart';
import 'package:tippani/sources/sources_service.dart';

/// Source files kept in memory, so the screen can be tested without a server.
class FakeSources implements SourcesService {
  @override
  bool available = true;

  final calls = <String>[];

  List<SourceMount> mountList = const [SourceMount('books', 'Books')];
  ScanState scanNow = const ScanState();
  List<FoundFile> foundList = [];
  List<AttachedSource> attachedList = [];
  String? refuse;
  Map<String, List<FolderEntry>> folders = {};

  @override
  Future<List<SourceMount>> mounts() async => mountList;

  @override
  Future<bool> scan(String mountId) async {
    calls.add('scan $mountId');
    scanNow = const ScanState(state: 'running', scanned: 3, found: 1);
    return false;
  }

  @override
  Future<ScanState> scanState(String mountId) async {
    // a scan finishes the second time it is asked about
    if (scanNow.live) {
      scanNow = const ScanState(state: 'done', scanned: 10, found: 2);
    }
    return scanNow;
  }

  @override
  Future<({ScanState scan, List<FoundFile> found})> found(
    String mountId,
  ) async => (scan: scanNow, found: List.of(foundList));

  @override
  Future<AttachResult> attachFound(String bucket, List<String> tokens) async {
    calls.add('attachFound $bucket ${tokens.join(',')}');
    if (refuse != null) throw ServerException(refuse!);
    foundList = [
      for (final f in foundList)
        if (!tokens.contains(f.token)) f,
    ];
    return AttachResult(attached: tokens.length);
  }

  @override
  Future<void> ignoreFound(List<String> tokens) async {
    calls.add('ignoreFound ${tokens.join(',')}');
    foundList = [
      for (final f in foundList)
        if (!tokens.contains(f.token)) f,
    ];
  }

  @override
  Future<List<AttachedSource>> attached() async => List.of(attachedList);

  @override
  Future<PrunePreview> prunePreview(int id) async => const PrunePreview(
    bytes: 2 * 1024 * 1024,
    keptBytes: 40 * 1024,
    withContext: 3,
    withoutContext: 1,
  );

  @override
  Future<void> prune(int id) async => calls.add('prune $id');

  @override
  Future<void> rescan(int id) async => calls.add('rescan $id');

  @override
  Future<void> remove(int id) async {
    calls.add('remove $id');
    attachedList = [
      for (final a in attachedList)
        if (a.id != id) a,
    ];
  }

  @override
  Future<FolderListing> browse(String mountId, String path) async {
    final entries = folders[path] ?? const <FolderEntry>[];
    return FolderListing(
      path: path,
      parent: path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : '',
      root: path.isEmpty,
      entries: entries,
    );
  }

  @override
  Future<void> attachMounted({
    required String mountId,
    required String rel,
    required String subject,
    required int workId,
    String episode = '',
  }) async {
    calls.add('attachMounted $mountId $rel $subject $workId $episode');
    if (refuse != null) throw ServerException(refuse!);
  }

  @override
  Future<void> upload({
    required Uint8List bytes,
    required String fileName,
    required String subject,
    required int workId,
    String episode = '',
  }) async {
    calls.add('upload $fileName $subject $workId $episode');
    if (refuse != null) throw ServerException(refuse!);
  }
}

class FakeSourcePicker implements SourcePicker {
  SourceFile? file;
  bool tooBig = false;

  @override
  Future<SourceFile?> pick() async {
    if (tooBig) throw const SourceTooBig();
    return file;
  }
}
