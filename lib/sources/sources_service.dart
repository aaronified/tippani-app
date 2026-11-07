import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
String _s(Object? v) => v == null ? '' : '$v';

/// A folder of the server's disk a reader may take files from (its label, never its path).
class SourceMount {
  const SourceMount(this.id, this.label);
  final String id, label;
}

/// How a scan of a folder stands.
class ScanState {
  const ScanState({
    this.state = 'none',
    this.error = '',
    this.scanned = 0,
    this.found = 0,
    this.unclaimed = 0,
    this.skipped = 0,
  });

  /// none, queued, running, partial, done, failed or interrupted.
  final String state;
  final String error;
  final int scanned, found, unclaimed, skipped;

  bool get live => state == 'queued' || state == 'running';

  static ScanState fromJson(Object? j) {
    if (j is! Map) return const ScanState();
    return ScanState(
      state: _s(j['state']).isEmpty ? 'none' : _s(j['state']),
      error: _s(j['error']),
      scanned: _int(j['scanned']),
      found: _int(j['found']),
      unclaimed: _int(j['unclaimed']),
      skipped: _int(j['skipped']),
    );
  }
}

/// A file the scan found that looks like it belongs to a work: this file for that work.
class FoundFile {
  const FoundFile({
    required this.token,
    required this.rel,
    required this.format,
    required this.subject,
    required this.workId,
    required this.title,
    this.episode = '',
    this.how = '',
    this.bucket = 'review',
  });

  final String token, rel, format, subject, title, episode, how, bucket;
  final int workId;

  /// Matched by an identifier both sides hold, not just by a name.
  bool get exact => bucket == 'exact';

  static FoundFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final token = _s(j['token']);
    if (token.isEmpty) return null;
    return FoundFile(
      token: token,
      rel: _s(j['rel']),
      format: _s(j['format']),
      subject: _s(j['subject']),
      workId: _int(j['work_id']),
      title: _s(j['title']),
      episode: _s(j['episode']),
      how: _s(j['how']),
      bucket: _s(j['bucket']),
    );
  }
}

/// The result of attaching or ignoring several found files.
class AttachResult {
  const AttachResult({this.attached = 0, this.skipped = 0, this.failed = 0});
  final int attached, skipped, failed;
}

/// A source file attached to a work.
class AttachedSource {
  const AttachedSource({
    required this.id,
    required this.subject,
    required this.workId,
    required this.name,
    this.episode = '',
    this.format = '',
    this.bytes = 0,
    this.origin = '',
    this.state = '',
    this.createdAt = '',
    this.withContext = 0,
  });

  final int id, workId, bytes, withContext;
  final String subject, episode, name, format, origin, state, createdAt;

  /// Taken from the server's disk through a folder, not copied (so there is nothing of ours to prune).
  bool get mounted => origin == 'mount';

  /// Its bytes are held here and could be pruned (what is left is the context cut from it).
  bool get prunable => !mounted && state == 'file';

  static AttachedSource? fromJson(Object? j) {
    if (j is! Map) return null;
    return AttachedSource(
      id: _int(j['id']),
      subject: _s(j['subject']),
      workId: _int(j['subject_id']),
      episode: _s(j['episode']),
      name: _s(j['name']),
      format: _s(j['format']),
      bytes: _int(j['bytes']),
      origin: _s(j['origin']),
      state: _s(j['state']),
      createdAt: _s(j['created_at']),
      withContext: _int(j['with_context']),
    );
  }
}

/// What pruning a source file would free, and what it keeps.
class PrunePreview {
  const PrunePreview({
    this.bytes = 0,
    this.keptBytes = 0,
    this.withContext = 0,
    this.withoutContext = 0,
  });
  final int bytes, keptBytes, withContext, withoutContext;
}

/// One entry in a folder being browsed.
class FolderEntry {
  const FolderEntry({
    required this.name,
    required this.rel,
    required this.dir,
    this.size = 0,
  });
  final String name, rel;
  final bool dir;
  final int size;
}

class FolderListing {
  const FolderListing({
    required this.path,
    required this.parent,
    required this.root,
    required this.entries,
    this.truncated = false,
  });
  final String path, parent;
  final bool root, truncated;
  final List<FolderEntry> entries;
}

/// Source files: the files a work's quotes were found in (an ebook, a subtitle track), which give a quote its
/// surroundings. Attached from the server's folders, found by a scan, chosen by hand or uploaded from the phone.
/// An interface so a test can stand in for the server. Every call throws a [ServerException] (with words for the
/// reader) when it cannot be done.
abstract class SourcesService {
  bool get available;

  Future<List<SourceMount>> mounts();

  /// Starts a scan of a folder; true when one was already running.
  Future<bool> scan(String mountId);
  Future<ScanState> scanState(String mountId);
  Future<({ScanState scan, List<FoundFile> found})> found(String mountId);
  Future<AttachResult> attachFound(String bucket, List<String> tokens);
  Future<void> ignoreFound(List<String> tokens);

  Future<List<AttachedSource>> attached();
  Future<PrunePreview> prunePreview(int id);
  Future<void> prune(int id);
  Future<void> rescan(int id);
  Future<void> remove(int id);

  Future<FolderListing> browse(String mountId, String path);

  /// Attaches the file at [rel] of a folder to a work. [subject] is 'book' or 'screen'; [episode] is for a show's
  /// episode (s01e04).
  Future<void> attachMounted({
    required String mountId,
    required String rel,
    required String subject,
    required int workId,
    String episode = '',
  });

