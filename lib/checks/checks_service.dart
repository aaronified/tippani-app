import '../api/server_call.dart';
import '../app_controller.dart';
import '../l10n/l10n.dart';

/// What a press on "accept" or "ignore" did, as the server counts it.
class ChangeResult {
  const ChangeResult({
    this.applied = 0,
    this.stale = 0,
    this.skipped = 0,
    this.skippedEdited = 0,
    this.duplicates = 0,
    this.ignored = 0,
  });

  /// Quotes rewritten.
  final int applied;

  /// Left alone because the quote changed since the list was read.
  final int stale;

  /// Belonged to the other group.
  final int skipped;
  final int skippedEdited;

  /// The corrected words already exist under another quote.
  final int duplicates;
  final int ignored;

  factory ChangeResult.fromJson(Object? j) {
    if (j is! Map) return const ChangeResult();
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ChangeResult(
      applied: n('applied'),
      stale: n('stale'),
      skipped: n('skipped'),
      skippedEdited: n('skipped_edited'),
      duplicates: n('duplicates'),
      ignored: n('ignored'),
    );
  }

  /// The sentence for a snackbar, or '' when nothing happened.
  String get words {
    final parts = <String>[
      if (applied > 0)
        tx('app.checks_service.updated', {
          'quotes': countWords('quote', applied),
        }),
      if (skippedEdited > 0)
        tx('app.checks_service.edited_left_alone', {'n': skippedEdited}),
      if (stale > 0) trn('app.checks_service.stale', stale),
      if (skipped > 0) trn('app.checks_service.other_group', skipped),
      if (duplicates > 0) trn('app.checks_service.duplicated', duplicates),
    ];
    return parts.join(' · ');
  }
}

// ------------------------------------------------------------------ stray marks

/// One stray mark a rule found in one field of one quote.
class CleanupFinding {
  const CleanupFinding({
    required this.rule,
    required this.field,
    required this.snippet,
    required this.afterSnippet,
    required this.count,
    required this.hash,
    required this.ignored,
  });

  final String rule;
  final String field;

  /// The text around the match, with the match marked in guillemets.
  final String snippet;

  /// The same text after the fix, with the replacement marked; empty when this build cannot fix the rule.
  final String afterSnippet;
  final int count;
  final String hash;
  final bool ignored;

  bool get fixable => afterSnippet.isNotEmpty;

  factory CleanupFinding.fromJson(Map<String, Object?> j) => CleanupFinding(
    rule: (j['rule'] as String?) ?? '',
    field: (j['field'] as String?) ?? '',
    snippet: (j['snippet'] as String?) ?? '',
    afterSnippet: (j['after_snippet'] as String?) ?? '',
    count: (j['count'] as num?)?.toInt() ?? 1,
    hash: (j['match_hash'] as String?) ?? '',
    ignored: j['ignored'] == true,
  );
}

/// A quote with stray marks, from a book ('book'), a film or show ('screen') or on its own ('quote').
class CleanupItem {
  const CleanupItem({
    required this.kind,
    required this.id,
    required this.workId,
    required this.workTitle,
    required this.findings,
  });

  final String kind;
  final int id;
  final int workId;
  final String workTitle;
  final List<CleanupFinding> findings;

  factory CleanupItem.fromJson(Map<String, Object?> j) => CleanupItem(
    kind: (j['kind'] as String?) ?? 'quote',
    id: (j['id'] as num).toInt(),
    workId: (j['work_id'] as num?)?.toInt() ?? 0,
    workTitle: (j['work_title'] as String?) ?? '',
    findings: [
      if (j['findings'] is List)
        for (final f in j['findings'] as List)
          if (f is Map) CleanupFinding.fromJson(Map<String, Object?>.from(f)),
    ],
  );
}

/// The address of one finding, which is what an accept or an ignore sends.
class CleanupTarget {
  const CleanupTarget(this.item, this.finding);
  final CleanupItem item;
  final CleanupFinding finding;

  String get key =>
      '${item.kind}:${item.id}:${finding.field}:${finding.rule}:${finding.hash}';

  Map<String, Object?> toJson() => {
    'kind': item.kind,
    'id': item.id,
    'field': finding.field,
    'rule': finding.rule,
    'match_hash': finding.hash,
  };
}

