import '../library/library_store.dart';
import '../library/models.dart';

/// What reading a Markdown file into the phone's own library did.
class MarkdownImportResult {
  const MarkdownImportResult({
    required this.works,
    required this.quotes,
    required this.duplicates,
    required this.skippedBlocks,
  });

  /// Works added (a work already on the phone is joined, not counted).
  final int works;

  /// Quotes added.
  final int quotes;

  /// Quotes already on the phone, left as they are.
  final int duplicates;

  /// Blocks this reader does not take (an anthology): the server's importer reads those.
  final int skippedBlocks;
}

/// The file is not Tippani Markdown.
class MarkdownImportException implements Exception {
  const MarkdownImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Block {
  _Block(this.fields);
  final Map<String, String> fields;
  final quotes = <QuoteDraft>[];
}

/// Reads Tippani Markdown (the file the app exports, and the server's own exports of books, films and standalone
/// quotes) into [library]: the inverse of `libraryMarkdown`. A work already on the phone (same title, kind and
/// creator) is joined rather than added twice, and a quote already in it is left alone, so importing the same file
/// twice changes nothing.
Future<MarkdownImportResult> importMarkdown(
  String text,
  LibraryStore library,
) async {
  final lines = text.replaceFirst('﻿', '').split(RegExp(r'\r\n|\r|\n'));
  var first = 0;
  while (first < lines.length && lines[first].trim().isEmpty) {
    first++;
  }
  if (first == lines.length) {
    throw const MarkdownImportException('That file is empty.');
  }
  if (lines[first].startsWith('# ')) {
    throw const MarkdownImportException(
      "That looks like a Readest export. Import it with your server's importer (Settings → Import and checks).",
    );
  }
  if (lines[first].trim() != '---') {
    throw const MarkdownImportException(
      'That is not Tippani Markdown: it should start with a "---" block naming the book or film.',
    );
  }

  // each block opens with "---", its frontmatter closes with "---", and its body has no bare "---"
  final opens = <int>[];
  var inFront = false;
  for (var i = first; i < lines.length; i++) {
    if (lines[i].trim() != '---') continue;
    if (inFront) {
      inFront = false;
    } else {
      opens.add(i);
      inFront = true;
    }
  }

  var skipped = 0;
  final blocks = <_Block>[];
  for (var k = 0; k < opens.length; k++) {
    final end = k + 1 < opens.length ? opens[k + 1] : lines.length;
    final block = _parseBlock(lines.sublist(opens[k] + 1, end));
    if (block == null) {
      skipped++;
    } else {
      blocks.add(block);
    }
  }

  var works = 0, quotes = 0, duplicates = 0;
  for (final b in blocks) {
    final type = (b.fields['type'] ?? 'book').toLowerCase();
    final kind = switch (type) {
      'book' => WorkKind.book,
      'movie' || 'film' => WorkKind.film,
      'show' || 'tv' || 'series' => WorkKind.show,
      'game' => WorkKind.game,
      _ => null,
    };
    int? workId;
    if (type == 'quotes') {
      workId = null;
    } else if (kind == null) {
      skipped++;
      continue;
    } else {
      final title = (b.fields['title'] ?? '').trim();
      if (title.isEmpty) {
        skipped++;
        continue;
      }
      final creator =
          (b.fields['author'] ??
                  b.fields['director'] ??
                  b.fields['creator'] ??
                  '')
              .trim();
      final existing = [
        for (final w in await library.works(kind: kind, query: title))
          if (w.title.toLowerCase() == title.toLowerCase() &&
              (creator.isEmpty ||
                  w.creator.isEmpty ||
                  w.creator.toLowerCase() == creator.toLowerCase()))
            w,
      ];
      if (existing.isNotEmpty) {
        workId = existing.first.id;
      } else {
        final w = await library.addWork(
          WorkDraft(
            title: title,
            kind: kind,
            creator: creator,
            year: int.tryParse(b.fields['year'] ?? ''),
            language: (b.fields['language'] ?? '').trim(),
          ),
        );
        workId = w.id;
        works++;
      }
    }
    final have = <String>{
      for (final q in await library.quotes(workId: workId, limit: 100000))
        if (q.workId == workId) _fold(q.text),
    };
    for (final d in b.quotes) {
      final withWork = QuoteDraft(
        text: d.text,
        workId: workId,
        translation: d.translation,
        language: d.language,
        speaker: d.speaker,
        chapter: d.chapter,
        location: d.location,
        note: d.note,
        color: d.color,
        favorite: d.favorite,
        notedAt: d.notedAt,
        source: 'import',
        tags: d.tags,
      );
      if (!have.add(_fold(d.text))) {
        duplicates++;
        continue;
      }
      await library.addQuote(withWork);
      quotes++;
    }
  }
  return MarkdownImportResult(
    works: works,
    quotes: quotes,
    duplicates: duplicates,
    skippedBlocks: skipped,
  );
}

String _fold(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

_Block? _parseBlock(List<String> lines) {
  final fields = <String, String>{};
  var i = 0;
  for (; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim() == '---') {
      i++;
      break;
    }
    final c = line.indexOf(':');
    if (c < 0) continue;
    fields[line.substring(0, c).trim().toLowerCase()] = line
        .substring(c + 1)
        .trim();
  }
  final type = (fields['type'] ?? 'book').toLowerCase();
  if (type == 'anthology') return null;
  final block = _Block(fields);
  final standalone = type == 'quotes';
  final screen = const {
    'movie',
    'film',
    'show',
    'tv',
    'series',
    'game',
  }.contains(type);

  var heading = '';
  List<String>? open;
  Map<String, String> bind = {};
  var inQuote = false;

  void flush() {
    final o = open;
    if (o == null) return;
    final text = o.join(' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isNotEmpty) {
      String b(List<String> keys) {
        for (final k in keys) {
          final v = bind[k];
          if (v != null && v.isNotEmpty) return v;
        }
        return '';
      }

      block.quotes.add(
        QuoteDraft(
          text: text,
          chapter: screen ? '' : heading,
          location: standalone
              ? b(['place', 'loc', 'location'])
              : screen
              ? b(['timestamp', 'loc', 'location'])
              : b(['loc', 'location', 'page']),
          speaker: standalone
              ? b(['speaker', 'character'])
              : b(['character', 'speaker']),
          translation: b(['translation', 'translated', 'english']),
          language: b(['language', 'lang']),
          note: b(['note']),
          color: b(['color', 'colour']).toLowerCase(),
          favorite: const {
            'true',
            'yes',
            '1',
            'y',
          }.contains(b(['favorite', 'favourite']).toLowerCase()),
          notedAt: _day(b(['date', 'added', 'noted'])),
          tags: [
            for (final t in b(['tags']).split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
        ),
      );
    }
    open = null;
    bind = {};
    inQuote = false;
  }

  for (final line in lines.sublist(i)) {
    if (line.startsWith('>')) {
      if (!inQuote) {
        flush();
        open = [];
        inQuote = true;
      }
      open!.add(line.substring(1).trimLeft());
    } else if (line.trim().isEmpty) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      heading = line.substring(3).trim();
    } else if (open != null && line.startsWith('- ')) {
      final c = line.indexOf(':', 2);
      if (c < 0) continue;
      inQuote = false;
      bind[line.substring(2, c).trim().toLowerCase()] = line
          .substring(c + 1)
          .trim();
    }
  }
  flush();
  return block;
}

DateTime? _day(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), 12);
}
