import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../account/preferences.dart';
import 'materials.dart';
import '../screens/server_link.dart' show ServerLinkIcon;

/// The decoded tiles, each once for the life of the app. A tile is 60 KB or so and the same few are laid on every screen.
class TileCache {
  TileCache._();

  static final _images = <String, ui.Image>{};
  static final _loading = <String, Future<ui.Image?>>{};

  /// The tile now, if it has been decoded.
  static ui.Image? peek(String file) => _images[file];

  /// Decodes [file] from the bundle once. Null when the bundle has no such file (a test without the assets), in which
  /// case the surface is drawn without grain rather than failing.
  static Future<ui.Image?> load(String file, [AssetBundle? bundle]) {
    if (file.isEmpty) return Future.value(null);
    final have = _images[file];
    if (have != null) return Future.value(have);
    return _loading.putIfAbsent(file, () async {
      try {
        final data = await (bundle ?? rootBundle).load('assets/textures/$file');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        return _images[file] = frame.image;
      } catch (_) {
        return null;
      }
    });
  }

  /// Forgets everything, for tests that swap the bundle.
  static void clear() {
    _images.clear();
    _loading.clear();
  }
}

/// The surfaces already composed, each once. A surface is a veil, two grain passes (one of them an `overlay` blend), up
/// to three light gradients and, for a pane, a layer of its own; drawing all that on every paint was the app's stutter
/// (ADR-0028). It is composed once into a picture the size of the surface, and every paint after that is one image
/// draw. Held within a byte budget, least recently used out first.
class SurfaceImages {
  SurfaceImages._();

  /// What the images may take between them. A phone-wide card at 2x is a megabyte or so; a screen holds a handful.
  static int budgetBytes = 48 * 1024 * 1024;

  static final _images = <Object, ui.Image>{};
  static int _bytes = 0;

  /// How many surfaces were composed since the app started (or [clear]), for the cost tests.
  @visibleForTesting
  static int composed = 0;

  static int _cost(ui.Image i) => i.width * i.height * 4;

  /// The largest image worth composing, in device pixels on a side and in all. Past either the GPU may refuse the
  /// texture (and `toImageSync` usually does not say so: the surface would draw blank), and one tall card would crowd
  /// the cache. Such a surface is drawn layer by layer, as before.
  static const maxSide = 4096;
  static const maxPixels = 4 * 1024 * 1024;

  /// Turns a recorded picture into an image. A seam for tests, which make it throw or hand back a useless image to see the
  /// layers drawn instead.
  @visibleForTesting
  static ui.Image Function(ui.Picture picture, int width, int height) composer =
      defaultComposer;

  static ui.Image defaultComposer(ui.Picture picture, int width, int height) =>
      picture.toImageSync(width, height);

  /// Whether a surface this size is composed at all.
  static bool fits(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= maxSide &&
      height <= maxSide &&
      width * height <= maxPixels &&
      width * height * 4 * 2 <= budgetBytes;

  /// The composed surface for [key], composing it with [compose] on a miss unless [mayCompose] is false (the surface is
  /// changing size and an image made now would be used once). Null when there is no image to draw (too big, not allowed,
  /// or this engine cannot make one from the picture), in which case the caller draws the layers directly.
  static ui.Image? obtain(
    Object key,
    int width,
    int height,
    void Function(Canvas canvas) compose, {
    bool mayCompose = true,
  }) {
    final have = _images.remove(key);
    if (have != null) {
      _images[key] = have; // most recently used goes last
      return have;
    }
    if (!mayCompose || !fits(width, height)) return null;
    try {
      final recorder = ui.PictureRecorder();
      compose(Canvas(recorder));
      final picture = recorder.endRecording();
      final ui.Image image;
      try {
        image = composer(picture, width, height);
      } finally {
        picture.dispose();
      }
      if (image.width != width || image.height != height) {
        image.dispose();
        return null;
      }
      composed++;
      _images[key] = image;
      _bytes += _cost(image);
      while (_bytes > budgetBytes && _images.length > 1) {
        final oldest = _images.keys.first;
        final gone = _images.remove(oldest)!;
        _bytes -= _cost(gone);
        gone.dispose();
      }
      return image;
    } catch (_) {
      return null;
    }
  }

  /// Forgets everything, for tests.
  static void clear() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    _bytes = 0;
    composed = 0;
  }

  @visibleForTesting
  static int get held => _images.length;
}