class CleanupScan {
  const CleanupScan({
    required this.rules,
    required this.items,
    required this.open,
    required this.ignored,
    required this.truncated,
  });

  /// Every rule the server checks, in its order.
  final List<String> rules;
  final List<CleanupItem> items;
  final int open;
  final int ignored;

  /// The server stopped listing before the end (a very large library); answering these and looking again shows
  /// the rest.
  final bool truncated;
}

/// The reader's words for each rule, as the web's own page gives them.
final cleanupRuleWords = <String, (String, String)>{
  'invisible': (
    tx('cleanup.rule.invisible.label'),
    tx('app.checks_service.an_invisible_space_or_hyphen_from'),
  ),
  'edge-space': (
    tx('cleanup.rule.edge-space.label'),
    tx('cleanup.rule.edge-space.body'),
  ),
  'double-space': (
    tx('cleanup.rule.double-space.label'),
    tx('app.checks_service.two_or_more_spaces_in_a'),
  ),
  'space-before-punctuation': (
    tx('cleanup.rule.space-before-punctuation.label'),
    tx('cleanup.rule.space-before-punctuation.body'),
  ),
  'reference-mark': (
    tx('cleanup.rule.reference-mark.label'),
    tx('app.checks_service.a_leftover_reference_mark_a_superscript'),
  ),
  'pronunciation': (
    tx('cleanup.rule.pronunciation.label'),
    tx('cleanup.rule.pronunciation.body'),
  ),
  'hyphen-break': (
    tx('cleanup.rule.hyphen-break.label'),
    tx('cleanup.rule.hyphen-break.body'),
  ),
  'repeated-punctuation': (
    tx('cleanup.rule.repeated-punctuation.label'),
    tx('cleanup.rule.repeated-punctuation.body'),
  ),
};

// ------------------------------------------------------------------ corrections

/// One quote whose words differ from the file the server holds for its work, with the file's version.
class Correction {
  const Correction({
    required this.kind,
    required this.id,
    required this.workId,
    required this.workTitle,
    required this.quote,
    required this.proposed,
    required this.from,
    required this.to,
    required this.bucket,
    required this.edited,
  });

  final String kind;
  final int id;
  final int workId;
  final String workTitle;
  final String quote;
  final String proposed;

  /// The differing stretch in the quote, and in the file, for marking.
  final String from;
  final String to;
  final String bucket;

  /// You changed this quote yourself after it was imported.
  final bool edited;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'quote': quote,
    'proposed': proposed,
  };

  factory Correction.fromJson(Map<String, Object?> j) => Correction(
    kind: (j['kind'] as String?) ?? 'book',
    id: (j['id'] as num).toInt(),
    workId: (j['work_id'] as num?)?.toInt() ?? 0,
    workTitle: (j['work_title'] as String?) ?? '',
    quote: (j['quote'] as String?) ?? '',
    proposed: (j['proposed'] as String?) ?? '',
    from: (j['from'] as String?) ?? '',
    to: (j['to'] as String?) ?? '',
    bucket: (j['bucket'] as String?) ?? '',
    edited: j['edited'] == true,
  );
}

/// A work with so many differing quotes that its file is probably the wrong one.
class WrongFile {
  const WrongFile(
    this.kind,
    this.workId,
    this.workTitle,
    this.differing,
    this.total,
  );
  final String kind;
  final int workId;
  final String workTitle;
  final int differing;
  final int total;
}

class CorrectionsScan {
  const CorrectionsScan({required this.proposals, required this.wrongFile});

  static const empty = CorrectionsScan(proposals: [], wrongFile: []);

  final List<Correction> proposals;
  final List<WrongFile> wrongFile;
}

/// The buckets of corrections, in the server's order, with the web's words.
final correctionBuckets = <String, (String, String)>{
  'spacing': (
    tx('corrections.bucket.spacing.title'),
    tx('corrections.bucket.spacing.note'),
  ),
  'punctuation': (
    tx('corrections.bucket.punctuation.title'),
    tx('corrections.bucket.punctuation.note'),
  ),
  'capitalisation': ('Capitalisation', 'The same words in a different case.'),
  'accents': (
    tx('corrections.bucket.accents.title'),
    tx('corrections.bucket.accents.note'),
  ),
  'marks': (
    tx('corrections.bucket.marks.title'),
    'Accents, case and punctuation together; the words are the same.',
  ),
  'extend': (
    tx('corrections.bucket.extend.title'),
    tx('corrections.bucket.extend.note'),
  ),
  'trim': (
    tx('corrections.bucket.trim.title'),
    tx('corrections.bucket.trim.note'),
  ),
  'one-word': (
    tx('corrections.bucket.one-word.title'),
    tx('corrections.bucket.one-word.note'),
  ),
  'few-words': (
    tx('corrections.bucket.few-words.title'),
    tx('corrections.bucket.few-words.note'),
  ),
  'wording': (
    tx('corrections.bucket.wording.title'),
    tx('corrections.bucket.wording.note'),
  ),
};

