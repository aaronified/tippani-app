import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../library/models.dart';
import '../library/share_format.dart';

// THE PICTURE OF A QUOTE, drawn the way the web app draws it (web/frontend/src/quoteImage.js): one fixed width of
// 640 logical pixels exported at twice that, a height that follows the content, fixed type sizes (a long quote makes
// a taller card, it is never shrunk or cut), the web's own palettes, a paper texture, and a footer with the Tippani
// mark. The numbers below are the web's, kept in the same names where there is one.

/// The logical width of the picture. It is exported at [shareScale] times that, so 1280 pixels wide.
const double shareWidth = 640;
const double shareScale = 2;

const double _mat = 22;
const double _cardPad = 34;
const double _footerH = 34;

/// The two looks of the picture, from the web's `theme.js`.
class SharePalette {
  const SharePalette({
    required this.bg,
    required this.cardTop,
    required this.cardBottom,
    required this.ink,
    required this.soft,
    required this.faint,
    required this.inkBorder,
    required this.mark,
  });

  final Color bg, cardTop, cardBottom, ink, soft, faint, inkBorder, mark;

  static const light = SharePalette(
    bg: Color(0xFFF4EDDE),
    cardTop: Color(0xFFFFFFFC),
    cardBottom: Color(0xFFFCF8ED),
    ink: Color(0xFF221C16),
    soft: Color(0xFF6A5F50),
    faint: Color(0xFF766A59),
    inkBorder: Color(0x9929261D),
    mark: Color(0xFFB4482D),
  );

  static const dark = SharePalette(
    bg: Color(0xFF262019),
    cardTop: Color(0xFF352D23),
    cardBottom: Color(0xFF2C251E),
    ink: Color(0xFFEFE6D4),
    soft: Color(0xFFB3A48C),
    faint: Color(0xFFA1937D),
    inkBorder: Color(0x66EFE6D4),
    mark: Color(0xFFD8613D),
  );
}

/// The accent the picture takes for a note's bar and the tag pills: the web's default terracotta.
const Color shareAccent = Color(0xFFB4482D);

/// The quote colours as the web paints them (theme.js `categoryHex`).
const Map<String, Color> shareQuoteColours = {
  'yellow': Color(0xFFE5C355),
  'blue': Color(0xFF7FA6C9),
  'pink': Color(0xFFD98CA6),
  'orange': Color(0xFFDF9A5B),
  'green': Color(0xFF7CB342),
  'purple': Color(0xFF8A7BC8),
};

/// A grain laid over the card. [asset] is null for a flat card.
class ShareTile {
  const ShareTile(this.asset, this.coarse, this.fine, this.strength);
  final String? asset;
  final double coarse, fine, strength;
}

/// The material sets of the web's picture, each by the grain it puts on the card (its third tile).
enum ShareMaterial {
  manuscript('Manuscript', ShareTile('assets/share/paper.webp', 220, 71, 0.10)),
  filmAssembly(
    'Film assembly',
    ShareTile('assets/share/matte.png', 200, 65, 0.07),
  ),
  office('Office', ShareTile('assets/share/satin.png', 210, 68, 0.07)),
  school('School', ShareTile('assets/share/paper.webp', 220, 71, 0.10)),
  atelier('Atelier', ShareTile('assets/share/cotton.png', 300, 97, 0.12)),
  bindery('Bindery', ShareTile('assets/share/paper-photo.png', 300, 97, 0.07)),
  quarry('Quarry', ShareTile('assets/share/satin.png', 210, 68, 0.07)),
  atrium('Atrium', ShareTile(null, 0, 0, 0));

  const ShareMaterial(this.label, this.tile);
  final String label;
  final ShareTile tile;

  static ShareMaterial named(String? id) => values.firstWhere(
    (m) => m.name == id,
    orElse: () => ShareMaterial.manuscript,
  );
}

enum ShareStyle { bold, italic, plain }

class ShareRun {
  const ShareRun(this.text, this.style);
  final String text;
  final ShareStyle style;
}

