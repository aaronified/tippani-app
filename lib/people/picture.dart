import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'people_directory.dart';

/// A picture the server names (a portrait, a character's still, a signature, a cover), read from the phone's own
/// copy of it, fetched the first time. Draws [fallback] while there is none, and when it cannot be had. A drawn
/// (SVG) picture is drawn as vectors, tinted by [tint] when given (a signature takes the text's colour).
class StoredPicture extends StatefulWidget {
  const StoredPicture({
    super.key,
    required this.name,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.circle = false,
    this.radius = 0,
    this.tint,
    this.fallback = const SizedBox.shrink(),
  });

  /// The file name on the server ('' for none).
  final String name;
  final double? width, height;
  final BoxFit fit;
  final bool circle;
  final double radius;
  final Color? tint;
  final Widget fallback;

  @override
  State<StoredPicture> createState() => _StoredPictureState();
}

class _StoredPictureState extends State<StoredPicture> {
  Future<File?>? _file;
  String _for = '';
  PeopleDirectory? _dir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dir = PeopleDirectoryScope.of(context);
    _look();
  }

  @override
  void didUpdateWidget(StoredPicture old) {
    super.didUpdateWidget(old);
    _look();
  }

  void _look() {
    if (widget.name == _for && _file != null) return;
    _for = widget.name;
    _file = widget.name.isEmpty ? null : _dir?.file(widget.name);
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
        Widget img;
        if (widget.name.toLowerCase().endsWith('.svg')) {
          img = SvgPicture.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit == BoxFit.cover ? BoxFit.contain : widget.fit,
            colorFilter: widget.tint == null
                ? null
                : ColorFilter.mode(widget.tint!, BlendMode.srcIn),
          );
        } else {
          img = Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          );
        }
        if (widget.circle) return ClipOval(child: img);
        if (widget.radius > 0) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: img,
          );
        }
        return img;
      },
    );
  }
}
