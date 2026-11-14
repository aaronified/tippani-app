import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/preferences.dart';
import 'materials.dart';

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
    final look = widget.look ?? MaterialLook.fromPrefs(PrefsScope.of(context));
    final name = look.tileFor(widget.slot);
    final textile = textiles[name]!;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The reader asked their phone for more contrast or less transparency: every decorative layer drops to zero, as
    // the web does.
    final media = MediaQuery.maybeOf(context);
    final plain = media?.highContrast ?? false;
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
        radius: widget.borderRadius,
      ),
      child: widget.child,
    );
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
  });

  final Color color;
  final Color accent;
  final String name;
  final Textile textile;
  final Phys phys;
  final bool dark;
  final ui.Image? tile;
  final BorderRadius radius;

  // The window is up and to the left, and it is the only one in the app; the wall it faces is the opposite corner.
  static const _light = Offset(0.22, 0.06);
  static const _lightBack = Offset(0.78, 0.96);

  bool get _glassy => name == 'glass' || name == 'glass-soft';
  bool get _metallic => name == 'metal' || name == 'brushed';

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    // Everything is composited in one isolated layer, so a blend mode sees this surface and not the page behind it.
    canvas.saveLayer(rect, Paint());
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
    _lights(canvas, rect);
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
      old.radius != radius;
}

/// What the account's surfaces are made of, reading the preferences so the widget rebuilds when they change.
MaterialLook materialLookOf(BuildContext context) =>
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
    final flat = textiles[look.tileFor('shell')]!.isFlat;
    return AppBar(
      title: title,
      actions: actions,
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
    if (textiles[look.tileFor('card')]!.isFlat) {
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
