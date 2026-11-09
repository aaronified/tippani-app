import '../library/quote_chips.dart';
import '../people/face_stack.dart';
import 'quote_chips_row.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/library_store.dart';
import '../library/markdown_export.dart';
import '../library/models.dart';
import '../library/share_format.dart';
import '../speech/quote_speech.dart';
import '../widgets/edge_fade_row.dart';
import '../library/cover_cache.dart' show WorkCover;
import '../theme/app_theme.dart';
import 'quote_form_screen.dart';
import 'shelf_card.dart' show shelfStatusLabel;
import 'work_form_screen.dart' show workKindLabel;
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// One quote in a list, as a card: the work it is from in a header (cover, title, who made it and where in it), the
/// words in the serif beside a bar in the quote's colour, the people on it as chips, and a footer with its tags and
/// the things to do with it (copy, read aloud, share, more). Pressing the card opens the quote.
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
    this.onLongPress,
    this.selected = false,
    this.share = shareThroughSheet,
  });

  final Quote quote;
  final Work? work;
  final VoidCallback onTap;
  final VoidCallback onFavourite;

  /// What pressing a person chip does. Null draws no chips, and the speaker stays in the header.
  final ValueChanged<ChipFilter>? onChip;

  /// The work to draw the pills from when [work] is left out of the header (on the work's own page, which already
  /// names it); the author's pill is dropped there ([omitAuthor]) since the page names them.
  final Work? chipWork;
  final bool omitAuthor;

  /// Puts the quote in an anthology. Null where there is no anthology to add to (no server, or the quote is
  /// not on it yet): it is not in the menu then, and a long press does nothing.
  final VoidCallback? onAddToAnthology;

  /// Starts selecting this quote. When null a long press adds it to an anthology (where that can be done).
  final VoidCallback? onLongPress;

  /// Whether the quote is one of those selected.
  final bool selected;

  /// Hands text to the share sheet. A parameter so a test can stand in for it.
  final ShareText share;

  Work? get _source => chipWork ?? work;

  Future<void> _copy(BuildContext context) async {
    final on = shareDefaults(shareFieldsOf(quote, _source));
    final text = buildShareText(quote, _source, on, ShareFormat.plain);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(context.tr('account.widget.copied'))),
      );
  }

  Future<void> _share() {
    final on = shareDefaults(shareFieldsOf(quote, _source));
    return share(buildShareText(quote, _source, on, ShareFormat.plain), '');
  }

  Future<void> _speak(BuildContext context) async {
    final language = quote.language.isNotEmpty
        ? quote.language
        : (_source?.language ?? '');
    final ok = await QuoteSpeech.instance.toggle(
      quote.id,
      quote.text,
      language,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.tr('app.quote_card.no_voice', {'language': language}),
            ),
          ),
        );
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final chips =
        onChip != null &&
        chipsFor(quote, _source, omitAuthor: omitAuthor).isNotEmpty;
    // the header names the work; on a work's own page the page does, so there is none
    final header = work != null || chipWork == null;
    final where = [
      if (quote.speaker.isNotEmpty && !chips) quote.speaker,
      if (work != null && work!.creator.isNotEmpty) work!.creator,
      if (quote.chapter.isNotEmpty) quote.chapter,
      if (quote.location.isNotEmpty) quote.location,
      if (work == null && chipWork == null)
        context.tr('app.quote_card.noted_on', {'date': _day(quote.notedAt)}),
    ].join(' · ');

    final star = IconButton(
      tooltip: quote.favorite
          ? context.tr('common.action.favourite.off.label')
          : context.tr('common.field.favourite.label'),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        quote.favorite ? Ti.starFilled : Ti.star,
        color: quote.favorite ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onPressed: onFavourite,
    );
    final words = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: quoteColour(quote.color),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              quote.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: quoteStyle(context, size: 17, language: quote.language),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        color: selected ? scheme.secondaryContainer : null,
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.primary, width: 2),
              )
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress ?? onAddToAnthology,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (header)
                  Row(
                    children: [
                      if (work != null)
                        WorkCover(
                          work: work!,
                          width: 36,
                          height: 52,
                          fallback: MonogramCover(
                            work: work!,
                            width: 36,
                            height: 52,
                          ),
                        )
                      else
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Ti.notes,
                            size: 20,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              work?.title ?? context.tr('app.quote_card.note'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                            if (where.isNotEmpty)
                              Text(
                                where,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      star,
                    ],
                  ),
                if (header)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
                    child: words,
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: words,
                        ),
                      ),
                      star,
                    ],
                  ),
                if (chips)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
                    child: QuoteChipsRow(
                      quote: quote,
                      work: _source,
                      dense: true,
                      omitAuthor: omitAuthor,
                      onTap: onChip!,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: quote.tags.isEmpty
                          ? Text(
                              context.tr('app.quote_card.no_tags'),
                              style: text.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : EdgeFadeRow(
                              gap: 6,
                              children: [
                                for (final t in quote.tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '#$t',
                                      style: text.labelMedium?.copyWith(
                                        color: scheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 4),
                    _CardActions(
                      onCopy: () => _copy(context),
                      onSpeak: () => _speak(context),
                      quoteId: quote.id,
                      onShare: _share,
                      onOpen: onTap,
                      onSelect: onLongPress,
                      onAddToAnthology: onAddToAnthology,
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

/// The card's footer buttons: Copy, Speak (Stop while it reads), Share, and a menu with the rest.
class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.onCopy,
    required this.onSpeak,
    required this.quoteId,
    required this.onShare,
    required this.onOpen,
    this.onSelect,
    this.onAddToAnthology,
  });

  final VoidCallback onCopy, onSpeak, onShare, onOpen;
  final int quoteId;
  final VoidCallback? onSelect, onAddToAnthology;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget button(String tip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20, color: muted),
          onPressed: onPressed,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(context.tr('common.action.copy.label'), Ti.copy, onCopy),
        ListenableBuilder(
          listenable: QuoteSpeech.instance,
          builder: (context, _) {
            final on = QuoteSpeech.instance.speaking == quoteId;
            return button(
              on
                  ? context.tr('settings.jobs.current.stop.label')
                  : context.tr('speech.play.aria'),
              on ? Ti.playerStopFilled : Ti.volume,
              onSpeak,
            );
          },
        ),
        button(context.tr('common.action.share.label'), Ti.share2, onShare),
        PopupMenuButton<VoidCallback>(
          tooltip: context.tr('settings.appearance.contrast.more.label'),
          padding: EdgeInsets.zero,
          icon: Icon(Ti.dotsVertical, size: 20, color: muted),
          onSelected: (run) => run(),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: onOpen,
              child: Text(context.tr('app.quote_card.open')),
            ),
            if (onSelect != null)
              PopupMenuItem(
                value: onSelect!,
                child: Text(context.tr('common.selection.menu.select.label')),
              ),
            if (onAddToAnthology != null)
              PopupMenuItem(
                value: onAddToAnthology!,
                child: Text(context.tr('common.action.anthology.label')),
              ),
          ],
        ),
      ],
    );
  }
}

