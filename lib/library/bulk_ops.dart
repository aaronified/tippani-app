import '../sync/fingerprint.dart' show realmOfKind;
import 'library_store.dart';
import 'models.dart';

/// A quote as a draft, so an edit can start from what it already says.
extension QuoteAsDraft on Quote {
  QuoteDraft toDraft({
    String? color,
    bool? favorite,
    List<String>? tags,
    String? language,
    String? speaker,
    String? chapter,
    String? location,
    int? workId,
  }) => QuoteDraft(
    text: text,
    workId: workId ?? this.workId,
    translation: translation,
    language: language ?? this.language,
    speaker: speaker ?? this.speaker,
    chapter: chapter ?? this.chapter,
    location: location ?? this.location,
    note: note,
    color: color ?? this.color,
    favorite: favorite ?? this.favorite,
    notedAt: notedAt,
    source: source,
    tags: tags ?? this.tags,
    boardId: boardId,
  );
}

/// A work as a draft.
extension WorkAsDraft on Work {
  WorkDraft toDraft({String? creator, String? language, int? year}) =>
      WorkDraft(
        title: title,
        kind: kind,
        creator: creator ?? this.creator,
        year: year ?? this.year,
        language: language ?? this.language,
      );
}

/// A field of a quote the reader can set on many at once.
enum QuoteField {
  speaker('Who said it'),
  chapter('Chapter'),
  location('Page or position'),
  language('Language of the words');

  const QuoteField(this.label);
  final String label;
}

/// A field of a work the reader can set on many at once.
enum WorkField {
  creator('Author, director or studio'),
  language('Language'),
  year('Year');

  const WorkField(this.label);
  final String label;
}

/// What a bulk change did: how many it changed, and how many it left alone (and why, in [note]).
class BulkResult {
  const BulkResult(this.changed, {this.skipped = 0, this.note = ''});
  final int changed;
  final int skipped;
  final String note;
}

/// The changes that can be made to many quotes or works at once. Each one is an ordinary edit of each row (so it
/// gets a new `updated_at` and the next sync sends it), made on the phone's own library: it works with no server.
class BulkOps {
  const BulkOps(this.store);
  final LibraryStore store;

  Future<BulkResult> recolour(List<Quote> quotes, String color) async {
    var n = 0;
    for (final q in quotes) {
      if (q.color == color) continue;
      await store.updateQuote(q.id, q.toDraft(color: color));
      n++;
    }
    return BulkResult(n, skipped: quotes.length - n);
  }

  Future<BulkResult> favourite(List<Quote> quotes, bool on) async {
    var n = 0;
    for (final q in quotes) {
      if (q.favorite == on) continue;
      await store.setFavorite(q.id, on);
      n++;
    }
    return BulkResult(n, skipped: quotes.length - n);
  }

