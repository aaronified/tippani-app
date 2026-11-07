import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../library/models.dart';
import '../library/quote_text.dart';
import '../library/share_format.dart';
import '../theme/app_theme.dart';
import 'quote_form_screen.dart' show quoteColour;

/// A quote drawn as a card: the words large, the translation under them, who and what it is from, and an
/// edge in the quote's own colour. The same widget is what the reader sees and what becomes the picture
/// they share or save, so the picture is never different from the screen.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    required this.work,
    this.show,
  });

  final Quote quote;
  final Work? work;

  /// Which parts to draw, by the ids in `share_format.dart`. Null draws the words, the translation and the
  /// whole credit (what the quote screen shows).
  final Set<String>? show;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = show;
    final from = on == null
        ? quoteAttribution(quote, work)
        : shareCredit(quote, work, on);
    final showQuote = on == null || on.contains('quote');
    final showTranslation = on == null || on.contains('translation');
    final note = on != null && on.contains('note') ? quote.note.trim() : '';
    final tags = on != null && on.contains('tags') && quote.tags.isNotEmpty
        ? quote.tags.map((t) => '#$t').join(' ')
        : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: scheme.surfaceContainerHigh,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 8, color: quoteColour(quote.color)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showQuote)
                        Text(
                          '“${quote.text.trim()}”',
                          style: quoteStyle(
                            context,
                            size: 24,
                            height: 1.4,
                            weight: FontWeight.w500,
                          ),
                        ),
                      if (showTranslation &&
                          quote.translation.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          quote.translation.trim(),
                          style: quoteStyle(
                            context,
                            size: 17,
                            color: scheme.onSurfaceVariant,
                            style: FontStyle.italic,
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
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          note,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          tags,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