/// A work in a list: its cover (or a monogram on a colour taken from its title, where it has none), the title,
/// who made it and what kind it is.
class WorkTile extends StatelessWidget {
  const WorkTile({
    super.key,
    required this.work,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Work work;
  final VoidCallback onTap;

  /// Starts selecting this work.
  final VoidCallback? onLongPress;
  final bool selected;

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
        color: selected ? scheme.secondaryContainer : null,
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.primary, width: 2),
              )
            : null,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
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
                      if (work.details.status.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          work.details.progress > 0 &&
                                  work.details.status != 'completed'
                              ? '${shelfStatusLabel(context, work.details.status)} · ${work.details.progress}%'
                              : shelfStatusLabel(context, work.details.status),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: work.details.status == 'completed'
                                ? scheme.tertiary
                                : scheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (work.details.progress > 0 &&
                            work.details.status != 'completed' &&
                            work.details.status != 'abandoned')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: work.details.progress / 100,
                                minHeight: 3,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Icon(Ti.chevronRight, color: scheme.onSurfaceVariant),
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
  final tr = context.tr;
  final md = await markdownFor(store, work: work);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (md.trim().isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('app.library.there_are_no_quotes_to_export'))),
    );
    return;
  }
  try {
    if (kind == ExportKind.share) {
      await share(md, context.tr('app.library.tippani_quotes'));
    } else {
      final saved = await picker.save(
        exportFileName(work),
        Uint8List.fromList(utf8.encode(md)),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? tr('account.notify.saved')
                : tr('app.library.nothing_was_saved'),
          ),
        ),
      );
    }
  } on Object {
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('app.library.the_export_could_not_be_written')),
      ),
    );
  }
}
