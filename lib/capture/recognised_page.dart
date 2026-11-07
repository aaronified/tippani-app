import 'dart:ui' show Offset, Rect;

import 'text_recogniser.dart' show tidyRecognisedText;

/// One word Tesseract found, and where on the picture it is (in the picture's own pixels).
class RecognisedWord {
  const RecognisedWord(this.index, this.box, this.text);

  /// Its place in reading order on the whole page.
  final int index;
  final Rect box;
  final String text;
}

/// A printed line of words.
class RecognisedLine {
  const RecognisedLine(this.box, this.words);
  final Rect box;
  final List<RecognisedWord> words;
}

/// What Tesseract found on a page: its size, and its lines of words with their places.
class RecognisedPage {
  const RecognisedPage(this.width, this.height, this.lines);

  final double width;
  final double height;
  final List<RecognisedLine> lines;

  List<RecognisedWord> get words => [for (final l in lines) ...l.words];
  bool get isEmpty => words.isEmpty;
}

final _tag = RegExp(r'<(?:span|div)\b[^>]*>');
final _bbox = RegExp(r'bbox\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)');

String _attr(String tag, String name) =>
    RegExp(
      name + r'''=(['"])(.*?)\1''',
      dotAll: true,
    ).firstMatch(tag)?.group(2) ??
    '';

Rect? _box(String title) {
  final m = _bbox.firstMatch(title);
  if (m == null) return null;
  return Rect.fromLTRB(
    double.parse(m[1]!),
    double.parse(m[2]!),
    double.parse(m[3]!),
    double.parse(m[4]!),
  );
}

String _decode(String s) => s
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m[1]!)),
    )
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Reads Tesseract's hOCR (HTML with each word's and line's box) into a [RecognisedPage]. Lenient: a line or word
/// with no usable box is skipped, text the markup wraps (bold, italic) is kept as text, and anything that is not
/// hOCR gives an empty page. Never throws.
RecognisedPage parseHocr(String html) {
  var pageW = 0.0, pageH = 0.0;
  final lines = <(Rect?, List<(Rect, String)>)>[];
  for (final m in _tag.allMatches(html)) {
    final tag = m[0]!;
    final cls = _attr(tag, 'class');
    final box = _box(_attr(tag, 'title'));
    if (cls.contains('ocr_page')) {
      if (box != null) {
        pageW = box.right;
        pageH = box.bottom;
      }
    } else if (cls.contains('ocr_line') ||
        cls.contains('ocr_header') ||
        cls.contains('ocr_caption') ||
        cls.contains('ocr_textfloat')) {
      lines.add((box, []));
    } else if (cls.contains('ocrx_word') && box != null) {
      final end = html.indexOf('</span>', m.end);
      final inner = html.substring(m.end, end < 0 ? html.length : end);
      final text = _decode(inner.replaceAll(RegExp(r'<[^>]*>'), '')).trim();
      if (text.isEmpty) continue;
      if (lines.isEmpty) lines.add((null, []));
      lines.last.$2.add((box, text));
    }
  }
  var i = 0;
  final out = <RecognisedLine>[];
  for (final (lineBox, ws) in lines) {
    if (ws.isEmpty) continue;
    final words = [for (final (b, t) in ws) RecognisedWord(i++, b, t)];
    var box = lineBox;
    if (box == null) {
      box = words.first.box;
      for (final w in words) {
        box = box!.expandToInclude(w.box);
      }
    }
    out.add(RecognisedLine(box!, words));
  }
  if (out.isEmpty) return const RecognisedPage(0, 0, []);
  if (pageW <= 0 || pageH <= 0) {
    for (final l in out) {
      if (l.box.right > pageW) pageW = l.box.right;
      if (l.box.bottom > pageH) pageH = l.box.bottom;
    }
  }
  return RecognisedPage(pageW, pageH, out);
}

/// Which words of a [RecognisedPage] the reader has chosen, and the text they make.
class PageSelection {
  PageSelection(this.page);

  final RecognisedPage page;
  final Set<int> _on = {};

  bool contains(RecognisedWord w) => _on.contains(w.index);
  bool get isEmpty => _on.isEmpty;
  int get count => _on.length;

  /// The word at [p] (in the picture's pixels), allowing a few pixels of slack round it; null if none.
  RecognisedWord? wordAt(Offset p, {double slack = 4}) {
    RecognisedWord? best;
    var bestArea = double.infinity;
    for (final w in page.words) {
      if (w.box.inflate(slack).contains(p)) {
        final a = w.box.width * w.box.height;
        if (a < bestArea) {
          best = w;
          bestArea = a;
        }
      }
    }
    return best;
  }

  /// Chooses the word at [p] if it is not chosen, and drops it if it is. False if there is no word there.
  bool toggleAt(Offset p) {
    final w = wordAt(p);
    if (w == null) return false;
    if (!_on.remove(w.index)) _on.add(w.index);
    return true;
  }

  /// Chooses every word that [r] covers well: a sloppy drag that only grazes the next line does not pick it up.
  void addInRect(Rect r) {
    for (final w in page.words) {
      final i = w.box.intersect(r);
      if (i.width <= 0 || i.height <= 0) continue;
      final area = w.box.width * w.box.height;
      if (area > 0 && (i.width * i.height) / area >= 0.35) _on.add(w.index);
    }
  }

  void selectAll() => _on.addAll([for (final w in page.words) w.index]);
  void clear() => _on.clear();

  /// The chosen words in reading order: a line's words with spaces, lines joined into a paragraph, and a blank
  /// line where the page has a gap between two chosen lines wider than most of a line. A word cut at a line's end
  /// is mended.
  String text() {
    final chosen = <(RecognisedLine, String)>[];
    for (final l in page.lines) {
      final ws = [
        for (final w in l.words)
          if (_on.contains(w.index)) w.text,
      ];
      if (ws.isNotEmpty) chosen.add((l, ws.join(' ')));
    }
    if (chosen.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < chosen.length; i++) {
      if (i > 0) {
        final prev = chosen[i - 1].$1.box, cur = chosen[i].$1.box;
        final gap = cur.top - prev.bottom;
        final tall = (prev.height + cur.height) / 2;
        buf.write(gap > tall * 0.9 ? '\n\n' : '\n');
      }
      buf.write(chosen[i].$2);
    }
    return tidyRecognisedText(buf.toString());
  }
}