/// What the picture says, from a quote and the parts switched on (the same ids the text formats use).
class SharePictureModel {
  SharePictureModel(Quote q, Work? w, Set<String> on) {
    final f = {for (final x in shareFieldsOf(q, w)) x.id: x.value};
    String? get(String id) => on.contains(id) ? f[id] : null;

    quote = get('quote') ?? '';
    translation = get('translation') ?? '';

    // A quote from a work: the author and the work credit the line, and the speaker is the character, who goes in
    // the small line below. A quote of no work: the speaker credits it, and the chapter is its occasion (italic).
    final attribution = <ShareRun>[];
    final meta = <String>[];
    if (w != null) {
      void a(String id, ShareStyle s) {
        final v = get(id);
        if (v != null) attribution.add(ShareRun(v, s));
      }

      a('author', ShareStyle.bold);
      a('work', ShareStyle.italic);
      a('year', ShareStyle.plain);
      for (final id in ['speaker', 'chapter', 'location', 'noted']) {
        final v = get(id);
        if (v != null) meta.add(v);
      }
    } else {
      final s = get('speaker');
      if (s != null) attribution.add(ShareRun(s, ShareStyle.bold));
      final c = get('chapter');
      if (c != null) attribution.add(ShareRun(c, ShareStyle.italic));
      for (final id in ['location', 'noted']) {
        final v = get(id);
        if (v != null) meta.add(v);
      }
    }
    this.attribution = attribution;
    this.meta = meta;
    note = get('note') ?? '';
    tags = on.contains('tags')
        ? [
            for (final t in q.tags)
              if (t.replaceAll(RegExp(r'\s+'), '').isNotEmpty)
                t.replaceAll(RegExp(r'\s+'), ''),
          ]
        : const [];
    colour = shareQuoteColours[q.color];
  }

  late final String quote, translation, note;
  late final List<ShareRun> attribution;
  late final List<String> meta;
  late final List<String> tags;
  late final Color? colour;
}

const _serifFallback = [
  'NotoSerifBengali',
  'NotoSerifDevanagari',
  'Georgia',
  'serif',
];

TextStyle _serif(
  double size,
  double line,
  Color color, {
  FontWeight weight = FontWeight.w400,
  FontStyle style = FontStyle.normal,
}) => TextStyle(
  fontFamily: 'Newsreader',
  fontFamilyFallback: _serifFallback,
  fontSize: size,
  height: line / size,
  leadingDistribution: TextLeadingDistribution.even,
  fontWeight: weight,
  fontStyle: style,
  color: color,
);

TextStyle _mono(
  double size,
  double line,
  Color color, {
  FontWeight weight = FontWeight.w500,
  double spacing = 0,
}) => TextStyle(
  fontFamily: 'IBMPlexMono',
  fontFamilyFallback: const ['monospace'],
  fontSize: size,
  height: line / size,
  leadingDistribution: TextLeadingDistribution.even,
  fontWeight: weight,
  letterSpacing: spacing,
  color: color,
);

/// The picture itself, at its full logical size ([shareWidth] wide). Put it in a `RepaintBoundary` and capture it at
/// `shareScale` to get the file; scale it down with a `FittedBox` to show it.
class SharePicture extends StatefulWidget {
  const SharePicture({
    super.key,
    required this.quote,
    required this.work,
    required this.on,
    this.dark = false,
    this.material = ShareMaterial.manuscript,
    this.tint = false,
  });

  final Quote quote;
  final Work? work;

  /// Which parts to draw, by the ids in `share_format.dart`.
  final Set<String> on;
  final bool dark;
  final ShareMaterial material;

  /// Whether the quote's own colour is drawn as a stripe beside the words.
  final bool tint;

  @override
  State<SharePicture> createState() => _SharePictureState();
}

class _SharePictureState extends State<SharePicture> {
  ui.Image? _tile;
  String? _tileFor;

  @override
  void initState() {
    super.initState();
    _loadTile();
  }

  @override
  void didUpdateWidget(SharePicture old) {
    super.didUpdateWidget(old);
    _loadTile();
  }