// ------------------------------------------------------------------ times and places

/// A time (film, show) or a place (book) the server's copy of the work's file proposes for one quote.
class LocatorProposal {
  const LocatorProposal({
    required this.kind,
    required this.id,
    required this.quote,
    required this.workId,
    required this.workTitle,
    required this.season,
    required this.episode,
    required this.current,
    required this.currentEnd,
    required this.proposed,
    required this.proposedEnd,
    required this.evidence,
    required this.bucket,
    required this.currentChapter,
    required this.proposedChapter,
  });

  /// 'dialogue' (a film or show line) or 'annotation' (a book highlight).
  final String kind;
  final int id;
  final String quote;
  final int workId;
  final String workTitle;
  final int season, episode;
  final String current, currentEnd, proposed, proposedEnd;

  /// The file's own words for the matched stretch.
  final String evidence;

  /// 'exact' (found once, word for word) or 'review' (a near match).
  final String bucket;
  final String currentChapter, proposedChapter;

  bool get isBook => kind == 'annotation';

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'proposed': proposed,
    'proposed_end': proposedEnd,
    'current': current,
    'current_end': currentEnd,
    if (currentChapter.isNotEmpty) 'current_chapter': currentChapter,
    if (proposedChapter.isNotEmpty) 'proposed_chapter': proposedChapter,
  };

  factory LocatorProposal.fromJson(Map<String, Object?> j) {
    String s(String k) => (j[k] as String?) ?? '';
    return LocatorProposal(
      kind: s('kind').isEmpty ? 'dialogue' : s('kind'),
      id: (j['id'] as num).toInt(),
      quote: s('quote'),
      workId: (j['work_id'] as num?)?.toInt() ?? 0,
      workTitle: s('work_title'),
      season: (j['season'] as num?)?.toInt() ?? 0,
      episode: (j['episode'] as num?)?.toInt() ?? 0,
      current: s('current'),
      currentEnd: s('current_end'),
      proposed: s('proposed'),
      proposedEnd: s('proposed_end'),
      evidence: s('evidence'),
      bucket: s('bucket'),
      currentChapter: s('current_chapter'),
      proposedChapter: s('proposed_chapter'),
    );
  }
}

/// What the three checks hold, for the badges.
class CheckCounts {
  const CheckCounts({
    this.strayMarks = 0,
    this.corrections = 0,
    this.locators = 0,
  });

  final int strayMarks;
  final int corrections;
  final int locators;

  int get total => strayMarks + corrections + locators;
}

/// The server's checks on the library: stray marks in the words, corrections from a work's own file, and times and
/// places from it. An interface so a test can stand in for the server.
abstract class ChecksService {
  bool get available;

  Future<CleanupScan> cleanup({bool ignored = false});
  Future<ChangeResult> cleanupAccept(List<CleanupTarget> targets);
  Future<ChangeResult> cleanupIgnore(
    List<CleanupTarget> targets, {
    required bool ignore,
  });

  Future<CorrectionsScan> corrections();
  Future<ChangeResult> correctionsAccept(
    String bucket,
    List<Correction> items, {
    bool bulk = false,
  });
  Future<ChangeResult> correctionsIgnore(List<Correction> items);

  Future<List<LocatorProposal>> locators();
  Future<ChangeResult> locatorsAccept(
    String bucket,
    List<LocatorProposal> items,
  );
  Future<ChangeResult> locatorsIgnore(List<LocatorProposal> items);

  /// How many of each are waiting.
  Future<CheckCounts> counts();
}

class PairedChecksService implements ChecksService {
  PairedChecksService(this._controller);
  final AppController _controller;

  @override
  bool get available => _controller.paired;

