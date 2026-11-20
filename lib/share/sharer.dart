import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// The one way anything leaves the app through Android's share sheet: text, a picture, or a file. The share
/// screen is the only caller. A class so a test can stand in for the sheet by putting its own in a [ShareScope],
/// instead of every screen carrying a function for each kind of thing it might send.
abstract class Sharer {
  const Sharer();

  Future<void> text(String text, String subject);

  Future<void> image(Uint8List png, String fileName, String text);

  Future<void> file(Uint8List bytes, String fileName);
}

/// The real thing: Android's share sheet.
class SheetSharer extends Sharer {
  const SheetSharer();

  @override
  Future<void> text(String text, String subject) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  @override
  Future<void> image(Uint8List png, String fileName, String text) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  }

  @override
  Future<void> file(Uint8List bytes, String fileName) async {
    final epub = fileName.toLowerCase().endsWith('.epub');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: epub ? 'application/epub+zip' : 'text/markdown',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }
}

/// Where the share screen finds its [Sharer]. With none above it, the real share sheet.
class ShareScope extends InheritedWidget {
  const ShareScope({super.key, required this.sharer, required super.child});

  final Sharer sharer;

  static Sharer of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShareScope>()?.sharer ??
      const SheetSharer();

  @override
  bool updateShouldNotify(ShareScope old) => old.sharer != sharer;
}
