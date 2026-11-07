import '../library/quote_chips.dart';
import '../people/face_stack.dart';
import 'quote_chips_row.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText;
import '../library/library_store.dart';
import '../library/markdown_export.dart';
import '../library/models.dart';
import '../library/cover_cache.dart' show WorkCover;
import '../theme/app_theme.dart';
import 'quote_form_screen.dart';
import 'work_form_screen.dart' show workKindLabel;

/// One quote in a list: its words in the serif, who and what it is from, a thin edge in the quote's colour,
/// and a star to favourite it.
class QuoteTile extends StatelessWidget {
  const QuoteTile({
    super.key,
    required this.quote,
    required this.work,
    required this.onTap,
    required this.onFavourite,
    this.onChip,
    this.chipWork,
    this.omitAuthor = false,
    this.onAddToAnthology,
  });

  final Quote quote;
  final Work? work;
  final VoidCallback onTap;
  final VoidCallback onFavourite;

  /// What pressing a person chip does. Null draws no chips, and the speaker stays in the line of text.
  final ValueChanged<ChipFilter>? onChip;

  /// The work to draw the pills from when [work] is left out of the line of text (on the work's own page); the
  /// author's pill is dropped there ([omitAuthor]) since the header names them.
  final Work? chipWork;
  final bool omitAuthor;

  /// Puts the quote in an anthology. Null where there is no anthology to add to (no server, or the quote is
  /// not on it yet): there is no button then, and a long press does nothing.
  final VoidCallback? onAddToAnthology;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final chips =
        onChip != null &&
        chipsFor(quote, chipWork ?? work, omitAuthor: omitAuthor).isNotEmpty;
    final from = [
      if (quote.speaker.isNotEmpty && !chips) quote.speaker,
      if (work != null) work!.title,
      if (quote.chapter.isNotEmpty) quote.chapter,
    ].join(' \u00b7 ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          onTap: onTap,
          onLongPress: onAddToAnthology,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 4,
                            decoration: BoxDecoration(
                              color: quoteColour(quote.color),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        quote.text,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: quoteStyle(context, size: 17),
                      ),
                      if (from.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          from,
                          style: text.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (chips) ...[
                        const SizedBox(height: 8),
                        QuoteChipsRow(
                          quote: quote,
                          work: chipWork ?? work,
                          dense: true,
                          omitAuthor: omitAuthor,
                          onTap: onChip!,
                        ),
                      ],
                      if (quote.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          quote.tags.map((t) => '#$t').join('  '),
                          style: text.labelSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      tooltip: quote.favorite
                          ? 'Remove from favourites'
                          : 'Favourite',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        quote.favorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: quote.favorite
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      onPressed: onFavourite,
                    ),
                    if (onAddToAnthology != null)
                      IconButton(
                        tooltip: 'Add to anthology',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.collections_bookmark_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: onAddToAnthology,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A work in a list: its cover (or a monogram on a colour taken from its title, where it has none), the title,
/// who made it and what kind it is.
class WorkTile extends StatelessWidget {
  const WorkTile({super.key, required this.work, required this.onTap});

  final Work work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      if (work.creator.isNotEmpty) work.creator,
      if (work.year != null) '${work.year}',
    ].join(' \u00b7 ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                WorkCover(
                  work: work,
                  width: 56,
                  height: 80,
                  fallback: MonogramCover(work: work, width: 56, height: 80),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              workKindLabel(work.kind).toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          FaceStack(
                            names: creditNames(work.creator),
                            ringColor:
                                theme.cardTheme.color ??
                                scheme.surfaceContainerLow,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A cover for a work that has no picture: its first letter in the serif, on one of the theme's container
/// colours chosen from the title, so the same book is always the same colour.
class MonogramCover extends StatelessWidget {
  const MonogramCover({
    super.key,
    required this.work,
    this.width = 56,
    this.height = 80,
  });

  final Work work;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    var h = 0;
    for (final c in work.title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final (bg, fg) = pairs[h % pairs.length];
    final letter = work.title.trim().isEmpty
        ? '?'
        : String.fromCharCode(work.title.trim().runes.first).toUpperCase();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, scheme.surface, 0.35)!],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: quoteFont,
          fontSize: width * 0.52,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// What a list says when it is empty: a quiet icon, a line, and what to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Markdown for the whole library, or for one work.
Future<String> markdownFor(LibraryStore store, {Work? work}) async {
  final works = work == null ? await store.works() : [work];
  final quotes = await store.quotes(workId: work?.id, limit: 1 << 30);
  return libraryMarkdown(works, quotes);
}

/// What an export of [work] (or of everything) is called as a file.
String exportFileName(Work? work) {
  if (work == null) return 'tippani-library.md';
  final safe = work.title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
      .trim();
  return 'tippani-${safe.isEmpty ? 'work' : safe}.md';
}

enum ExportKind { share, save }

/// The export menu shared by the library and a work's page. It says so when there is nothing to export, so
/// an empty file is never handed over.
Future<void> runExport(
  BuildContext context, {
  required LibraryStore store,
  required ShareText share,
  required BackupPicker picker,
  required ExportKind kind,
  Work? work,
}) async {
  final md = await markdownFor(store, work: work);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (md.trim().isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('There are no quotes to export yet.')),
    );
    return;
  }
  try {
    if (kind == ExportKind.share) {
      await share(md, 'Tippani quotes');
    } else {
      final saved = await picker.save(
        exportFileName(work),
        Uint8List.fromList(utf8.encode(md)),
      );
      messenger.showSnackBar(
        SnackBar(content: Text(saved ? 'Saved.' : 'Nothing was saved.')),
      );
    }
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('The export could not be written.')),
    );
  }
}