  Future<void> _loadTile() async {
    final asset = widget.material.tile.asset;
    if (asset == _tileFor) return;
    _tileFor = asset;
    if (asset == null) {
      setState(() => _tile = null);
      return;
    }
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted && _tileFor == asset) setState(() => _tile = frame.image);
    } on Object {
      // no grain: the card is drawn flat, as the web draws it until the tile arrives
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.dark ? SharePalette.dark : SharePalette.light;
    final m = SharePictureModel(widget.quote, widget.work, widget.on);
    final bar = widget.tint && m.colour != null;
    final inset = bar ? 8.0 : 0.0;

    final blocks = <Widget>[];
    void add(Widget w, double gapBefore) {
      if (blocks.isNotEmpty) blocks.add(SizedBox(height: gapBefore));
      blocks.add(w);
    }

    if (m.quote.isNotEmpty) {
      final words = Text(
        '“${m.quote}”',
        style: _serif(27, 38, p.ink, style: FontStyle.italic),
      );
      add(
        bar
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  words,
                  Positioned(
                    left: -10,
                    top: 0,
                    bottom: 0,
                    width: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: m.colour,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              )
            : words,
        0,
      );
    }
    if (m.translation.isNotEmpty) {
      add(Text(m.translation, style: _serif(21, 28, p.soft)), 12);
    }
    if (m.attribution.isNotEmpty) {
      TextStyle s(ShareStyle x) => switch (x) {
        ShareStyle.bold => _serif(15, 23, p.soft, weight: FontWeight.w600),
        ShareStyle.italic => _serif(15, 23, p.soft, style: FontStyle.italic),
        ShareStyle.plain => _serif(15, 23, p.soft),
      };
      add(
        Text.rich(
          TextSpan(
            style: s(ShareStyle.plain),
            children: [
              const TextSpan(text: '— '),
              for (var i = 0; i < m.attribution.length; i++) ...[
                if (i > 0) const TextSpan(text: ', '),
                TextSpan(
                  text: m.attribution[i].text,
                  style: s(m.attribution[i].style),
                ),
              ],
            ],
          ),
        ),
        14,
      );
    }
    if (m.meta.isNotEmpty) {
      add(
        Text(
          m.meta.map((e) => e.toUpperCase()).join('  ·  '),
          style: _mono(11.5, 19, p.soft, spacing: 1),
        ),
        6,
      );
    }
    if (m.note.isNotEmpty) {
      add(
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            m.note,
            style: TextStyle(
              fontFamily: 'Caveat',
              fontFamilyFallback: const [
                'NotoSerifBengali',
                'NotoSerifDevanagari',
                'cursive',
              ],
              fontSize: 22,
              height: 28 / 22,
              leadingDistribution: TextLeadingDistribution.even,
              color: p.ink,
            ),
          ),
        ),
        20,
      );
    }
    if (m.tags.isNotEmpty) {
      add(
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final t in m.tags)
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    shareAccent.withValues(alpha: 0.3),
                    p.cardTop,
                  ),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: shareAccent.withValues(alpha: 0.55),
                  ),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    t,
                    style: _mono(11, 14, p.ink, weight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        18,
      );
    }

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.cardTop, p.cardBottom],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47000000),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.inkBorder, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _GrainPainter(widget.material.tile, _tile),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _cardPad + inset,
              _cardPad,
              _cardPad,
              _cardPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...blocks,
                if (blocks.isNotEmpty) const SizedBox(height: 20),
                _Footer(palette: p),
              ],
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: shareWidth,
      child: ColoredBox(
        color: p.bg,
        child: Padding(padding: const EdgeInsets.all(_mat), child: card),
      ),
    );
  }
}

/// The hairline, the Tippani mark and "made with tippani", all on one baseline.
class _Footer extends StatelessWidget {
  const _Footer({required this.palette});

  final SharePalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      height: _footerH,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: Container(height: 1, color: p.ink.withValues(alpha: 0.12)),
          ),
          Positioned(
            left: 0,
            top: 10 + 8,
            right: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CustomPaint(
                  size: Size(213.14 * 20 / 256, (229.3 - 23.37) * 20 / 256),
                  painter: _MarkPainter(p.mark),
                ),
                const SizedBox(width: 7),
                Text('made with', style: _mono(11, 16, p.faint)),
                const SizedBox(width: 6),
                Text(
                  'tippani',
                  style: _serif(14, 18, p.ink, weight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  'টিপ্পনী',
                  style: TextStyle(
                    fontFamily: 'NotoSerifBengali',
                    fontSize: 12,
                    height: 16 / 12,
                    color: p.faint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The grain: the tile laid twice over the card, at a coarse and a fine size. The coarse one is plain alpha, the fine
/// one is an overlay, as the web composites it. Each tile has a mean grey of 128, so the overlay does not move
/// the card's colour.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.tile, this.image);

  final ShareTile tile;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || tile.asset == null) return;
    final rect = Offset.zero & size;
    void pass(double px, BlendMode mode) {
      final k = px / img.width;
      final shader = ImageShader(
        img,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.diagonal3Values(k, k, 1).storage,
        filterQuality: FilterQuality.medium,
      );
      canvas.saveLayer(
        rect,
        Paint()
          ..blendMode = mode
          ..color = Color.fromRGBO(0, 0, 0, tile.strength),
      );
      canvas.drawRect(rect, Paint()..shader = shader);
      canvas.restore();
    }

    pass(tile.coarse, BlendMode.srcOver);
    pass(tile.fine, BlendMode.overlay);
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.image != image || old.tile != tile;
}

/// The Tippani mark, from the same vector the web draws (a 256 box, ink from (21.43, 23.37)).
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.red);

  final Color red;

  static const _cream = Color(0xFFF4EDDE);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 213.14;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-21.43, -23.37);
    final fill = Paint()..color = red;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21.43, 23.37, 213.14, 178.04),
        const Radius.circular(44.51),
      ),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(84, 190)
        ..lineTo(128, 190)
        ..lineTo(78, 229)
        ..close(),
      fill,
    );
    final cream = Paint()..color = _cream;
    final stroke = Paint()
      ..color = _cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    for (final cx in [72.0, 152.0]) {
      canvas.drawCircle(Offset(cx, 128), 31, cream);
      canvas.drawLine(Offset(cx + 13, 104), Offset(cx + 6, 74), stroke);
    }
    for (final y in [45.39, 82.72, 120.05, 157.38]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(197.24, y, 22, 22),
          const Radius.circular(6.8),
        ),
        cream,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.red != red;
}
