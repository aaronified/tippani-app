import '../library/library_store.dart';
import '../library/models.dart';

String foldTag(String s) => s.trim().toLowerCase();

QuoteDraft _draftOf(Quote q, List<String> tags) => QuoteDraft(
  text: q.text,
  workId: q.workId,
  translation: q.translation,
  language: q.language,
  speaker: q.speaker,
  chapter: q.chapter,
  location: q.location,
  note: q.note,
  color: q.color,
  favorite: q.favorite,
  notedAt: q.notedAt,
  source: q.source,
  tags: tags,
  boardId: q.boardId,
);

Future<List<Quote>> _all(LibraryStore store) => store.quotes(limit: 1 << 30);

/// How many quotes on the phone wear each tag, by the tag's own spelling.
Future<Map<String, int>> localTagCounts(LibraryStore store) async {
  final out = <String, int>{};
  final spelling = <String, String>{};
  for (final q in await _all(store)) {
    for (final t in q.tags) {
      final key = spelling.putIfAbsent(foldTag(t), () => t);
      out[key] = (out[key] ?? 0) + 1;
    }
  }
  return out;
}

/// Gives the quotes wearing any of [from] the tag [to] instead (or, when [to] is null, takes the tags off).
/// A quote that already wears [to] just loses the other. Each changed quote is saved as an edit, so it travels
/// to the server with the next sync. Returns how many quotes changed.
Future<int> retag(LibraryStore store, List<String> from, {String? to}) async {
  final drop = {for (final f in from) foldTag(f)};
  final plans = <(Quote, List<String>)>[];
  for (final q in await _all(store)) {
    if (!q.tags.any((t) => drop.contains(foldTag(t)))) continue;
    final next = <String>[];
    var placed = false;
    for (final t in q.tags) {
      final dropped = drop.contains(foldTag(t));
      final isTo = to != null && foldTag(t) == foldTag(to);
      if (dropped || isTo) {
        // a quote already wearing [to] under another spelling keeps one copy, spelt as [to]
        if (to != null && !placed) {
          next.add(to);
          placed = true;
        }
      } else {
        next.add(t);
      }
    }
    plans.add((q, next));
  }
  // The store keeps a tag's first spelling for as long as any quote wears it, so a change of capitals first
  // takes the tag off every quote (which retires the old spelling) and then puts the new one on.
  if (to != null && from.length == 1 && foldTag(from.single) == foldTag(to)) {
    for (final (q, next) in plans) {
      await store.updateQuote(
        q.id,
        _draftOf(q, [
          for (final t in next)
            if (t != to) t,
        ]),
      );
    }
  }
  for (final (q, next) in plans) {
    await store.updateQuote(q.id, _draftOf(q, next));
  }
  return plans.length;
}

/// Renames [from] to [to] on every quote (merging into it when a tag called [to] exists).
Future<int> renameTagLocal(LibraryStore store, String from, String to) =>
    retag(store, [from], to: to);

/// Folds each of [drops] into [keep].
Future<int> mergeTagsLocal(
  LibraryStore store,
  String keep,
  List<String> drops,
) => retag(store, drops, to: keep);

/// Takes [name] off every quote.
Future<int> deleteTagLocal(LibraryStore store, String name) =>
    retag(store, [name]);