/// One slot's surface: a colour with the material's grain laid over it, then what the material does with the light.
///
/// Drawn the way the web draws it: `(1 - s) * colour + s * overlay(fine, coarse)`, a veil of the colour at `1 - s` over a
/// fine pass composited normally and a coarse one composited `overlay`, and above those the dials as gradients (a
/// highlight, a glow from within, the room's wall). One tile file serves light and dark: it carries only deviation from
/// mid grey, so the mode supplies the colour and the file the grain.
class MaterialSurface extends StatefulWidget {
  const MaterialSurface({
    super.key,
    required this.slot,
    required this.color,
    this.child,
    this.look,
    this.borderRadius = BorderRadius.zero,
  });

  /// 'ground', 'shell', 'card' or 'cover'.
  final String slot;

  /// The slot's colour from the colour scheme: what the surface would be with no material.
  final Color color;
  final Widget? child;
  final BorderRadius borderRadius;

  /// Overrides what the account says; a test and the mixer's specimens use it.
  final MaterialLook? look;

  @override
  State<MaterialSurface> createState() => _MaterialSurfaceState();
}

class _MaterialSurfaceState extends State<MaterialSurface> {
  ui.Image? _tile;
  String _loaded = '';
  final _watch = SizeWatch();

  @override
  void dispose() {
    _watch.dispose();
    super.dispose();
  }

