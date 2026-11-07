import 'dart:async';
import 'dart:typed_data';

import '../api/server_call.dart';
import '../app_controller.dart';

/// One kind of file the server's importer reads, with the steps for getting that file, as the web's import page
/// lists them.
class ImportSource {
  const ImportSource(
    this.kind,
    this.title,
    this.extensions,
    this.about,
    this.steps, {
    this.caveat = '',
  });

  /// The server's own name for the format (the `as` of an import).
  final String kind;
  final String title;
  final List<String> extensions;
  final String about;
  final List<String> steps;
  final String caveat;
}

const importSources = <ImportSource>[
  ImportSource(
    'markdown',
    'Markdown',
    ['md', 'markdown', 'txt'],
    'Tippani exports of books or the catalogue, or a Readest export.',
    [
      'Import a Tippani export (books or catalogue), a Readest export, or your own frontmatter and quotes.',
      'A single .md may hold many books or titles. Each one is imported.',
    ],
  ),
  ImportSource(
    'readest',
    'Readest',
    ['json'],
    "Readest's annotation export. Colours and the date of each highlight come across.",
    [
      "In Readest, open the book's annotations and export them.",
      "Import the .json. Readest's Markdown export is read too.",
    ],
  ),
  ImportSource(
    'bookcision',
    'Bookcision',
    ['json'],
    'Kindle highlights through the Bookcision bookmarklet.',
    [
      "On read.amazon.com/notebook, open the book's Notes & Highlights.",
      'Run the Bookcision bookmarklet, then Download → JSON, and import that file.',
      "Without the bookmarklet, import the saved Kindle notebook page instead. It keeps the colours.",
    ],
  ),
  ImportSource(
    'hardcover-html',
    'Hardcover',
    ['html', 'htm'],
    'Your reading-journal page for one book.',
    [
      'Open your journal page, for example hardcover.app/books/<book>/journals/@you.',
      'Save it as a web page, HTML only.',
      'Import the saved .html.',
    ],
  ),
  ImportSource(
    'goodreads-html',
    'Goodreads',
    ['html', 'htm'],
    "A book's public Quotes page. Quote tags come across too.",
    [
      "Open the book's Quotes page, for example goodreads.com/work/quotes/<id>-<book>.",
      'Save it as a web page, HTML only.',
      'Import the saved .html.',
    ],
  ),
  ImportSource(
    'imdb-quotes',
    'IMDb quotes',
    ['html', 'htm'],
    "A film or show's Quotes page, imported as dialogues.",
    [
      "Open the title's Quotes page, for example imdb.com/title/tt0434409/quotes.",
      'Save it as a web page, HTML only.',
      'Import the saved .html.',
    ],
  ),
  ImportSource(
    'kindle-notebook',
    'Kindle notebook',
    ['html', 'htm'],
    'Your Kindle Notes & Highlights page. Colours and locations come across.',
    [
      'Open read.amazon.com/notebook and pick the book.',
      'Save it as a web page, HTML only.',
      'Import the saved .html.',
    ],
  ),
  ImportSource(
    'kindle-clippings',
    'My Clippings',
    ['txt'],
    "The Kindle device's own file. Every book at once, highlights and notes.",
    [
      'Plug the Kindle in by USB.',
      'Copy documents/My Clippings.txt off the device.',
      'Import it. Every book in the file lands at once.',
    ],
    caveat: "Kindle's clippings format is undocumented and changes by device language, so some entries may not read correctly. Anything unreadable is skipped and counted.",
  ),
];

ImportSource? importSourceOf(String kind) {
  for (final s in importSources) {
    if (s.kind == kind) return s;
  }
  return null;
}

/// Every file extension an import can take, for the file chooser.
List<String> get importExtensions =>
    {for (final s in importSources) ...s.extensions}.toList();

/// What reading one file left in the server's queue.
class ImportOutcome {
  const ImportOutcome({
    required this.ok,
    this.source = '',
    this.staged = 0,
    this.works = 0,
    this.nearDuplicates = 0,
    this.pending = 0,
    this.message = '',
    this.unknownFormat = false,
  });

  final bool ok;

