import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import 'page_geometry.dart';

/// What the app works out about a photographed page: its shape, how far to turn it, and where the text is.
class PageGuess {
  const PageGuess({
    required this.width,
    required this.height,
    required this.angle,
    required this.crop,
  });

  /// The picture's own size, as it is shown (so its shape).
  final int width, height;

  /// Degrees to turn it clockwise to make the lines of text level.
  final double angle;

  /// The part to keep, as fractions of the picture after turning it.
  final ui.Rect crop;
}

/// Straightens and crops a page picture. An interface so a test can stand in for the picture work.
abstract class PageAdjuster {
  /// Looks at the picture at [path] and says how it should be turned and cropped.
  Future<PageGuess> analyse(String path);

  /// Makes a new picture from [path]: turned by [angle] degrees clockwise about its centre, then cut to [crop]
  /// (fractions of the turned picture), with white where the turning left a gap. Returns the new file's path.
  Future<String> render(String path, double angle, ui.Rect crop);
}

/// The phone's own picture decoding, drawing and encoding (`dart:ui`); nothing leaves the phone.
class DevicePageAdjuster implements PageAdjuster {
  const DevicePageAdjuster({this.outDir});

  /// Where adjusted pictures are made; null uses the phone's temporary folder.
  final Directory? outDir;

  /// The long side the picture is worked at when looking for the lines: enough to see text, small enough to be quick.
  static const _lookAt = 480;

  /// The longest side of the picture made for reading (a camera's 12 megapixels is more than Tesseract needs).
  static const _readAt = 3000;

  @override
  Future<PageGuess> analyse(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: _lookAt);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('the picture could not be read');
      final rgba = data.buffer.asUint8List();
      final luma = Uint8List(img.width * img.height);
      for (var i = 0; i < luma.length; i++) {
        final o = i * 4;
        luma[i] =
            ((rgba[o] * 299 + rgba[o + 1] * 587 + rgba[o + 2] * 114) / 1000)
                .round();
      }
      final l = Luma(img.width, img.height, luma);
      final angle = estimateSkewDegrees(l);
      return PageGuess(
        width: img.width,
        height: img.height,
        angle: angle,
        crop: textBounds(l, angle),
      );
    } finally {
      img.dispose();
      codec.dispose();
    }
  }

  @override
  Future<String> render(String path, double angle, ui.Rect crop) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final big = math.max(descriptor.width, descriptor.height);
    final codec = await descriptor.instantiateCodec(
      targetWidth: big > _readAt
          ? (descriptor.width * _readAt / big).round()
          : null,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    try {
      final w = img.width.toDouble(), h = img.height.toDouble();
      final cw = math.max(1, (crop.width * w).round());
      final ch = math.max(1, (crop.height * h).round());
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.translate(-crop.left * w, -crop.top * h);
      canvas.translate(w / 2, h / 2);
      canvas.rotate(angle * math.pi / 180);
      canvas.translate(-w / 2, -h / 2);
      canvas.drawImage(
        img,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final out = await rec.endRecording().toImage(cw, ch);
      try {
        final png = await out.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('the picture could not be made');
        final dir = outDir ?? await getTemporaryDirectory();
        final file = File(
          '${dir.path}/tippani_page_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
        return file.path;
      } finally {
        out.dispose();
      }
    } finally {
      img.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