  /// Sends a file from the phone as a work's source.
  Future<void> upload({
    required Uint8List bytes,
    required String fileName,
    required String subject,
    required int workId,
    String episode = '',
  });
}

/// The paired server's source files.
class PairedSourcesService implements SourcesService {
  PairedSourcesService(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  @override
  Future<List<SourceMount>> mounts() => serverCall(_controller, (c) async {
    final r = await c.getJson('/sources/mounts');
    final list = r is Map ? r['mounts'] : null;
    return [
      if (list is List)
        for (final m in list)
          if (m is Map && _s(m['id']).isNotEmpty)
            SourceMount(_s(m['id']), _s(m['label'])),
    ];
  });

  @override
  Future<bool> scan(String mountId) => serverCall(_controller, (c) async {
    final r = await c.postJson('/sources/scan', {'mount_id': mountId});
    return r is Map && r['running'] == true;
  });

  @override
  Future<ScanState> scanState(String mountId) => serverCall(_controller, (
    c,
  ) async {
    final r = await c.getJson(
      '/sources/found?mount_id=${Uri.encodeQueryComponent(mountId)}&status=1',
    );
    return ScanState.fromJson(r is Map ? r['scan'] : null);
  });

  @override
  Future<({ScanState scan, List<FoundFile> found})> found(String mountId) =>
      serverCall(_controller, (c) async {
        final r = await c.getJson(
          '/sources/found?mount_id=${Uri.encodeQueryComponent(mountId)}',
        );
        final list = r is Map ? r['candidates'] : null;
        return (
          scan: ScanState.fromJson(r is Map ? r['scan'] : null),
          found: [
            if (list is List)
              for (final x in list)
                if (FoundFile.fromJson(x) != null) FoundFile.fromJson(x)!,
          ],
        );
      });

  @override
  Future<AttachResult> attachFound(String bucket, List<String> tokens) =>
      serverCall(_controller, (c) async {
        final r = await c.postJson('/sources/attach-found', {
          'bucket': bucket,
          'tokens': tokens,
        });
        return r is Map
            ? AttachResult(
                attached: _int(r['attached']),
                skipped: _int(r['skipped']),
                failed: _int(r['failed']),
              )
            : const AttachResult();
      });

  @override
  Future<void> ignoreFound(List<String> tokens) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/sources/ignore-found', {'tokens': tokens});
      });

  @override
  Future<List<AttachedSource>> attached() => serverCall(_controller, (c) async {
    final r = await c.getJson('/sources/all');
    final list = r is Map ? r['sources'] : null;
    return [
      if (list is List)
        for (final x in list)
          if (AttachedSource.fromJson(x) != null) AttachedSource.fromJson(x)!,
    ];
  });

  @override
  Future<PrunePreview> prunePreview(int id) =>
      serverCall(_controller, (c) async {
        final r = await c.getJson('/sources/$id/prune');
        return r is Map
            ? PrunePreview(
                bytes: _int(r['bytes']),
                keptBytes: _int(r['kept_bytes']),
                withContext: _int(r['with_context']),
                withoutContext: _int(r['without_context']),
              )
            : const PrunePreview();
      });

  @override
  Future<void> prune(int id) => serverCall<void>(_controller, (c) async {
    await c.postJson('/sources/$id/prune', const {});
  });

  @override
  Future<void> rescan(int id) => serverCall<void>(_controller, (c) async {
    await c.postJson('/sources/$id/rescan', const {});
  });

  @override
  Future<void> remove(int id) => serverCall<void>(_controller, (c) async {
    await c.delete('/sources/$id');
  });

  @override
  Future<FolderListing> browse(String mountId, String path) =>
      serverCall(_controller, (c) async {
        final q = Uri(queryParameters: {'mount': mountId, 'path': path}).query;
        final r = await c.getJson('/sources/browse?$q');
        final m = r is Map ? r : const {};
        final list = m['entries'];
        return FolderListing(
          path: _s(m['path']),
          parent: _s(m['parent']),
          root: m['root'] == true,
          truncated: m['truncated'] == true,
          entries: [
            if (list is List)
              for (final e in list)
                if (e is Map)
                  FolderEntry(
                    name: _s(e['name']),
                    rel: _s(e['rel']),
                    dir: e['dir'] == true,
                    size: _int(e['size']),
                  ),
          ],
        );
      });

  @override
  Future<void> attachMounted({
    required String mountId,
    required String rel,
    required String subject,
    required int workId,
    String episode = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.postJson('/sources/attach-mounted', {
      'mount': mountId,
      'rel': rel,
      'subject': subject,
      'id': workId,
      'episode': episode,
    });
  });

  @override
  Future<void> upload({
    required Uint8List bytes,
    required String fileName,
    required String subject,
    required int workId,
    String episode = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.sendFile(
      'PUT',
      '/sources',
      'file',
      bytes,
      fileName,
      fields: {
        'subject': subject,
        'subject_id': '$workId',
        if (episode.isNotEmpty) 'episode': episode,
      },
    );
  });
}

/// Gives the screens below it the [SourcesService].
class SourcesScope extends InheritedWidget {
  const SourcesScope({super.key, required this.service, required super.child});

  final SourcesService? service;

  static SourcesService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SourcesScope>()?.service;

  @override
  bool updateShouldNotify(SourcesScope old) => old.service != service;
}
