import 'package:flutter/material.dart';

/// A row that scrolls sideways when it is longer than the space it has. Where more is hidden past an edge, that edge
/// fades out (an edge mask), so a long name or a run of tags reads as "there is more this way" instead of being cut
/// off hard. Nothing fades when everything fits.
class EdgeFadeRow extends StatefulWidget {
  const EdgeFadeRow({
    super.key,
    required this.children,
    this.gap = 8,
    this.fade = 24,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;

  /// Space between the children.
  final double gap;

  /// How wide the fade is.
  final double fade;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<EdgeFadeRow> createState() => _EdgeFadeRowState();
}

class _EdgeFadeRowState extends State<EdgeFadeRow> {
  final _controller = ScrollController();
  bool _before = false;
  bool _after = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _measure(ScrollMetrics m) {
    final before = m.extentBefore > 1;
    final after = m.extentAfter > 1;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fade = widget.fade;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        // metrics change while laying out; settle after the frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measure(n.metrics);
        });
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _measure(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final f = rect.width <= 0
                ? 0.0
                : (fade / rect.width).clamp(0.0, 0.5);
            return LinearGradient(
              colors: [
                _before ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                _after ? Colors.transparent : Colors.black,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(rect);
          },
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: widget.crossAxisAlignment,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) SizedBox(width: widget.gap),
                  widget.children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
