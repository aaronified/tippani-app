import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../sync/fingerprint.dart';
import 'models.dart';

/// Where a work's cover picture comes from. An interface so a test can stand in for the server and the disk.
abstract class CoverSource {
  /// The picture file for the server's cover [name], fetched and kept on the phone the first time, or null when
  /// there is none to show (no cover, no server, or the server did not answer).
  Future<File?> fileFor(String name);

  /// Sends [bytes] to the server as [work]'s cover and returns the new cover name, or null if that did not work
  /// (not on the server yet, or the server refused it).
  Future<String?> upload(Work work, Uint8List bytes, String fileName);
}

/// The server's own cover names: sixteen hex digits and a picture extension. Anything else is never fetched, so
/// a name from the server can not point anywhere but the cover folder.
final coverName = RegExp(r'^[0-9a-f]{16}\.(jpg|png|webp|gif|svg)$');

/// Covers fetched from the paired server and kept in the app's own storage. The server names a cover file
/// once and never reuses the name, so a cover fetched is good for good and a changed cover is a new name.
class CoverCache implements CoverSource {
  CoverCache(this._controller, {this._folder, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppController _controller;
  Directory? _folder;
  final DateTime Function() _clock;
  final _failedAt = <String, DateTime>{};
  final _inFlight = <String, Future<File?>>{};

  /// How long a cover that could not be fetched is left alone before it is tried again.
  static const retryAfter = Duration(minutes: 2);

  Future<Directory> _dir() async {
    var d = _folder;
    if (d == null) {
      final base = await getApplicationSupportDirectory();
      d = Directory('${base.path}/covers');
      _folder = d;
    }
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Keeps [bytes], a picture chosen on the phone, under a name of the server's own shape and returns that
  /// name, so a screen draws it at once while the upload waits for the server. The server names the picture
  /// again when it takes it, and the screens follow that name.
  Future<String> keepLocal(Uint8List bytes, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    final kind = const ['jpg', 'png', 'webp', 'gif'].contains(ext)
        ? ext
        : 'jpg';
    final random = Random.secure();
    final stem = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final name = '$stem.$kind';
    final file = File('${(await _dir()).path}/$name');
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return name;
  }

  /// Whether the picture named [name] is already on the phone.
  Future<bool> kept(String name) async =>
      coverName.hasMatch(name) &&
      await File('${(await _dir()).path}/$name').exists();

  @override
  Future<File?> fileFor(String name) {
    if (!coverName.hasMatch(name)) return Future.value(null);
    // The callback must not return the future it removes: whenComplete waits for a returned future, and this one
    // would be waiting for itself.
    return _inFlight[name] ??= _fetch(name).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<File?> _fetch(String name) async {
    final file = File('${(await _dir()).path}/$name');
    if (await file.exists()) return file;
    final failed = _failedAt[name];
    if (failed != null && _clock().difference(failed) < retryAfter) return null;
    try {
      final bytes = await _controller.withClient(
        (c) => c.getBytes('/covers/$name'),
      );
      if (bytes == null || bytes.isEmpty) return null;
      // written whole or not at all, so a half-written picture is never shown
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      _failedAt.remove(name);
      return file;
    } on ApiException {
      _failedAt[name] = _clock();
      return null;
    } on FileSystemException {
      _failedAt[name] = _clock();
      return null;
    }
  }

  @override
  Future<String?> upload(Work work, Uint8List bytes, String fileName) async {
    final id = work.serverId;
    if (id == null) return null;
    final route = workRoute(realmOfKind(work.kind));
    try {
      return await _controller.withClient<String?>((c) async {
        await c.postFile('$route/$id/cover', 'file', bytes, fileName);
        final row = await c.getJson('$route/$id');
        final name = row is Map
            ? (row[work.kind == WorkKind.book || work.kind == WorkKind.other
                  ? 'cover_path'
                  : 'poster_path'])
            : null;
        return name is String ? name : null;
      });
    } on ApiException {
      return null;
    }
  }
}

/// Gives the screens below it the [CoverSource], so a cover picture can be shown without every screen taking one.
class CoverScope extends InheritedWidget {
  const CoverScope({super.key, required this.source, required super.child});

  final CoverSource? source;

  static CoverSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverScope>()?.source;

  @override
  bool updateShouldNotify(CoverScope old) => old.source != source;
}

/// A work's cover as a picture of [width] by [height], or [fallback] while there is none (and while it loads).
class WorkCover extends StatefulWidget {
  const WorkCover({
    super.key,
    required this.work,
    this.width = 56,
    this.height = 80,
    required this.fallback,
  });

  final Work work;
  final double width, height;
  final Widget fallback;

  @override
  State<WorkCover> createState() => _WorkCoverState();
}

class _WorkCoverState extends State<WorkCover> {
  Future<File?>? _file;
  String? _for;
  CoverSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _look();
  }

  @override
  void didUpdateWidget(WorkCover old) {
    super.didUpdateWidget(old);
    _look();
  }

  void _look() {
    final source = CoverScope.of(context);
    if (source == _source && widget.work.cover == _for) return;
    _source = source;
    _for = widget.work.cover;
    _file = source == null || widget.work.cover.isEmpty
        ? null
        : source.fileFor(widget.work.cover);
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return widget.fallback;
    return FutureBuilder<File?>(
      future: f,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return widget.fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }
}