  /// The format the server read it as.
  final String source;
  final int staged;
  final int works;
  final int nearDuplicates;

  /// How many quotes now wait in the queue, from every file.
  final int pending;

  /// The server's words when it could not read the file.
  final String message;

  /// True when nothing in the file said what it was: the reader can name the format and try again.
  final bool unknownFormat;
}

/// One import file in the queue.
class StagedBatch {
  const StagedBatch({
    required this.id,
    required this.source,
    required this.filename,
    required this.works,
    required this.quotes,
  });

  final int id;
  final String source;
  final String filename;
  final int works;
  final int quotes;

  factory StagedBatch.fromJson(Map<String, Object?> j) => StagedBatch(
    id: (j['id'] as num).toInt(),
    source: (j['source'] as String?) ?? '',
    filename: (j['filename'] as String?) ?? '',
    works: (j['works'] as num?)?.toInt() ?? 0,
    quotes: (j['quotes'] as num?)?.toInt() ?? 0,
  );
}

/// One destination in the queue: the book, film, show or game the quotes will join, or none (standalone quotes).
class StagedWork {
  const StagedWork({
    required this.id,
    required this.batchId,
    required this.kind,
    required this.title,
    required this.author,
    required this.year,
    required this.quotes,
    required this.targetId,
    required this.targetTitle,
    required this.targetYear,
    required this.ambiguous,
    required this.pinned,
  });

  final int id;
  final int batchId;
  final String kind;
  final String title;
  final String author;
  final int year;
  final int quotes;

  /// The work already in the library these quotes join, or 0 when approving adds a new one.
  final int targetId;
  final String targetTitle;
  final int targetYear;

  /// More than one work has this name: the reader should check it joined the right one.
  final bool ambiguous;

  /// The reader chose the destination.
  final bool pinned;

  bool get standalone => kind == 'quote' || kind.isEmpty && title.isEmpty;