  static List<Map<String, Object?>> _rows(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) Map<String, Object?>.from(e),
  ];

  @override
  Future<CleanupScan> cleanup({bool ignored = false}) =>
      serverCall(_controller, (c) async {
        final r = asMap(
          await c.getJson('/cleanup?bucket=${ignored ? 'ignored' : 'open'}'),
        );
        final counts = r['counts'] is Map
            ? Map<String, Object?>.from(r['counts'] as Map)
            : <String, Object?>{};
        return CleanupScan(
          rules: [
            if (r['rules'] is List)
              for (final x in r['rules'] as List) '$x',
          ],
          items: [for (final j in _rows(r['items'])) CleanupItem.fromJson(j)],
          open: (counts['open'] as num?)?.toInt() ?? 0,
          ignored: (counts['ignored'] as num?)?.toInt() ?? 0,
          truncated: r['truncated'] == true,
        );
      });

  Future<ChangeResult> _post(String path, Map<String, Object?> body) =>
      serverCall(
        _controller,
        (c) async => ChangeResult.fromJson(await c.postJson(path, body)),
      );

  @override
  Future<ChangeResult> cleanupAccept(List<CleanupTarget> targets) =>
      _post('/cleanup/accept', {
        'items': [for (final t in targets) t.toJson()],
      });

  @override
  Future<ChangeResult> cleanupIgnore(
    List<CleanupTarget> targets, {
    required bool ignore,
  }) async {
    await _post(ignore ? '/cleanup/ignore' : '/cleanup/unignore', {
      'items': [for (final t in targets) t.toJson()],
    });
    return ChangeResult(ignored: targets.length);
  }

  @override
  Future<CorrectionsScan> corrections() => serverCall(_controller, (c) async {
    final r = asMap(await c.getJson('/corrections'));
    return CorrectionsScan(
      proposals: [
        for (final j in _rows(r['proposals'])) Correction.fromJson(j),
      ],
      wrongFile: [
        for (final j in _rows(r['wrong_file']))
          WrongFile(
            (j['kind'] as String?) ?? '',
            (j['work_id'] as num?)?.toInt() ?? 0,
            (j['work_title'] as String?) ?? '',
            (j['differing'] as num?)?.toInt() ?? 0,
            (j['total'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  });

  @override
  Future<ChangeResult> correctionsAccept(
    String bucket,
    List<Correction> items, {
    bool bulk = false,
  }) => _post('/corrections/accept', {
    'bucket': bucket,
    'bulk': bulk,
    'items': [for (final i in items) i.toJson()],
  });

  @override
  Future<ChangeResult> correctionsIgnore(List<Correction> items) async {
    await _post('/corrections/ignore', {
      'items': [for (final i in items) i.toJson()],
    });
    return ChangeResult(ignored: items.length);
  }

  @override
  Future<List<LocatorProposal>> locators() => serverCall(_controller, (
    c,
  ) async {
    final r = asMap(await c.getJson('/locators/proposals'));
    return [for (final j in _rows(r['proposals'])) LocatorProposal.fromJson(j)];
  });

  @override
  Future<ChangeResult> locatorsAccept(
    String bucket,
    List<LocatorProposal> items,
  ) => _post('/locators/accept', {
    'bucket': bucket,
    'items': [for (final i in items) i.toJson()],
  });

  @override
  Future<ChangeResult> locatorsIgnore(List<LocatorProposal> items) async {
    await _post('/locators/ignore', {
      'items': [for (final i in items) i.toJson()],
    });
    return ChangeResult(ignored: items.length);
  }

  @override
  Future<CheckCounts> counts() => serverCall(_controller, (c) async {
    final cleanup = asMap(await c.getJson('/cleanup?bucket=open'));
    final corr = asMap(await c.getJson('/corrections'));
    final loc = asMap(await c.getJson('/locators/proposals'));
    final cc = cleanup['counts'] is Map ? cleanup['counts'] as Map : const {};
    final lc = loc['counts'] is Map ? loc['counts'] as Map : const {};
    return CheckCounts(
      strayMarks: (cc['open'] as num?)?.toInt() ?? 0,
      corrections: corr['proposals'] is List
          ? (corr['proposals'] as List).length
          : 0,
      locators:
          ((lc['exact'] as num?)?.toInt() ?? 0) +
          ((lc['review'] as num?)?.toInt() ?? 0),
    );
  });
}