  void _ensure(Textile t) {
    if (_loaded == t.file) return;
    _loaded = t.file;
    _tile = TileCache.peek(t.file);
    if (_tile != null || t.file.isEmpty) return;
    final wanted = t.file;
    TileCache.load(wanted).then((img) {
      if (!mounted || _loaded != wanted || img == null) return;
      setState(() => _tile = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look ?? materialLookOf(context);
    final name = look.tileFor(widget.slot);
    final textile = textiles[name]!;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The reader asked their phone for more contrast or less transparency: every decorative layer drops to zero, as
    // the web does. Asked of the one setting and not of the whole MediaQuery, which changes every frame the keyboard
    // moves and would rebuild every surface on the screen with it.
    final plain =
        (MediaQuery.maybeHighContrastOf(context) ?? false) || look.reduced;
    if (textile.isFlat || plain) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      );
    }
    _ensure(textile);
    return CustomPaint(
      painter: MaterialPainter(
        color: widget.color,
        accent: theme.colorScheme.primary,
        name: name,
        textile: textile,
        phys: look.physFor(name),
        dark: dark,
        tile: _tile,
        watch: _watch,
        radius: widget.borderRadius,
        pixelRatio: (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1).clamp(
          1.0,
          3.0,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Remembers the size a surface was last painted at, so that a surface whose size is changing (an expanding tile, a
/// window being resized) is not composed on every frame of it: each of those images would be used once and would push
/// the list's own cards out of the cache. A changed size is drawn layer by layer for that frame and a repaint is asked
/// for after it; the surface is composed once it has painted at the same size twice running.
class SizeWatch extends ChangeNotifier {
  Size? last;
  bool _pending = false;
  bool _disposed = false;

  /// Notes [size] and says whether it is the one before.
  bool settle(Size size) {
    final same = last == null || last == size;
    last = size;
    if (!same && !_pending) {
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        if (!_disposed) notifyListeners();
      });
    }
    return same;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Paints one material over one colour. A value object: it repaints only when something it draws with changed.
class MaterialPainter extends CustomPainter {
  MaterialPainter({
    required this.color,
    required this.accent,
    required this.name,
    required this.textile,
    required this.phys,
    required this.dark,
    required this.tile,
    this.radius = BorderRadius.zero,
    this.pixelRatio = 1,
    this.watch,
  }) : super(repaint: watch);

  /// Told the size of every paint; null composes at once (a test, a specimen).
  final SizeWatch? watch;

  final Color color;
  final Color accent;
  final String name;
  final Textile textile;
  final Phys phys;
  final bool dark;
  final ui.Image? tile;
  final BorderRadius radius;

  /// Device pixels per logical one, as far as the composed image is sharp (clamped to 1..3 to bound its size).
  final double pixelRatio;

  // The window is up and to the left, and it is the only one in the app; the wall it faces is the opposite corner.
  static const _light = Offset(0.22, 0.06);
  static const _lightBack = Offset(0.78, 0.96);

  bool get _glassy => name == 'glass' || name == 'glass-soft';
  bool get _metallic => name == 'metal' || name == 'brushed';

  /// How many times a material was painted, for the cost tests.
  @visibleForTesting
  static int debugPaints = 0;

  // One paint for every surface: an image draw allocates nothing, so nothing is left to make per frame.
  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    debugPaints++;
    if (size.isEmpty) return;
    final w = (size.width * pixelRatio).ceil();
    final h = (size.height * pixelRatio).ceil();
    final image = SurfaceImages.obtain(
      (
        name,
        color.toARGB32(),
        accent.toARGB32(),
        phys,
        dark,
        tile == null ? 0 : identityHashCode(tile),
        w,
        h,
        pixelRatio,
        radius,
      ),
      w,
      h,
      (c) {
        c.scale(w / size.width, h / size.height);
        _layers(c, size);
      },
      mayCompose: watch?.settle(size) ?? true,
    );
    if (image == null) {
      _layers(canvas, size);
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Offset.zero & size,
      _imagePaint,
    );
  }

  /// The surface drawn layer by layer: what the image is composed from.
  void _layers(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    // A pane is translucent, so it is composited in its own layer and a blend mode sees the pane and not the page
    // behind it. Every other material is opaque from its first pixel, and a layer per card is a cost a long list
    // would pay for nothing.
    if (_glassy) {
      canvas.saveLayer(rect, Paint());
    } else {
      canvas.save();
    }
    canvas.clipRRect(shape);
    final s = textile.strength;

    // A pane stays translucent; everything else is opaque colour.
    canvas.drawRect(
      rect,
      Paint()
        ..color = _glassy ? color.withValues(alpha: dark ? 0.34 : 0.24) : color,
    );

    final img = tile;
    if (img != null) {
      _grain(canvas, rect, img, textile.fine, BlendMode.srcOver);
      _grain(canvas, rect, img, textile.coarse, BlendMode.overlay);
    }
    // The veil: the colour again at 1 - s, which is what keeps the grain a texture and not a photograph.
    canvas.drawRect(
      rect,
      Paint()..color = color.withValues(alpha: (1 - s).clamp(0, 1)),
    );

    // What the material does with the light goes over the grain and under the sheen, as the web stacks it. A pane
    // carries no light layers of its own there: its sweep is its highlight.
    if (!_glassy) _lights(canvas, rect);

    if (_glassy) {
      final hi1 = dark ? 0.16 : 0.55;
      final hi2 = dark ? 0.04 : 0.12;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = _cssLinear(
            rect,
            124,
            [
              Colors.white.withValues(alpha: hi1),
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: hi2),
            ],
            const [0, 0.34, 0.64, 1],
          ),
      );
    }
    if (_metallic) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = _cssLinear(
            rect,
            126,
            [
              accent.withValues(alpha: 0.16),
              Colors.transparent,
              Colors.transparent,
              accent.withValues(alpha: 0.10),
            ],
            const [0, 0.4, 0.6, 1],
          ),
      );
    }
    canvas.restore();
  }

  void _grain(
    Canvas canvas,
    Rect rect,
    ui.Image img,
    double px,
    BlendMode mode,
  ) {
    final scale = px / img.width;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = mode
        ..shader = ui.ImageShader(
          img,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.diagonal3Values(scale, scale, 1).storage,
          filterQuality: FilterQuality.medium,
        ),
    );
  }

  /// The four dials as gradients, over the veil and the grain: the window's highlight, the glow from within, and the
  /// wall's wash. A dial at zero draws nothing, so a flat-ish material costs nothing here.
  void _lights(Canvas canvas, Rect rect) {
    final hard = phys.hard / 100;
    final sss = phys.sss / 100;
    final diff = phys.diff / 100;
    final refl = phys.refl / 100;

    // Bottom to top: the wall's wash, the glow from within, then the highlight, which is the order the web lists them
    // in reverse (its first layer is the top one).
    if (refl > 0.06) {
      final a = (dark ? 0.016 : 0.024) * refl;
      _glow(
        canvas,
        rect,
        0.9,
        _lightBack,
        const Color.fromARGB(255, 236, 240, 248),
        a,
        BlendMode.screen,
      );
    }
    if (sss > 0.04) {
      final a = (dark ? 0.020 : 0.030) * sss;
      _glow(
        canvas,
        rect,
        1.2,
        _light,
        const Color.fromARGB(255, 255, 242, 214),
        a,
        BlendMode.softLight,
      );
    }
    final spread = (52 + 40 * (1 - hard)).roundToDouble() / 100;
    final peak = (dark ? 0.012 : 0.018) + (dark ? 0.038 : 0.052) * hard;
    final warm = diff > 0.02
        ? Color.fromARGB(
            255,
            (255 - 10 * diff).round(),
            (250 - 18 * diff).round(),
            (242 - 6 * diff).round(),
          )
        : Colors.white;
    if (peak > 0.004) {
      _glow(canvas, rect, spread, _light, warm, peak, BlendMode.screen);
    }
  }

  /// CSS `radial-gradient(S% S% at X Y, ramp)`: an ellipse whose radii are a share of the box, five stops on a squared
  /// curve (fewer stops show as bands on a dark ground).
  void _glow(
    Canvas canvas,
    Rect rect,
    double share,
    Offset at,
    Color rgb,
    double peak,
    BlendMode mode,
  ) {
    final rx = rect.width * share;
    final ry = rect.height * share;
    if (rx <= 0 || ry <= 0) return;
    const stops = [0.0, 0.25, 0.5, 0.75, 1.0];
    final colors = [
      for (final t in stops)
        rgb.withValues(alpha: (peak * math.pow(1 - t, 2.2)).clamp(0, 1)),
    ];
    final cx = rect.left + rect.width * at.dx;
    final cy = rect.top + rect.height * at.dy;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(rx, ry);
    canvas.drawRect(
      Rect.fromLTWH(-cx / rx, -cy / ry, rect.width / rx, rect.height / ry),
      Paint()
        ..blendMode = mode
        ..shader = ui.Gradient.radial(Offset.zero, 1, colors, stops),
    );
    canvas.restore();
  }

  /// CSS `linear-gradient(<deg>, ...)`: the angle is clockwise from "up", and the line is long enough that the corners
  /// reach 0% and 100% exactly.
  ui.Shader _cssLinear(
    Rect rect,
    double degrees,
    List<Color> colors,
    List<double> stops,
  ) {
    final a = degrees * math.pi / 180;
    final dx = math.sin(a);
    final dy = -math.cos(a);
    final half = (rect.width * dx.abs() + rect.height * dy.abs()) / 2;
    final c = rect.center;
    return ui.Gradient.linear(
      Offset(c.dx - dx * half, c.dy - dy * half),
      Offset(c.dx + dx * half, c.dy + dy * half),
      colors,
      stops,
    );
  }

  @override
  bool shouldRepaint(MaterialPainter old) =>
      old.color != color ||
      old.accent != accent ||
      old.name != name ||
      old.phys != phys ||
      old.dark != dark ||
      old.tile != tile ||
      old.pixelRatio != pixelRatio ||
      old.radius != radius;
}

/// The account's [MaterialLook], built once where the preferences arrive and handed down by value: a surface that reads it
/// is told only when the look is not equal to the last, so a preference that has nothing to do with surfaces (a daily
/// review count, a type size) rebuilds none of them.
class LookScope extends InheritedWidget {
  const LookScope({super.key, required this.look, required super.child});