  factory StagedWork.fromJson(Map<String, Object?> j) => StagedWork(
    id: (j['id'] as num).toInt(),
    batchId: (j['batch_id'] as num?)?.toInt() ?? 0,
    kind: (j['kind'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    author: (j['author'] as String?) ?? '',
    year: (j['release_year'] as num?)?.toInt() ?? 0,
    quotes: (j['quotes'] as num?)?.toInt() ?? 0,
    targetId: (j['target_id'] as num?)?.toInt() ?? 0,
    targetTitle: (j['target_title'] as String?) ?? '',
    targetYear: (j['target_year'] as num?)?.toInt() ?? 0,
    ambiguous: j['ambiguous'] == true,
    pinned: j['pinned'] == true,
  );
}

/// One quote waiting to be approved.
class StagedQuote {
  const StagedQuote({
    required this.id,
    required this.workId,
    required this.text,
    required this.note,
    required this.translation,
    required this.color,
    required this.favorite,
    required this.chapter,
    required this.location,
    required this.character,
    required this.actor,
    required this.timestamp,
    required this.tags,
  });

  final int id;
  final int workId;
  final String text, note, translation, color;
  final bool favorite;
  final String chapter, location, character, actor, timestamp;
  final List<String> tags;

  factory StagedQuote.fromJson(Map<String, Object?> j) {
    String s(String k) => (j[k] as String?) ?? '';
    final tags = j['tags'];
    return StagedQuote(
      id: (j['id'] as num).toInt(),
      workId: (j['staged_work_id'] as num?)?.toInt() ?? 0,
      text: s('quote'),
      note: s('note'),
      translation: s('translation'),
      color: s('color'),
      favorite: j['favorite'] == true,
      chapter: s('chapter'),
      location: s('location'),
      character: s('character'),
      actor: s('actor'),
      timestamp: s('timestamp'),
      tags: [
        if (tags is List)
          for (final t in tags) '$t',
      ],
    );
  }
}

/// The whole queue, or one file's part of it.
class Staging {
  const Staging({
    required this.pending,
    required this.batches,
    required this.works,
    required this.quotes,
    required this.total,
  });

  static const empty = Staging(
    pending: 0,
    batches: [],
    works: [],
    quotes: [],
    total: 0,
  );

  /// Every quote waiting, whatever is shown.
  final int pending;
  final List<StagedBatch> batches;
  final List<StagedWork> works;
  final List<StagedQuote> quotes;

  /// What the filter matched (quotes), for "12 of 400".
  final int total;
}

/// Which staged quotes an approval, discard or edit is about. Exactly one form is used.
class StagedSelector {
  const StagedSelector.quotes(this.ids)
    : workIds = const [],
      batchId = 0,
      all = false;
  const StagedSelector.works(List<int> ids)
    : workIds = ids,
      ids = const [],
      batchId = 0,
      all = false;
  const StagedSelector.batch(int id)
    : batchId = id,
      ids = const [],
      workIds = const [],
      all = false;
  const StagedSelector.everything()
    : all = true,
      ids = const [],
      workIds = const [],
      batchId = 0;

  final List<int> ids;
  final List<int> workIds;
  final int batchId;
  final bool all;

  Map<String, Object?> toJson() => {
    if (ids.isNotEmpty) 'ids': ids,
    if (workIds.isNotEmpty) 'work_ids': workIds,
    if (batchId > 0) 'batch_id': batchId,
    if (all) 'all': true,
  };
}

/// What to change on staged quotes. A null field is left alone; an empty string clears it.
class StagedEdit {
  const StagedEdit({
    this.color,
    this.favorite,
    this.chapter,
    this.location,
    this.character,
    this.actor,
    this.timestamp,
    this.addTags = const [],
    this.removeTags = const [],
    this.moveToKind,
    this.moveToId,
    this.shiftField,
    this.shiftOp,
    this.shiftValue,
    this.shiftText,
  });

  final String? color;
  final bool? favorite;
  final String? chapter, location, character, actor, timestamp;
  final List<String> addTags, removeTags;

  /// Pin the selected quotes' group onto a work already in the library: 'book' or 'movie', and its id there.
  final String? moveToKind;
  final int? moveToId;

  /// Shift a locator in bulk: field 'location' or 'timestamp', op add|subtract|multiply|divide|set|reset.
  final String? shiftField, shiftOp, shiftText;
  final double? shiftValue;

  Map<String, Object?> toJson() => {
    if (color != null) 'color': color,
    if (favorite != null) 'favorite': favorite,
    if (chapter != null) 'chapter': chapter,
    if (location != null) 'location': location,
    if (character != null) 'character': character,
    if (actor != null) 'actor': actor,
    if (timestamp != null) 'timestamp': timestamp,
    if (addTags.isNotEmpty) 'add_tags': addTags,
    if (removeTags.isNotEmpty) 'remove_tags': removeTags,
    if (shiftOp != null)
      'formula': {
        'field': shiftField ?? 'location',
        'op': shiftOp,
        if (shiftValue != null) 'value': shiftValue,
        if (shiftText != null) 'text': shiftText,
      },
  };
}

/// What approving the queue did.
class ApprovalOutcome {
  const ApprovalOutcome({
    required this.ok,
    this.added = 0,
    this.skipped = 0,
    this.enriched = 0,
    this.relinked = 0,
    this.message = '',
  });

  final bool ok;
  final int added, skipped, enriched, relinked;
  final String message;
}

/// A book or film the reader can move staged quotes onto.
class WorkChoice {
  const WorkChoice(this.kind, this.id, this.title, this.year, this.creator);

  /// 'book' or 'movie' (a show or game is a movie row on the server).
  final String kind;
  final int id;
  final String title;
  final int year;
  final String creator;
}

/// Importing files on the server and looking over what they staged. An interface so a test can stand in for the
/// server.
abstract class ImportService {
  bool get available;

  /// Sends [bytes] to the server to be read. [as] names the format when the reader chose it; null lets the
  /// server tell from the file. Waits for the server's job to finish, calling [onProgress] as it goes.
  Future<ImportOutcome> importFile(
    String name,
    Uint8List bytes, {
    String? as,
    void Function(int done, int total)? onProgress,
  });

  /// How many quotes wait in the queue (cheap: for a badge).
  Future<int> pending();

  /// The queue, or one file's (or one group's) part of it; [limit] 0 means every quote.
  Future<Staging> staged({
    int batchId = 0,
    int workId = 0,
    int limit = 0,
    int offset = 0,
  });

  /// Approves [selection] into the library and waits for the job.
  Future<ApprovalOutcome> approve(
    StagedSelector selection, {
    void Function(int done, int total)? onProgress,
  });

  Future<int> discard(StagedSelector selection);

  Future<int> edit(StagedSelector selection, StagedEdit change);

  /// Moves the groups of [selection] onto a work in the library ([onto]), or into another group in the queue
  /// ([mergeInto], a staged work's id).
  Future<void> move(
    StagedSelector selection, {
    WorkChoice? onto,
    int? mergeInto,
  });

  Future<List<WorkChoice>> destinations();
}

class PairedImportService implements ImportService {
  PairedImportService(
    this._controller, {
    this._poll = const Duration(milliseconds: 700),
  });

  final AppController _controller;
  final Duration _poll;

  @override
  bool get available => _controller.paired;

  static bool _done(String state) =>
      state != 'queued' && state != 'running' && state.isNotEmpty;

  /// Waits for job [id] to end; returns its job object and its result.
  Future<(Map<String, Object?>, Map<String, Object?>)> _await(
    int id,
    void Function(int, int)? onProgress,
  ) async {
    for (var i = 0; i < 4000; i++) {
      final job = asMap(
        asMap(
          await serverCall(_controller, (c) => c.getJson('/jobs/$id')),
        )['job'],
      );
      final done = (job['done'] as num?)?.toInt() ?? 0;
      final total = (job['total'] as num?)?.toInt() ?? 0;
      onProgress?.call(done, total);
      final state = (job['state'] as String?) ?? '';
      if (_done(state)) {
        Map<String, Object?> result = const {};
        try {
          final r = await serverCall(
            _controller,
            (c) => c.getJson('/jobs/$id/result'),
          );
          final inner = r is Map ? r['result'] : null;
          if (inner is Map) result = Map<String, Object?>.from(inner);
        } on ServerException {
          // the job's own words below are enough
        }
        return (job, result);
      }
      await Future<void>.delayed(_poll);
    }
    throw const ServerException(
      'The server is taking too long. Check it later.',
    );
  }

  static Map<String, Object?> _body(Map<String, Object?> result) {
    final b = result['body'];
    return b is Map ? Map<String, Object?>.from(b) : result;
  }

  @override
  Future<ImportOutcome> importFile(
    String name,
    Uint8List bytes, {
    String? as,
    void Function(int done, int total)? onProgress,
  }) async {
    final started = await serverCall(
      _controller,
      (c) =>
          c.postFile('/import/auto', 'file', bytes, name, fields: {'as': ?as}),
    );
    final id = (asMap(asMap(started)['job'])['id'] as num).toInt();
    final (job, result) = await _await(id, onProgress);
    final status = (result['status'] as num?)?.toInt() ?? 200;
    final body = _body(result);
    final state = (job['state'] as String?) ?? '';
    if (state != 'succeeded' || status >= 400) {
      final msg =
          (body['error'] as String?) ??
          (job['error'] as String?) ??
          'The server could not read that file.';
      return ImportOutcome(
        ok: false,
        message: msg,
        unknownFormat:
            body['unknown_format'] == true ||
            msg.toLowerCase().contains('nothing in this file') ||
            msg.toLowerCase().contains("couldn't tell") ||
            msg.toLowerCase().contains('could not tell'),
      );
    }
    final works = body['works'];
    return ImportOutcome(
      ok: true,
      source: (body['source'] as String?) ?? '',
      staged: (body['staged'] as num?)?.toInt() ?? 0,
      works: works is List ? works.length : 0,
      nearDuplicates: (body['near_duplicates'] as num?)?.toInt() ?? 0,
      pending: (body['pending'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> pending() => serverCall(_controller, (c) async {
    final r = asMap(await c.getJson('/import/staged?counts=1'));
    return (r['pending'] as num?)?.toInt() ?? 0;
  });

  @override
  Future<Staging> staged({
    int batchId = 0,
    int workId = 0,
    int limit = 0,
    int offset = 0,
  }) => serverCall(_controller, (c) async {
    final q = [
      if (batchId > 0) 'batch_id=$batchId',
      if (workId > 0) 'work_id=$workId',
      if (limit > 0) 'limit=$limit',
      if (offset > 0) 'offset=$offset',
    ].join('&');
    final r = asMap(await c.getJson('/import/staged${q.isEmpty ? '' : '?$q'}'));
    List<T> rows<T>(String k, T Function(Map<String, Object?>) f) => [
      if (r[k] is List)
        for (final e in r[k] as List)
          if (e is Map) f(Map<String, Object?>.from(e)),
    ];
    return Staging(
      pending: (r['pending'] as num?)?.toInt() ?? 0,
      batches: rows('batches', StagedBatch.fromJson),
      works: rows('works', StagedWork.fromJson),
      quotes: rows('quotes', StagedQuote.fromJson),
      total: (r['total'] as num?)?.toInt() ?? 0,
    );
  });

  @override
  Future<ApprovalOutcome> approve(
    StagedSelector selection, {
    void Function(int done, int total)? onProgress,
  }) async {
    final started = await serverCall(
      _controller,
      (c) => c.postJson('/import/staged/approve', selection.toJson()),
    );
    final id = (asMap(asMap(started)['job'])['id'] as num).toInt();
    final (job, result) = await _await(id, onProgress);
    final body = _body(result);
    final counts = job['counts'] is Map
        ? Map<String, Object?>.from(job['counts'] as Map)
        : <String, Object?>{};
    int n(String k) =>
        (body[k] as num?)?.toInt() ?? (counts[k] as num?)?.toInt() ?? 0;
    if ((job['state'] as String?) != 'succeeded') {
      return ApprovalOutcome(
        ok: false,
        message:
            (body['error'] as String?) ??
            (job['error'] as String?) ??
            'The server could not add those quotes.',
      );
    }
    return ApprovalOutcome(
      ok: true,
      added: n('added'),
      skipped: n('skipped'),
      enriched: n('enriched'),
      relinked: n('relinked'),
    );
  }

  @override
  Future<int> discard(StagedSelector selection) =>
      serverCall(_controller, (c) async {
        final r = await c.delete('/import/staged', body: selection.toJson());
        return r is Map ? (r['discarded'] as num?)?.toInt() ?? 0 : 0;
      });

  @override
  Future<int> edit(StagedSelector selection, StagedEdit change) =>
      serverCall(_controller, (c) async {
        final r = asMap(
          await c.postJson('/import/staged/bulk', {
            ...selection.toJson(),
            ...change.toJson(),
          }),
        );
        return (r['updated'] as num?)?.toInt() ?? 0;
      });

  @override
  Future<void> move(
    StagedSelector selection, {
    WorkChoice? onto,
    int? mergeInto,
  }) => serverCall(_controller, (c) async {
    await c.postJson('/import/staged/bulk', {
      ...selection.toJson(),
      'retarget': onto != null
          ? {'kind': onto.kind, 'id': onto.id}
          : {'staged_work_id': mergeInto},
    });
  });

  @override
  Future<List<WorkChoice>> destinations() => serverCall(_controller, (c) async {
    final out = <WorkChoice>[];
    final books = asMap(await c.getJson('/books'))['books'];
    if (books is List) {
      for (final b in books) {
        if (b is Map) {
          out.add(
            WorkChoice(
              'book',
              (b['id'] as num).toInt(),
              '${b['title'] ?? ''}',
              (b['published_year'] as num?)?.toInt() ?? 0,
              '${b['author'] ?? ''}',
            ),
          );
        }
      }
    }
    final movies = asMap(await c.getJson('/movies'))['movies'];
    if (movies is List) {
      for (final m in movies) {
        if (m is Map) {
          out.add(
            WorkChoice(
              'movie',
              (m['id'] as num).toInt(),
              '${m['title'] ?? ''}',
              (m['release_year'] as num?)?.toInt() ??
                  (m['year'] as num?)?.toInt() ??
                  0,
              '${m['director'] ?? ''}',
            ),
          );
        }
      }
    }
    return out;
  });
}
