import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Whether [bytes] are a vector picture (the server stores a signature as SVG as often as a bitmap).
bool looksLikeSvg(Uint8List bytes) {
  final n = bytes.length < 512 ? bytes.length : 512;
  final head = String.fromCharCodes(bytes.sublist(0, n)).toLowerCase();
  return head.contains('<svg');
}

/// Draws the vector picture [svg] as a bitmap [height] pixels tall (its own width ratio), PNG-encoded, or null if it
/// cannot be read. The share picture decodes bitmaps only, so a vector signature goes through here first.
Future<Uint8List?> svgToPng(Uint8List svg, {int height = 160}) async {
  try {
    final info = await vg.loadPicture(SvgBytesLoader(svg), null);
    try {
      final size = info.size;
      if (size.width <= 0 || size.height <= 0) return null;
      final scale = height / size.height;
      final width = (size.width * scale).ceil().clamp(1, 4096);
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(scale);
      canvas.drawPicture(info.picture);
      final image = await rec.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } finally {
      info.picture.dispose();
    }
  } on Object {
    return null;
  }
}