  final MaterialLook look;

  @override
  bool updateShouldNotify(LookScope old) => look != old.look;
}

/// What the account's surfaces are made of. Reads the [LookScope] the app puts above its screens; where there is none (a
/// test, a screen shown on its own) it reads the preferences itself, as it did before.
MaterialLook materialLookOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<LookScope>()?.look ??
    MaterialLook.fromPrefs(PrefsScope.of(context));

/// The top bar: the app's own [AppBar] drawn on the "shell" material. Takes the few arguments the app's bars use.
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.titleSpacing,
  });

  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final double? titleSpacing;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final look = materialLookOf(context);
    final scheme = Theme.of(context).colorScheme;
    final flat = !look.drawn('shell');
    return AppBar(
      title: title,
      actions: [const ServerLinkIcon(), ...?actions],
      bottom: bottom,
      leading: leading,
      titleSpacing: titleSpacing,
      // A plain bar keeps the theme's own colour; a textured one is transparent over its own surface.
      backgroundColor: flat ? null : Colors.transparent,
      flexibleSpace: flat
          ? null
          : RepaintBoundary(
              child: MaterialSurface(
                slot: 'shell',
                color: scheme.surfaceContainer,
                look: look,
                child: const SizedBox.expand(),
              ),
            ),
    );
  }
}

/// A card: the app's own [Card] drawn on the "card" material (what a quote is written on).
///
/// The texture sits under the [Card], whose material is clear, so ink from a tap on a child paints over the grain rather
/// than under it.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.color,
    this.margin,
    this.clipBehavior,
    this.shape,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final look = materialLookOf(context);
    if (!look.drawn('card')) {
      return Card(
        color: color,
        margin: margin,
        clipBehavior: clipBehavior,
        shape: shape,
        child: child,
      );
    }
    final theme = Theme.of(context);
    final border = shape ?? theme.cardTheme.shape;
    final radius = border is RoundedRectangleBorder
        ? border.borderRadius.resolve(Directionality.of(context))
        : BorderRadius.circular(20);
    final base =
        color ?? theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow;
    final surface = MaterialSurface(
      slot: 'card',
      color: base,
      look: look,
      borderRadius: radius,
      child: Card(
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: clipBehavior,
        shape: shape,
        child: child,
      ),
    );
    final m = margin ?? theme.cardTheme.margin;
    return m == null || m == EdgeInsets.zero
        ? surface
        : Padding(padding: m, child: surface);
  }
}
