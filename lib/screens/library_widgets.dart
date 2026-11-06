import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText;
import '../library/library_store.dart';
import '../library/markdown_export.dart';
import '../library/models.dart';
import 'quote_form_screen.dart';

/// One quote in a list: its words, who and what it is from, and a star to favourite it.
class QuoteTile extends StatelessWidget {
  const QuoteTile({
    super.key,
    required this.quote,
    required this.work,
    required this.onTap,
    required this.onFavourite,
  });

  final Quote quote;
  final Work? work;
  final VoidCallback onTap;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final from = [
      if (quote.speaker.isNotEmpty) quote.speaker,
      if (work != null) work!.title,
      if (quote.chapter.isNotEmpty) quote.chapter,
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 6, height: 72, color: quoteColour(quote.color)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge,
                    ),
                    if (from.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(from, style: text.bodySmall),
                    ],
                    if (quote.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        quote.tags.map((t) => '#$t').join('  '),
                        style: text.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: quote.favorite ? 'Remove from favourites' : 'Favourite',
              icon: Icon(quote.favorite ? Icons.star : Icons.star_border),
              onPressed: onFavourite,
            ),
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
