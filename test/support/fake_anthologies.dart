import 'dart:typed_data';

import 'package:tippani/anthologies/anthologies.dart';

/// An in-memory stand-in for the server's anthologies, remembering what the screens asked in [calls].
class FakeAnthologies implements AnthologyService {
  FakeAnthologies({this.available = true});

  @override
  bool available;

  @override
  bool hasPoster = true;

  /// When set, every call throws it.
  AnthologyException? fail;

  int _next = 1;
  int _nextSection = 1;
  final _rows = <int, Map<String, Object?>>{};
  final _entries = <int, List<AnthologyEntry>>{};
  final _sections = <int, List<AnthologySection>>{};
  final _removed = <int, List<RemovedPassage>>{};
  final calls = <String>[];

  /// What a fill finds: the quotes it adds, by rule.
  final fills = <String, List<AnthologyEntry>>{};

  /// What the fill chooser offers.
  FillVocabulary vocab = const FillVocabulary(
    tags: ['stoicism'],
    authors: ['Seneca'],
    books: [(key: '4', name: 'Walden')],
  );

  /// A quote the screens can add, as the detail will show it.
  void put(int id, AnthologyEntry e) {
    final list = _entries[id]!;
    final last = [
      ...list.map((x) => x.position),
      ..._sections[id]!.map((x) => x.position),
    ].fold<double>(0, (a, b) => a > b ? a : b);
    list.add(_withPosition(e, e.position == 0 ? last + 1 : e.position));
  }

  AnthologyEntry _withPosition(AnthologyEntry e, double p, {String? note}) =>
      AnthologyEntry(
        kind: e.kind,
        itemId: e.itemId,
        quote: e.quote,
        note: note ?? e.note,
        source: e.source,
        credit: e.credit,
        color: e.color,
        language: e.language,
        locator: e.locator,
        position: p,
        favorite: e.favorite,
        workId: e.workId,
        personName: e.personName,
        characterName: e.characterName,
        date: e.date,
      );

  void _check() {
    final f = fail;
    if (f != null) throw f;
  }

  Anthology _row(int id) => Anthology(
    id: id,
    title: _rows[id]!['title']! as String,
    intro: _rows[id]!['intro']! as String,
    entries: _entries[id]!.length,
    raw: Map.of(_rows[id]!),
  );

  Anthology seed(String title, {String intro = ''}) {
    final id = _next++;
    _rows[id] = {
      'id': id,
      'title': title,
      'intro': intro,
      'show_locator': true,
      'group_by': '',
      'cover_path': '',
      'epigraph': '',
      'dedication': '',
    };
    _entries[id] = [];
    _sections[id] = [];
    _removed[id] = [];
    return _row(id);
  }

  /// All the slots of [id] in order, as `kind/itemId` (a heading as `section/id`).
  List<String> order(int id) {
    final d = AnthologyDetail(_row(id), _entries[id]!, _sections[id]!);
    return [for (final s in d.slots) '${s.ref.kind}/${s.ref.itemId}'];
  }

  Map<String, Object?> rowOf(int id) => _rows[id]!;

  @override
  Future<List<Anthology>> list() async {
    _check();
    return [for (final id in _rows.keys) _row(id)];
  }

  @override
  Future<AnthologyDetail> get(int id) async {
    _check();
    if (!_rows.containsKey(id)) {
      throw const AnthologyException('The server could not do that.');
    }
    return AnthologyDetail(
      _row(id),
      List.of(_entries[id]!),
      List.of(_sections[id]!),
    );
  }

  @override
  Future<Anthology> create(String title, String intro) async {
    _check();
    calls.add('create $title');
    return seed(title, intro: intro);
  }

