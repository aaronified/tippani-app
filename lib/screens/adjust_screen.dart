import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../capture/page_adjuster.dart';
import '../capture/page_geometry.dart';

/// Straightens and crops a photographed page before it is read. The app first works out how the page is tilted and
/// where the text is (both can be changed): turn the picture with the slider or the nudge buttons, and drag the
/// corners of the frame to keep only the text. Pops the path of the adjusted picture; Use as is pops the original.
class AdjustScreen extends StatefulWidget {
  const AdjustScreen({super.key, required this.imagePath, this.adjuster});

  final String imagePath;
  final PageAdjuster? adjuster;

  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

const _whole = Rect.fromLTRB(0, 0, 1, 1);

class _AdjustScreenState extends State<AdjustScreen> {
  late final PageAdjuster _adjuster =
      widget.adjuster ?? const DevicePageAdjuster();
  double _aspect = 3 / 4;
  bool _ready = false;
  bool _busy = true;
  double _angle = 0;
  Rect _crop = _whole;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _auto();
  }

  /// Works out the tilt and the text's area again, replacing any changes by hand.
  Future<void> _auto() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final g = await _adjuster.analyse(widget.imagePath);
      if (!mounted) return;
      setState(() {
        _aspect = g.width / math.max(1, g.height);
        _angle = g.angle.clamp(-15, 15).toDouble();
        _crop = clampCrop(g.crop);
        _ready = true;
      });
    } on Object {
      if (mounted) {
        setState(
          () => _problem = 'The picture could not be looked at. You can still use it as it is.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
    _angle = 0;
    _crop = _whole;
  });

  void _turn(double d) =>
      setState(() => _angle = (_angle + d).clamp(-15, 15).toDouble());

  Future<void> _use() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final path = await _adjuster.render(widget.imagePath, _angle, _crop);
      if (mounted) Navigator.of(context).pop(path);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = 'The picture could not be adjusted. Try again, or use it as it is.';
        });
      }
    }
  }

  Widget _handle(
    Key key,
    Offset at,
    void Function(Offset delta, Size stage) move,
    Size stage,
  ) => Positioned(
    left: at.dx - 22,
    top: at.dy - 22,
    // A drag recogniser that wins the moment a finger lands: inside a scrolling page an ordinary pan loses to the
    // page's own scroll on any drag that goes mostly up or down, and the corner would never move.
    child: RawGestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      gestures: {
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              ImmediateMultiDragGestureRecognizer
            >(
              () => ImmediateMultiDragGestureRecognizer(),
              (r) => r.onStart = (_) => _Drag((d) => move(d, stage)),
            ),
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Straighten and crop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_ready)
            AspectRatio(
              aspectRatio: _aspect,
              child: LayoutBuilder(
                builder: (context, box) {
                  final stage = Size(box.maxWidth, box.maxHeight);
                  Offset px(double fx, double fy) =>
                      Offset(fx * stage.width, fy * stage.height);
                  void drag(
                    Offset d,
                    Size s, {
                    bool l = false,
                    bool t = false,
                    bool r = false,
                    bool b = false,
                  }) {
                    final dx = d.dx / s.width, dy = d.dy / s.height;
                    setState(
                      () => _crop = clampCrop(
                        Rect.fromLTRB(
                          _crop.left + (l ? dx : 0),
                          _crop.top + (t ? dy : 0),
                          _crop.right + (r ? dx : 0),
                          _crop.bottom + (b ? dy : 0),
                        ),
                      ),
                    );
                  }

                  return ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white,
                            child: Transform.rotate(
                              angle: _angle * math.pi / 180,
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _FramePainter(
                                _crop,
                                theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        _handle(
                          const Key('crop-tl'),
                          px(_crop.left, _crop.top),
                          (d, s) => drag(d, s, l: true, t: true),
                          stage,
                        ),
                        _handle(
                          const Key('crop-tr'),
                          px(_crop.right, _crop.top),
                          (d, s) => drag(d, s, r: true, t: true),
                          stage,
                        ),
                        _handle(
                          const Key('crop-bl'),
                          px(_crop.left, _crop.bottom),
                          (d, s) => drag(d, s, l: true, b: true),
                          stage,
                        ),
                        _handle(
                          const Key('crop-br'),
                          px(_crop.right, _crop.bottom),
                          (d, s) => drag(d, s, r: true, b: true),
                          stage,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_problem != null) ...[
            const SizedBox(height: 12),
            Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_ready) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Turn anticlockwise',
                  icon: const Icon(Icons.rotate_left),
                  onPressed: _busy ? null : () => _turn(-0.5),
                ),
                Expanded(
                  child: Slider(
                    value: _angle,
                    min: -15,
                    max: 15,
                    divisions: 60,
                    label: '${_angle.toStringAsFixed(1)}°',
                    onChanged: _busy ? null : (v) => setState(() => _angle = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Turn clockwise',
                  icon: const Icon(Icons.rotate_right),
                  onPressed: _busy ? null : () => _turn(0.5),
                ),
              ],
            ),
            Center(child: Text('Turned ${_angle.toStringAsFixed(1)}°')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _auto,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Auto'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: _busy || !_ready ? null : _use,
                child: const Text('Use this'),
              ),
              OutlinedButton(
                onPressed: _busy && _problem == null
                    ? null
                    : () => Navigator.of(context).pop(widget.imagePath),
                child: const Text('Use as is'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Darkens what the crop leaves out and outlines what it keeps.
class _FramePainter extends CustomPainter {
  _FramePainter(this.crop, this.colour);
  final Rect crop;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Paint()..color = const Color(0x88000000);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(r),
      ),
      shade,
    );
    canvas.drawRect(
      r,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.crop != crop || old.colour != colour;
}

/// What a finger dragging a corner does: each movement is handed on as it is.
class _Drag implements Drag {
  _Drag(this.moved);
  final void Function(Offset delta) moved;

  @override
  void update(DragUpdateDetails details) => moved(details.delta);

  @override
  void end(DragEndDetails details) {}

  @override
  void cancel() {}
}
