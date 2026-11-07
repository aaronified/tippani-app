import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/l10n/english.g.dart';

bool _watching = false;

/// Every test that draws a screen is also checking that no token reaches the reader: a text on screen that is a
/// token's own name ("app.share.copy_picture") means a screen showed a token it never translated.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_watching) {
    _watching = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      void walk(RenderObject o) {
        if (o is RenderParagraph) {
          final t = o.text.toPlainText().trim();
          if (t.contains('.') &&
              !t.contains(' ') &&
              englishTokens.containsKey(t)) {
            throw StateError('A token reached the screen untranslated: $t');
          }
        }
        o.visitChildren(walk);
      }

      for (final v in RendererBinding.instance.renderViews) {
        walk(v);
      }
    });
  }
  await testMain();
}
