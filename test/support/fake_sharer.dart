import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tippani/share/sharer.dart';

/// Stands in for Android's share sheet: remembers what the share screen handed it. Put it above the screen with
/// [FakeSharer.around].
class FakeSharer extends Sharer {
  final texts = <String>[];
  final subjects = <String>[];
  final images = <({Uint8List png, String name, String text})>[];
  final files = <({Uint8List bytes, String name})>[];

  /// When set, sending a picture throws, as a phone with no share sheet would.
  bool failImage = false;

  @override
  Future<void> text(String text, String subject) async {
    texts.add(text);
    subjects.add(subject);
  }

  @override
  Future<void> image(Uint8List png, String fileName, String text) async {
    if (failImage) throw Exception('no share sheet');
    images.add((png: png, name: fileName, text: text));
  }

  @override
  Future<void> file(Uint8List bytes, String fileName) async {
    files.add((bytes: bytes, name: fileName));
  }

  Widget around(Widget child) => ShareScope(sharer: this, child: child);
}
