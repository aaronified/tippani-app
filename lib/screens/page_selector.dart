import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../capture/recognised_page.dart';

/// A scanned page with every word Tesseract found drawn over it, so the reader picks the passage they want right on
/// the picture: tap a word to take it or leave it out, drag a box across several to take them, Select all or Clear.
/// Everything starts chosen. [onChanged] gets the text of the chosen words, now and after each change.
class PageSelector extends StatefulWidget {
  const PageSelector({
    super.key,
    required this.imagePath,
    required this.page,
    required this.onChanged,
  });

  final String imagePath;
  final RecognisedPage page;
  final ValueChanged<String> onChanged;

  @override
  State<PageSelector> createState() => _PageSelectorState();
}

class _PageSelectorState extends State<PageSelector> {
  late final PageSelection _sel = PageSelection(widget.page)..selectAll();
  Rect? _box;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_sel.text());
    });
  }

  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged(_sel.text());
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: page.width / page.height,
          child: LayoutBuilder(
            builder: (context, c) {
              final scale = c.maxWidth / page.width;
              Offset toPage(Offset o) => Offset(o.dx / scale, o.dy / scale);
              // A tap takes a word or leaves it out. A finger that moves draws a box, through a drag recogniser that
              // starts after a few pixels of movement and is checked before the page's own scroll, so a drag that goes
              // mostly up or down draws a box and does not scroll the page (an ordinary pan would lose to the scroll).
              return RawGestureDetector(
                key: const Key('page-stage'),
                behavior: HitTestBehavior.opaque,
                gestures: {
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        () => TapGestureRecognizer(),
                        (t) => t.onTapUp = (d) {
                          final p = toPage(d.localPosition);
                          _changed(() => _sel.toggleAt(p));
                        },
                      ),
                  ImmediateMultiDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        ImmediateMultiDragGestureRecognizer
                      >(
                        () => ImmediateMultiDragGestureRecognizer(),
                        (r) => r.onStart = (global) {
                          final box = context.findRenderObject() as RenderBox;
                          final start = toPage(box.globalToLocal(global));
                          return _StageDrag(
                            start: start,
                            scale: scale,
                            onBox: (b) => setState(() => _box = b),
                            onBoxDone: (b) {
                              setState(() => _box = null);
                              _changed(() => _sel.addInRect(b));
                            },
                          );
                        },
                      ),
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.white),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WordsPainter(
                          page,
                          _sel,
                          _box,
                          scale,
                          theme.colorScheme.primary,
                          _sel.count,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap a word to take it or leave it out. Drag a box across words to take them.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _changed(_sel.selectAll),
              child: const Text('Select all'),
            ),
            OutlinedButton(
              onPressed: () => _changed(_sel.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }
}

class _WordsPainter extends CustomPainter {
  _WordsPainter(
    this.page,
    this.sel,
    this.box,
    this.scale,
    this.colour,
    this.count,
  );

  final RecognisedPage page;
  final PageSelection sel;
  final Rect? box;
  final double scale;
  final Color colour;

  /// Repaint when the choice changes (the selection is mutated in place, so its size says it changed).
  final int count;

  Rect _px(Rect r) => Rect.fromLTRB(
    r.left * scale,
    r.top * scale,
    r.right * scale,
    r.bottom * scale,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = colour.withValues(alpha: 0.35);
    final edge = Paint()
      ..color = colour.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final w in page.words) {
      final r = _px(w.box);
      if (sel.contains(w)) canvas.drawRect(r, fill);
      canvas.drawRect(r, edge);
    }
    final b = box;
    if (b != null) {
      canvas.drawRect(
        _px(b),
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WordsPainter old) => true;
}

/// A finger moving on the picture: a box from where it landed to where it is.
class _StageDrag implements Drag {
  _StageDrag({
    required this.start,
    required this.scale,
    required this.onBox,
    required this.onBoxDone,
  });

  final Offset start;
  final double scale;
  final void Function(Rect box) onBox;
  final void Function(Rect box) onBoxDone;

  var _moved = Offset.zero;
  Rect? _box;

  @override
  void update(DragUpdateDetails details) {
    _moved += details.delta;
    _box = Rect.fromPoints(start, start + _moved / scale);
    onBox(_box!);
  }

  @override
  void end(DragEndDetails details) {
    final b = _box;
    if (b != null) onBoxDone(b);
  }

  @override
  void cancel() {
    if (_box != null) onBoxDone(Rect.zero);
  }
}
