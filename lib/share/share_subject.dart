import '../anthologies/anthologies.dart';
import '../l10n/l10n.dart';
import '../library/markdown_export.dart';
import '../library/models.dart';
import '../library/share_format.dart';

/// What the share screen is sending: one quote, several quotes (a selection, a whole work, the library), or an
/// anthology. The screen is the same for all three (the same formats row, the same text, the same Share, Copy and
/// Save); the subject says which formats make sense, what the parts are, and how each format is written.
sealed class ShareSubject {
  const ShareSubject();

  /// The formats this offers, in the order they are drawn; the first is chosen when the screen opens.
  List<ShareFormat> get formats;

  /// The format the screen opens on.
  ShareFormat get firstFormat => formats.first;

  /// What the sheet is told the share is about, and how the file is named (before its extension).
  String get title;
  String get fileStem;

  /// A short line under the heading saying what is being sent; empty for one quote, which is on the screen.
  String get summary;
}

/// One quote, with the work it is from. The only subject that can be sent as a picture.
final class QuoteShare extends ShareSubject {
  const QuoteShare(this.quote, this.work);

  final Quote quote;
  final Work? work;

  @override
  List<ShareFormat> get formats => const [
    ShareFormat.picture,
    ShareFormat.plain,
    ShareFormat.markdown,
    ShareFormat.whatsapp,
    ShareFormat.reddit,
  ];

  @override
  String get title => tx('add.mode.quote.label');

  @override
  String get fileStem => 'tippani-quote-${quote.id}';

  @override
  String get summary => '';
}

/// Several quotes. [works] are the works they are from (for their credit lines and for the Markdown file, which is
/// Tippani's own import format and holds everything each quote has). [work] is set when the quotes are all of one
/// work and it is being shared whole: its name heads the text and is left out of each credit line.
///
/// There is no picture: a picture of two hundred quotes is nothing anyone would send.
final class QuotesShare extends ShareSubject {
  const QuotesShare(this.quotes, this.works, {this.work, this.on});

  /// In the order they should be sent.
  final List<Quote> quotes;
  final List<Work> works;
  final Work? work;

  /// The parts to start with, where the screen that opened this has a say (the work's reading page's switches).
  final Set<String>? on;

  Work? workOf(Quote q) {
    final id = q.workId;
    if (id == null) return null;
    for (final w in works) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// The parts to start with: what a quote starts with, and for a whole work not who and what it is from on every
  /// line (the heading says it once).
  Set<String> defaultOn(List<ShareField> fields) {
    final preset = on;
    if (preset != null) return {...preset};
    return {
      for (final id in shareDefaults(fields))
        if (work == null || !const {'author', 'work', 'year'}.contains(id)) id,
    };
  }

  /// The Tippani Markdown file for these quotes: what [ShareFormat.markdown] sends, whatever the switches say.
  String get markdown => libraryMarkdown(works, quotes);

  @override
  List<ShareFormat> get formats => const [
    ShareFormat.plain,
    ShareFormat.markdown,
    ShareFormat.whatsapp,
    ShareFormat.reddit,
  ];

  /// Opens on the Tippani Markdown, the importable file the old Export menu led with. Where the opener carries the
  /// plain-text switches over ([on], the reading page's), it opens on the plain text those switches shape.
  @override
  ShareFormat get firstFormat =>
      on == null ? ShareFormat.markdown : ShareFormat.plain;

  @override
  String get title => work?.title ?? tx('app.library.tippani_quotes');

  @override
  String get fileStem {
    final w = work;
    if (w == null) return 'tippani-library';
    final safe = w.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .trim();
    return 'tippani-${safe.isEmpty ? 'work' : safe}';
  }

  @override
  String get summary => countWords('quote', quotes.length);
}

/// An anthology, as the reader has ordered it. Its Markdown file and its EPUB book are made by the server, so those
/// two need it; the plain text is made here from [detail].
final class AnthologyShare extends ShareSubject {
  const AnthologyShare(this.detail, this.service);

  final AnthologyDetail detail;
  final AnthologyService service;

  @override
  List<ShareFormat> get formats => const [
    ShareFormat.plain,
    ShareFormat.markdown,
    ShareFormat.epub,
  ];

  @override
  String get title => detail.anthology.title;

  @override
  String get fileStem {
    final safe = detail.anthology.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .trim();
    return 'tippani-${safe.isEmpty ? 'anthology' : safe}';
  }

  @override
  String get summary => countWords('passage', detail.entries.length);
}

/// An anthology as plain text to send: its title and introduction, then each passage with where it is from and the
/// reader's commentary on it.
String anthologyShareText(AnthologyDetail d) {
  final out = StringBuffer(d.anthology.title);
  if (d.anthology.intro.trim().isNotEmpty) {
    out.write('\n\n${d.anthology.intro.trim()}');
  }
  for (final e in d.entries) {
    out.write('\n\n“${e.quote.trim()}”');
    if (e.from.isNotEmpty) out.write('\n— ${e.from}');
    if (e.note.trim().isNotEmpty) out.write('\n${e.note.trim()}');
  }
  return out.toString();
}
