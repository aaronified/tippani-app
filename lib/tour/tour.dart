import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/l10n.dart';
import 'tour_store.dart';

/// One stop of the tour: a sentence about one real control.
class TourStep {
  const TourStep({
    required this.id,
    required this.title,
    required this.body,
    this.target,
    this.before,
  });

  final String id;
  final String title;
  final String body;

  /// The control this step points at. Null for a step about the app as a whole, which is drawn in the middle. A step
  /// whose target is not on this phone's screen is skipped, never shown pointing at nothing.
  final GlobalKey? target;

  /// What puts the control in view (open the tab it is on). Runs when the step is about to be shown.
  final VoidCallback? before;
}

/// A tour that is running; [done] completes when it ends, however it ends.
class TourRun {
  TourRun._(this._entry, this.done, this._finish);

  final OverlayEntry _entry;
  final Future<void> done;
  final void Function() _finish;

  /// Ends the tour without remembering anything (the screen under it went away).
  void cancel() {
    if (_entry.mounted) _entry.remove();
    _finish();
  }
}

/// Starts a tour over [context]'s overlay. How it ended is written to [store].
///
/// A hand-built overlay and no package (ADR-0027): a dimmed screen with a hole over the control, and a card at the
/// edge of the screen that is nearer the reader's thumb, so the buttons are where the thumb already is.
TourRun startTour(
  BuildContext context, {
  required List<TourStep> steps,
  TourStore? store,
}) {
  final done = Completer<void>();
  late final OverlayEntry entry;
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  entry = OverlayEntry(
    builder: (_) => _TourOverlay(
      steps: steps,
      onEnd: (outcome) {
        if (entry.mounted) entry.remove();
        if (outcome != null) store?.remember(outcome);
        finish();
      },
    ),
  );
  Overlay.of(context).insert(entry);
  return TourRun._(entry, done.future, finish);
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onEnd});

  final List<TourStep> steps;
  final void Function(TourOutcome?) onEnd;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _at = -1;
  Rect? _hole;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _show(0, 1);
  }

  /// The control is built at all (a hidden section or a missing feature leaves it unbuilt).
  bool _built(TourStep s) {
    if (s.target == null) return true;
    final o = s.target!.currentContext?.findRenderObject();
    return o is RenderBox && o.attached && o.hasSize && !o.size.isEmpty;
  }

  /// The control can be seen right now: built, and not on a tab that is not the open one.
  Rect? _measure(TourStep s) {
    final c = s.target?.currentContext;
    if (c == null || !_built(s)) return null;
    var hidden = false;
    c.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) hidden = true;
      return !hidden;
    });
    if (hidden) return null;
    final box = c.findRenderObject()! as RenderBox;
    final overlay = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  List<int> get _available => [
    for (var i = 0; i < widget.steps.length; i++)
      if (_built(widget.steps[i])) i,
  ];

  void _show(int i, int dir) {
    if (i < 0 || i >= widget.steps.length) {
      if (i >= widget.steps.length) widget.onEnd(TourOutcome.finished);
      return;
    }
    final s = widget.steps[i];
    if (!_built(s)) {
      _show(i + dir, dir);
      return;
    }
    s.before?.call();
    // the frame that draws what `before` changed comes first, then the control can be measured
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rect = _measure(s);
      if (s.target != null && rect == null) {
        _show(i + dir, dir);
        return;
      }
      setState(() {
        _at = i;
        _hole = rect;
        _shown = true;
      });
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final step = widget.steps[_at];
    final avail = _available;
    final n = avail.indexOf(_at) + 1;
    final total = avail.length;
    final last = avail.isEmpty || avail.last == _at;
    final first = avail.isEmpty || avail.first == _at;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return BlockSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final hole = _hole?.inflate(6);
          final lower = hole != null && hole.center.dy > size.height / 2;
          final pad = MediaQuery.paddingOf(context);
          final end =
              hole ??
              Rect.fromCenter(
                center: size.center(Offset.zero),
                width: 0,
                height: 0,
              );
          return Stack(
            children: [
              // the scrim takes every press, so a stray tap does not reach the screen under the tour
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: ExcludeSemantics(
                    child: TweenAnimationBuilder<Rect?>(
                      tween: RectTween(end: end),
                      duration: animate
                          ? const Duration(milliseconds: 260)
                          : Duration.zero,
                      curve: Curves.easeOutCubic,
                      builder: (context, r, _) => CustomPaint(
                        painter: _ScrimPainter(
                          hole: hole == null ? null : r,
                          scrim: scheme.scrim.withValues(alpha: 0.78),
                          ring: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    lower || hole == null ? pad.top + 12 : hole.bottom + 12,
                    16,
                    hole == null
                        ? pad.bottom + 12
                        : lower
                        ? size.height - hole.top + 12
                        : pad.bottom + 12,
                  ),
                  child: Align(
                    alignment: hole == null
                        ? Alignment.center
                        : lower
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _Card(
                        step: step,
                        n: n,
                        total: total,
                        first: first,
                        last: last,
                        onSkip: () => widget.onEnd(TourOutcome.dismissed),
                        onBack: () => _show(_at - 1, -1),
                        onNext: () => last
                            ? widget.onEnd(TourOutcome.finished)
                            : _show(_at + 1, 1),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.scrim, required this.ring});

  final Rect? hole;
  final Color scrim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    RRect? r;
    if (hole != null) {
      r = RRect.fromRectAndRadius(hole!, const Radius.circular(18));
      path.addRRect(r);
    }
    canvas.drawPath(
      path..fillType = PathFillType.evenOdd,
      Paint()..color = scrim,
    );
    if (r != null) {
      canvas.drawRRect(
        r,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.n,
    required this.total,
    required this.first,
    required this.last,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  final TourStep step;
  final int n;
  final int total;
  final bool first;
  final bool last;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = context.tr('app.tour.count', {'n': n, 'total': total});
    return Material(
      key: const ValueKey('tour-card'),
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                // what a screen reader says when the step changes: the sentence, then where we are
                child: Semantics(
                  key: const ValueKey('tour-text'),
                  container: true,
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(step.body, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 10),
                      Text(
                        count,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: onSkip,
                  child: Text(context.tr('app.tour.skip')),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!first)
                      TextButton(
                        onPressed: onBack,
                        child: Text(context.tr('app.tour.back')),
                      ),
                    FilledButton(
                      onPressed: onNext,
                      child: Text(
                        last
                            ? context.tr('app.tour.done')
                            : context.tr('app.tour.next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