  @override
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  }) async {
    _check();
    calls.add('edit ${a.id} $title');
    _rows[a.id]!['title'] = title;
    _rows[a.id]!['intro'] = intro;
  }

  @override
  Future<void> setSwitches(Anthology a, Map<String, bool> switches) async {
    _check();
    calls.add('switches ${a.id} $switches');
    _rows[a.id]!.addAll(switches);
  }

  @override
  Future<void> delete(int id) async {
    _check();
    calls.add('delete $id');
    _rows.remove(id);
    _entries.remove(id);
  }

  @override
  Future<bool> add(int id, String kind, int itemId) async {
    _check();
    calls.add('add $id $kind $itemId');
    final list = _entries[id]!;
    if (list.any((e) => e.kind == kind && e.itemId == itemId)) return false;
    put(
      id,
      AnthologyEntry(
        kind: kind,
        itemId: itemId,
        quote: 'quote $itemId',
        note: '',
        source: '',
        credit: '',
        color: 'yellow',
        language: '',
        locator: '',
      ),
    );
    return true;
  }

  @override
  Future<void> removeEntry(int id, String kind, int itemId) async {
    _check();
    calls.add('remove $id $kind $itemId');
    final gone = _entries[id]!.where(
      (e) => e.kind == kind && e.itemId == itemId,
    );
    for (final e in gone) {
      _removed[id]!.add(
        RemovedPassage(
          kind: e.kind,
          itemId: e.itemId,
          quote: e.quote,
          source: e.source,
          credit: e.credit,
          note: e.note,
        ),
      );
    }
    _entries[id]!.removeWhere((e) => e.kind == kind && e.itemId == itemId);
  }

  @override
  Future<void> setNote(int id, String kind, int itemId, String note) async {
    _check();
    calls.add('note $id $kind/$itemId $note');
    final list = _entries[id]!;
    final i = list.indexWhere((e) => e.kind == kind && e.itemId == itemId);
    list[i] = _withPosition(list[i], list[i].position, note: note);
  }

  @override
  Future<void> move(
    int id,
    String kind,
    int itemId, {
    ({String kind, int itemId})? after,
  }) async {
    _check();
    calls.add('move $id $kind/$itemId after ${after?.kind}/${after?.itemId}');
    final detail = AnthologyDetail(_row(id), _entries[id]!, _sections[id]!);
    final slots = detail.slots;
    final all = [for (final s in slots) s.ref];
    final from = all.indexWhere((r) => r.kind == kind && r.itemId == itemId);
    // a heading takes the passages under it along
    var count = 1;
    if (kind == 'section') {
      while (from + count < all.length && all[from + count].kind != 'section') {
        count++;
      }
    }
    final moving = all.sublist(from, from + count);
    all.removeRange(from, from + count);
    final at = after == null
        ? 0
        : all.indexWhere(
                (r) => r.kind == after.kind && r.itemId == after.itemId,
              ) +
              1;
    all.insertAll(at, moving);
    // renumber 1, 2, 3...
    for (var i = 0; i < all.length; i++) {
      final r = all[i];
      if (r.kind == 'section') {
        final j = _sections[id]!.indexWhere((s) => s.id == r.itemId);
        final s = _sections[id]![j];
        _sections[id]![j] = AnthologySection(
          id: s.id,
          position: i + 1.0,
          title: s.title,
          prose: s.prose,
        );
      } else {
        final j = _entries[id]!.indexWhere(
          (e) => e.kind == r.kind && e.itemId == r.itemId,
        );
        _entries[id]![j] = _withPosition(_entries[id]![j], i + 1.0);
      }
    }
  }

  @override
  Future<AnthologySection> addSection(
    int id,
    String title,
    String prose, {
    ({String kind, int itemId})? after,
  }) async {
    _check();
    calls.add('section+ $id $title');
    final s = AnthologySection(
      id: _nextSection++,
      position: 1000000,
      title: title,
      prose: prose,
    );
    _sections[id]!.add(s);
    if (after != null) {
      await move(id, 'section', s.id, after: after);
      calls.removeLast();
    } else {
      // the end: renumber so it is last
      await move(
        id,
        'section',
        s.id,
        after: order(id)
            .where((o) => o != 'section/${s.id}')
            .map(
              (o) =>
                  (kind: o.split('/')[0], itemId: int.parse(o.split('/')[1])),
            )
            .lastOrNull,
      );
      calls.removeLast();
    }
    return _sections[id]!.firstWhere((x) => x.id == s.id);
  }

  @override
  Future<void> editSection(
    int id,
    int sectionId,
    String title,
    String prose,
  ) async {
    _check();
    calls.add('section~ $id $sectionId $title');
    final j = _sections[id]!.indexWhere((s) => s.id == sectionId);
    final s = _sections[id]![j];
    _sections[id]![j] = AnthologySection(
      id: s.id,
      position: s.position,
      title: title,
      prose: prose,
    );
  }

  @override
  Future<void> deleteSection(int id, int sectionId) async {
    _check();
    calls.add('section- $id $sectionId');
    _sections[id]!.removeWhere((s) => s.id == sectionId);
  }

  @override
  Future<void> setGrouping(int id, String groupBy) async {
    _check();
    calls.add('group $id $groupBy');
    _rows[id]!['group_by'] = groupBy;
  }

  @override
  Future<void> setFront(
    int id,
    String epigraph,
    String dedication, {
    String? description,
  }) async {
    _check();
    calls.add('front $id');
    _rows[id]!['epigraph'] = epigraph;
    _rows[id]!['dedication'] = dedication;
    if (description != null) _rows[id]!['description'] = description;
  }

  @override
  Future<String> setPoster(int id, Uint8List bytes, String fileName) async {
    _check();
    calls.add('poster $id ${bytes.length}');
    _rows[id]!['poster_path'] = 'fedcba9876543210.png';
    return 'fedcba9876543210.png';
  }

  @override
  Future<void> removePoster(int id) async {
    _check();
    calls.add('poster- $id');
    _rows[id]!['poster_path'] = '';
  }

  @override
  Future<String> setCover(int id, Uint8List bytes, String fileName) async {
    _check();
    calls.add('cover $id ${bytes.length}');
    _rows[id]!['cover_path'] = '0123456789abcdef.png';
    return '0123456789abcdef.png';
  }

  @override
  Future<void> removeCover(int id) async {
    _check();
    calls.add('cover- $id');
    _rows[id]!['cover_path'] = '';
  }

  @override
  Future<FillResult> fill(
    int id,
    String rule, {
    bool preview = false,
    bool auto = false,
  }) async {
    _check();
    calls.add('fill $id $rule preview=$preview auto=$auto');
    final found = fills[rule] ?? const [];
    var added = 0;
    if (!preview) {
      for (final e in found) {
        if (!_entries[id]!.any(
          (x) => x.kind == e.kind && x.itemId == e.itemId,
        )) {
          put(id, e);
          added++;
        }
      }
      _rows[id]!['rule'] = rule;
      _rows[id]!['rule_auto'] = auto;
    }
    return FillResult(
      added: added,
      matched: found.length,
      skipped: preview ? 0 : found.length - added,
      capped: false,
      items: preview ? found : const [],
    );
  }

  @override
  Future<FillVocabulary> vocabulary() async {
    _check();
    return vocab;
  }

  @override
  Future<List<RemovedPassage>> removed(int id) async {
    _check();
    return List.of(_removed[id]!);
  }

  @override
  Future<void> restore(int id, String kind, int itemId) async {
    _check();
    calls.add('restore $id $kind/$itemId');
    final r = _removed[id]!.firstWhere(
      (x) => x.kind == kind && x.itemId == itemId,
    );
    _removed[id]!.remove(r);
    put(
      id,
      AnthologyEntry(
        kind: r.kind,
        itemId: r.itemId,
        quote: r.quote,
        note: r.note,
        source: r.source,
        credit: r.credit,
        color: 'yellow',
        language: '',
        locator: '',
      ),
    );
  }

  @override
  Future<ExportedFile> export(int id, {bool epub = false}) async {
    _check();
    calls.add('export $id ${epub ? 'epub' : 'md'}');
    return ExportedFile(
      '${_rows[id]!['title']}.${epub ? 'epub' : 'md'}',
      Uint8List.fromList([1, 2, 3]),
    );
  }
}
