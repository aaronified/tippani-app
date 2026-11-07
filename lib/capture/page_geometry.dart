import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

/// A picture reduced to brightness, 0 (black) to 255 (white), one byte per pixel.
class Luma {
  Luma(this.width, this.height, this.data)
    : assert(data.length == width * height);

  final int width;
  final int height;
  final Uint8List data;

  int at(int x, int y) => data[y * width + x];
}

/// The pixels that are ink: darker than a threshold between the page's average and black. Taken at most
/// [limit] of, evenly, so a large picture costs no more than a small one.
List<(double, double)> inkPoints(Luma l, {int limit = 30000}) {
  var sum = 0, sumSq = 0;
  for (final v in l.data) {
    sum += v;
    sumSq += v * v;
  }
  final n = l.data.length;
  if (n == 0) return const [];
  final mean = sum / n;
  final sd = math.sqrt(math.max(0, sumSq / n - mean * mean));
  // A flat picture has no ink in it.
  if (sd < 8) return const [];
  final threshold = mean - 0.6 * sd;
  final all = <(double, double)>[];
  for (var y = 0; y < l.height; y++) {
    for (var x = 0; x < l.width; x++) {
      if (l.at(x, y) < threshold) all.add((x.toDouble(), y.toDouble()));
    }
  }
  if (all.length <= limit) return all;
  final step = all.length / limit;
  return [for (var i = 0.0; i < all.length; i += step) all[i.floor()]];
}

/// How far to turn the picture, in degrees clockwise (negative: anticlockwise), so that its lines of text run
/// level. Between -[max] and [max]; 0 when there is too little ink to tell.
///
/// Lines of text make the ink pile up in a few rows when the picture is level and smear across many when it is
/// tilted. For each angle the ink is projected onto the rows it would fall in once turned, and the angle that
/// piles it up the most (the sum of the squares of the row counts) wins. A coarse pass at a degree, then a fine
/// pass at a tenth around the best.
double estimateSkewDegrees(Luma l, {double max = 15}) {
  final pts = inkPoints(l);
  if (pts.length < 80) return 0;
  final cx = l.width / 2, cy = l.height / 2;
  final span = (math.sqrt(l.width * l.width + l.height * l.height)).ceil() + 2;

  double score(double degrees) {
    final r = degrees * math.pi / 180;
    final s = math.sin(r), c = math.cos(r);
    final bins = Int32List(span * 2 + 1);
    for (final (x, y) in pts) {
      final yy = (x - cx) * s + (y - cy) * c;
      bins[(yy + span).round()]++;
    }
    var total = 0.0;
    for (final b in bins) {
      total += b * b;
    }
    return total;
  }

  var best = 0.0, bestScore = score(0);
  for (var a = -max; a <= max; a += 1) {
    final sc = score(a);
    if (sc > bestScore) {
      bestScore = sc;
      best = a;
    }
  }
  final centre = best;
  for (var a = centre - 1; a <= centre + 1; a += 0.1) {
    final sc = score(a);
    if (sc > bestScore) {
      bestScore = sc;
      best = a;
    }
  }
  // Tenths are the most this can claim; below a twentieth of a degree is level.
  final rounded = (best * 10).round() / 10;
  return rounded.abs() < 0.05 ? 0 : rounded;
}

/// Where the text is, as a rectangle in fractions of the picture (0 to 1 across and down), once the picture is
/// turned by [degrees] about its centre: the area the ink covers, ignoring the odd stray speck at the edge, and
/// a small margin all round. The whole picture when there is no ink to find.
Rect textBounds(Luma l, double degrees, {double margin = 0.02}) {
  final pts = inkPoints(l);
  const whole = Rect.fromLTRB(0, 0, 1, 1);
  if (pts.length < 80) return whole;
  final cx = l.width / 2, cy = l.height / 2;
  final r = degrees * math.pi / 180;
  final s = math.sin(r), c = math.cos(r);
  final xs = <double>[], ys = <double>[];
  for (final (x, y) in pts) {
    xs.add(cx + (x - cx) * c - (y - cy) * s);
    ys.add(cy + (x - cx) * s + (y - cy) * c);
  }
  xs.sort();
  ys.sort();
  double pct(List<double> v, double p) => v[((v.length - 1) * p).round()];
  final left = pct(xs, 0.01) / l.width - margin;
  final right = pct(xs, 0.99) / l.width + margin;
  final top = pct(ys, 0.01) / l.height - margin;
  final bottom = pct(ys, 0.99) / l.height + margin;
  final box = Rect.fromLTRB(
    left.clamp(0, 1).toDouble(),
    top.clamp(0, 1).toDouble(),
    right.clamp(0, 1).toDouble(),
    bottom.clamp(0, 1).toDouble(),
  );
  // Too small to be a page of text: leave the picture whole.
  return box.width < 0.1 || box.height < 0.05 ? whole : box;
}

/// [r] kept inside the picture and at least [min] of it across and down.
Rect clampCrop(Rect r, {double min = 0.1}) {
  var l = r.left.clamp(0, 1 - min).toDouble();
  var t = r.top.clamp(0, 1 - min).toDouble();
  var rr = r.right.clamp(l + min, 1).toDouble();
  var b = r.bottom.clamp(t + min, 1).toDouble();
  return Rect.fromLTRB(l, t, rr, b);
}
