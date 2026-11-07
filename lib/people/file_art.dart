import 'dart:io';

import 'package:flutter/material.dart';

import '../library/cover_cache.dart';

/// A picture the server names (a cover, a poster, a portrait), fetched once and kept like a cover, drawn at
/// [width] by [height] (round when [circle]); [fallback] stands in while there is none.
class FileArt extends StatefulWidget {
  const FileArt({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    required this.fallback,
    this.circle = false,
  });

  final String name;
  final double width, height;
  final bool circle;
  final Widget fallback;

  @override
  State<FileArt> createState() => _FileArtState();
}

class _FileArtState extends State<FileArt> {
  Future<File?>? _file;
  String _for = '';
  CoverSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _look();
  }

  @override
  void didUpdateWidget(FileArt old) {
    super.didUpdateWidget(old);
    _look();
  }

  void _look() {
    final source = CoverScope.of(context);
    if (identical(source, _source) && widget.name == _for) return;
    _source = source;
    _for = widget.name;
    _file = source == null || widget.name.isEmpty
        ? null
        : source.fileFor(widget.name);
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
        final image = Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (widget.width * 3).round(),
          errorBuilder: (_, _, _) => widget.fallback,
        );
        return widget.circle
            ? ClipOval(child: image)
            : ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
      },
    );
  }
}