  Future<BulkResult> addTag(List<Quote> quotes, String tag) async {
    final t = tag.trim().replaceFirst(RegExp(r'^#'), '');
    if (t.isEmpty) return BulkResult(0, skipped: quotes.length);
    var n = 0;
    for (final q in quotes) {
      if (q.tags.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
      await store.updateQuote(q.id, q.toDraft(tags: [...q.tags, t]));
      n++;
    }
    return BulkResult(n, skipped: quotes.length - n);
  }

  Future<BulkResult> removeTag(List<Quote> quotes, String tag) async {
    final t = tag.trim().toLowerCase();
    var n = 0;
    for (final q in quotes) {
      if (!q.tags.any((x) => x.toLowerCase() == t)) continue;
      await store.updateQuote(
        q.id,
        q.toDraft(
          tags: [
            for (final x in q.tags)
              if (x.toLowerCase() != t) x,
          ],
        ),
      );
      n++;
    }
    return BulkResult(n, skipped: quotes.length - n);
  }

  Future<BulkResult> setQuoteField(
    List<Quote> quotes,
    QuoteField field,
    String value,
  ) async {
    final v = value.trim();
    var n = 0;
    for (final q in quotes) {
      final now = switch (field) {
        QuoteField.speaker => q.speaker,
        QuoteField.chapter => q.chapter,
        QuoteField.location => q.location,
        QuoteField.language => q.language,
      };
      if (now == v) continue;
      await store.updateQuote(q.id, switch (field) {
        QuoteField.speaker => q.toDraft(speaker: v),
        QuoteField.chapter => q.toDraft(chapter: v),
        QuoteField.location => q.toDraft(location: v),
        QuoteField.language => q.toDraft(language: v),
      });
      n++;
    }
    return BulkResult(n, skipped: quotes.length - n);
  }

  Future<BulkResult> setWorkField(
    List<Work> works,
    WorkField field,
    String value,
  ) async {
    final v = value.trim();
    final year = field == WorkField.year ? int.tryParse(v) : null;
    if (field == WorkField.year && v.isNotEmpty && year == null) {
      return BulkResult(
        0,
        skipped: works.length,
        note: 'The year must be a number.',
      );
    }
    var n = 0;
    for (final w in works) {
      final same = switch (field) {
        WorkField.creator => w.creator == v,
        WorkField.language => w.language == v,
        WorkField.year => w.year == year,
      };
      if (same) continue;
      await store.updateWork(w.id, switch (field) {
        WorkField.creator => w.toDraft(creator: v),
        WorkField.language => w.toDraft(language: v),
        WorkField.year => WorkDraft(
          title: w.title,
          kind: w.kind,
          creator: w.creator,
          year: year,
          language: w.language,
        ),
      });
      n++;
    }
    return BulkResult(n, skipped: works.length - n);
  }

  /// Files standalone quotes on [boardId] (null: on none). A quote from a work is never on a board, so those
  /// are left alone and counted.
  Future<BulkResult> moveToBoard(List<Quote> quotes, int? boardId) async {
    var n = 0, left = 0;
    for (final q in quotes) {
      if (q.workId != null || q.boardId == boardId) {
        left++;
        continue;
      }
      await store.setQuoteBoard(q.id, boardId);
      n++;
    }
    return BulkResult(
      n,
      skipped: left,
      note: quotes.any((q) => q.workId != null)
          ? 'Quotes from a book or film are not filed on boards.'
          : '',
    );
  }

  /// Deletes the quotes and hands back what each said, so [restore] can put them back.
  Future<List<QuoteDraft>> delete(List<Quote> quotes) async {
    final drafts = [for (final q in quotes) q.toDraft()];
    for (final q in quotes) {
      await store.deleteQuote(q.id);
    }
    return drafts;
  }

  /// Puts back what [delete] removed. They are new rows (the server's bin holds the old ones), with all they said.
  Future<void> restore(List<QuoteDraft> drafts) async {
    for (final d in drafts) {
      await store.addQuote(d);
    }
  }

  /// Moves the quotes of every work in [sources] onto [target] and deletes the emptied works. Only works of the
  /// same family as the target (books with books, films, shows and games together) are merged, because a book's
  /// highlight and a film's line are different things on the server.
  Future<BulkResult> mergeWorks(Work target, List<Work> sources) async {
    final realm = realmOfKind(target.kind);
    var merged = 0, left = 0;
    for (final s in sources) {
      if (s.id == target.id || realmOfKind(s.kind) != realm) {
        left++;
        continue;
      }
      final qs = await store.quotes(workId: s.id, limit: 1 << 30);
      for (final q in qs) {
        await store.updateQuote(q.id, q.toDraft(workId: target.id));
      }
      await store.deleteWork(s.id);
      merged++;
    }
    return BulkResult(
      merged,
      skipped: left,
      note: left > 0
          ? 'Only works of the same kind are merged (books with books, films and shows together).'
          : '',
    );
  }
}

/// Whether [a] and [b] could be merged (the same family of work).
bool canMerge(Work a, Work b) => realmOfKind(a.kind) == realmOfKind(b.kind);
