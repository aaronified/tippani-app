import 'models.dart';
import '../l10n/l10n.dart';

/// The ways a quote can be sent. Same five as the web app's share dialog.
enum ShareFormat {
  picture('quotes.board.form.picture.label'),
  plain('app.share_format.plain_text'),
  markdown('share.format.markdown.name'),
  whatsapp('WhatsApp'),
  reddit('share.format.reddit.name');

  const ShareFormat(this.label);
  final String label;

  bool get isText => this != picture;
}

/// One part of a quote that can be switched on or off for a share.
class ShareField {
  const ShareField(this.id, this.label, this.value);

  final String id;
  final String label;

  /// What it says (empty parts are never listed).
  final String value;
}

/// Parts that start switched off, as on the web: where in the work, the save date and the work's year are facts
/// the credit line already carries or a reader does not need.
const shareOffByDefault = {'location', 'noted', 'year'};

String _date(DateTime d) {
  final u = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}';
}

/// The parts this quote has, in the order they read. Only parts with something in them.
List<ShareField> shareFieldsOf(Quote q, Work? w) {
  final out = <ShareField>[];
  void add(String id, String label, String value) {
    if (value.trim().isNotEmpty) out.add(ShareField(id, label, value.trim()));
  }

  add('quote', tx('common.field.quote.label'), q.text);
  add('translation', tx('common.field.translation.label'), q.translation);
  add('speaker', tx('common.field.speaker.label'), q.speaker);
  if (w != null) {
    add('author', tx('common.field.author.label'), w.creator);
    add('work', tx('anthologies.group.work'), w.title);
    add('year', 'Year', w.year == null ? '' : '${w.year}');
  }
  add('chapter', tx('board.sort.chapter.label'), q.chapter);
  add('location', tx('common.field.location.label'), q.location);
  add('noted', tx('share.field.noted.label'), _date(q.notedAt));
  add(
    'tags',
    tx('common.field.tags.label'),
    q.tags.map((t) => '#$t').join(' '),
  );
  add('note', tx('app.share_format.my_note'), q.note);
  return out;
}

/// The switches a freshly opened share starts with.
Set<String> shareDefaults(List<ShareField> fields) => {
  for (final f in fields)
    if (!shareOffByDefault.contains(f.id)) f.id,
};

/// Who and where, on one line, from the switched-on parts: "Thoreau, Walden, Economy".
String shareCredit(Quote q, Work? w, Set<String> on) {
  final fields = {for (final f in shareFieldsOf(q, w)) f.id: f.value};
  return ['speaker', 'author', 'work', 'year', 'chapter', 'location']
      .where(on.contains)
      .map((id) => fields[id] ?? '')
      .where((s) => s.isNotEmpty)
      .join(', ');
}

String _bold(String s, ShareFormat f) => switch (f) {
  ShareFormat.markdown || ShareFormat.reddit => '**$s**',
  ShareFormat.whatsapp => '*$s*',
  _ => s,
};

String _italic(String s, ShareFormat f) => switch (f) {
  ShareFormat.markdown || ShareFormat.reddit => '*$s*',
  ShareFormat.whatsapp => '_${s}_',
  _ => s,
};

/// A quote as text in [format]: the words (a block quote in Markdown and Reddit), the translation, the credit
/// line, then tags and the reader's note, each only when switched on in [on]. People are bold and works italic
/// where the format has them.
String buildShareText(Quote q, Work? w, Set<String> on, ShareFormat format) {
  final fields = {for (final f in shareFieldsOf(q, w)) f.id: f.value};
  final block = format == ShareFormat.markdown || format == ShareFormat.reddit;
  String quoted(String s) =>
      block ? s.split('\n').map((l) => '> $l').join('\n') : s;

  final out = <String>[];
  if (on.contains('quote') && fields['quote'] != null) {
    out.add(quoted('“${fields['quote']}”'));
  }
  if (on.contains('translation') && fields['translation'] != null) {
    out.add(quoted(_italic(fields['translation']!, format)));
  }
  final credit = <String>[
    for (final id in [
      'speaker',
      'author',
      'work',
      'year',
      'chapter',
      'location',
    ])
      if (on.contains(id) && fields[id] != null)
        switch (id) {
          'speaker' || 'author' => _bold(fields[id]!, format),
          'work' => _italic(fields[id]!, format),
          _ => fields[id]!,
        },
  ];
  if (credit.isNotEmpty) out.add('— ${credit.join(', ')}');
  if (on.contains('noted') && fields['noted'] != null) {
    out.add(tx('app.quote.noted_x', {'x': fields['noted']}));
  }
  if (on.contains('tags') && fields['tags'] != null) out.add(fields['tags']!);
  if (on.contains('note') && fields['note'] != null) {
    out.add('Note: ${fields['note']}');
  }
  return out.join('\n\n');
}
