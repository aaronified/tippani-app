import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../library/models.dart';
import '../library/quote_text.dart';
import 'quote_form_screen.dart' show quoteColour;

/// A quote drawn as a card: the words large, the translation under them, who and what it is from, and an
/// edge in the quote's own colour. The same widget is what the reader sees and what becomes the picture
/// they share or save, so the picture is never different from the screen.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote, required this.work});

  final Quote quote;
  final Work? work;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = quoteAttribution(quote, work);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(color: quoteColour(quote.color), width: 8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“${quote.text.trim()}”',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              height: 1.35,
            ),
          ),
          if (quote.translation.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              quote.translation.trim(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (from.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '— $from',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The picture of what [key]'s [RepaintBoundary] is showing, as a PNG about [width] pixels wide. Null when
/// it is not on screen (nothing to draw).
Future<Uint8List?> captureCard(GlobalKey key, {double width = 1080}) async {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderRepaintBoundary || !box.hasSize || box.size.width == 0) {
    return null;
  }
  final image = await box.toImage(pixelRatio: width / box.size.width);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
