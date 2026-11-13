import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/offline_cache.dart';
import '../l10n/l10n.dart';
import '../settings/settings_store.dart';
import 'anthologies.dart';

/// Finds what the phone already knows about a quote the server calls [itemId] in its [kind] table, so a passage
/// added with no server shows its words at once. Null when the phone does not hold it.
typedef PassageLookup = Future<Map<String, Object?>?> Function(
  String kind,
  int itemId,
);

/// Anthologies that work with no server (ADR-0022). Every read is the server's last answer when the server
/// cannot be reached (see [OfflineCache]), and every change the reader makes while it cannot be reached is
/// applied to that kept copy at once and queued, then sent in order the next time the server answers.
///
/// A change the server then refuses (the anthology was deleted somewhere else, say) is dropped and counted in
/// [problems] rather than blocking the ones behind it. An anthology made with no server has a negative id until
/// it is sent; the changes queued against it follow it to its real id.
///
/// ONLY WHAT CAN BE SAID IN A QUEUE IS QUEUED. A cover picture, a fill and an export need the server and say so.
class OfflineAnthologies implements AnthologyService {
  OfflineAnthologies(
    this._inner,
    this._cache,
    this._store, {
    this.lookup,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    pending.value = _load().ops.length;
    // What waits was made under one pairing: when the cache is cleared (unpaired, or the server forgotten) it goes
    // too, so a queued change is never sent to another account or another server.
    _cache.whenCleared.add(() async {
      await _store.remove(_key);
      pending.value = 0;
      problems.value = const [];
    });
  }

  final AnthologyService _inner;
  final OfflineCache _cache;
  final SettingsStore _store;
  final PassageLookup? lookup;
  final DateTime Function() _clock;

  static const _key = 'outbox.anthologies';

  /// How many changes wait for the server.
  final ValueNotifier<int> pending = ValueNotifier(0);

  /// What the server refused when the queue was sent, in its words; the reader can clear it.
  final ValueNotifier<List<String>> problems = ValueNotifier(const []);

  bool _flushing = false;

  @override
  bool get available => true;

  // ── the queue ──────────────────────────────────────────────────────────────────────────────────────

  _Queue _load() {
    final raw = _store.read(_key);
    if (raw == null || raw.isEmpty) return _Queue();
    try {
      return _Queue.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return _Queue();
    }
  }

  Future<void> _save(_Queue q) async {
    pending.value = q.ops.length;
    if (q.ops.isEmpty && q.map.isEmpty && q.next == -1) {
      await _store.remove(_key);
    } else {
      await _store.write(_key, jsonEncode(q.toJson()));
    }
  }

  /// Sends what is waiting, in order, and returns how many changes went. Stops at the first one the server
  /// cannot be reached for; drops one the server refuses.
  ///
  /// THE QUEUE IS READ AGAIN AROUND EVERY SEND. A change the reader makes while a request is out is added to what
  /// is stored, and a copy loaded at the start and saved after each send would write over it (and hand a
  /// temporary id out twice). Only the op that was sent is taken off, and the ids the server gave are added.
  Future<int> flush() async {
    if (_flushing) return 0;
    if (_load().ops.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    final touched = <int>{};
    final refused = <String>[];
    try {
      while (true) {
        final q = _load();
        if (q.ops.isEmpty) break;
        final op = q.ops.first;
        final gained = <String, int>{};
        try {
          await _replay(op, q, touched, gained);
        } on AnthologyException catch (e) {
          if (e.unreachable) break;
          refused.add(e.message);
        }
        final now = _load();
        now.map.addAll(gained);
        if (now.ops.isNotEmpty && jsonEncode(now.ops.first) == jsonEncode(op)) {
          now.ops.removeAt(0);
        }
        await _save(now);
        sent++;
      }
      if (sent > 0) await _refresh(touched);
    } finally {
      _flushing = false;
    }
    if (refused.isNotEmpty) {
      problems.value = [...problems.value, ...refused];
    }
    return sent;
  }

  /// Reads the lists the server holds now, so what was kept on the phone is the server's word again.
  Future<void> _refresh(Set<int> touched) async {
    try {
      await _inner.list();
      for (final id in touched) {
        if (id > 0) await _inner.get(id);
      }
    } on AnthologyException {
      // the kept copy stands until the next time
    }
  }

  int _real(_Queue q, int id) => id < 0 ? (q.map['a:$id'] ?? id) : id;
  int _realSection(_Queue q, int id) => id < 0 ? (q.map['s:$id'] ?? id) : id;

  Future<void> _replay(
    Map<String, Object?> op,
    _Queue q,
    Set<int> touched,
    Map<String, int> gained,
  ) async {
    final id = _real(q, (op['id'] as num?)?.toInt() ?? 0);
    if (op['op'] != 'create' && id < 0) {
      // made here and never sent (its creation was refused): there is nothing to change
      return;
    }
    touched.add(id);
    final kind = op['kind'] as String? ?? '';
    final item = (op['item'] as num?)?.toInt() ?? 0;
    switch (op['op']) {
      case 'create':
        final made = await _inner.create(
          op['title'] as String? ?? '',
          op['intro'] as String? ?? '',
        );
        gained['a:${op['tmp']}'] = made.id;
        touched.add(made.id);
        await _forget('/anthologies/${op['tmp']}');
      case 'edit':
        final fresh = (await _inner.get(id)).anthology;
        await _inner.edit(
          fresh,
          title: op['title'] as String? ?? fresh.title,
          intro: op['intro'] as String? ?? fresh.intro,
        );
      case 'switches':
        final fresh = (await _inner.get(id)).anthology;
        await _inner.setSwitches(fresh, {
          for (final e in (op['switches'] as Map).entries)
            e.key as String: e.value == true,
        });
      case 'delete':
        await _inner.delete(id);
      case 'add':
        await _inner.add(id, kind, item);
      case 'remove':
        await _inner.removeEntry(id, kind, item);
      case 'note':
        await _inner.setNote(id, kind, item, op['note'] as String? ?? '');
      case 'move':
        final after = op['after'];
        await _inner.move(
          id,
          kind,
          kind == 'section' ? _realSection(q, item) : item,
          after: after is Map
              ? (
                  kind: after['kind'] as String,
                  itemId: after['kind'] == 'section'
                      ? _realSection(q, (after['item'] as num).toInt())
                      : (after['item'] as num).toInt(),
                )
              : null,
        );
      case 'section':
        final after = op['after'];
        final made = await _inner.addSection(
          id,
          op['title'] as String? ?? '',
          op['prose'] as String? ?? '',
          after: after is Map
              ? (
                  kind: after['kind'] as String,
                  itemId: after['kind'] == 'section'
                      ? _realSection(q, (after['item'] as num).toInt())
                      : (after['item'] as num).toInt(),
                )
              : null,
        );
        gained['s:${op['tmp']}'] = made.id;
      case 'editSection':
        await _inner.editSection(
          id,
          _realSection(q, (op['sid'] as num).toInt()),
          op['title'] as String? ?? '',
          op['prose'] as String? ?? '',
        );
      case 'deleteSection':
        await _inner.deleteSection(
          id,
          _realSection(q, (op['sid'] as num).toInt()),
        );
      case 'group':
        await _inner.setGrouping(id, op['by'] as String? ?? '');
      case 'front':
        await _inner.setFront(
          id,
          op['epigraph'] as String? ?? '',
          op['dedication'] as String? ?? '',
          description: op['description'] as String?,
        );
      case 'restore':
        await _inner.restore(id, kind, item);
      case 'cover':
        await _inner.setCover(
          id,
          base64Decode(op['bytes'] as String? ?? ''),
          op['name'] as String? ?? 'cover.jpg',
        );
      case 'removeCover':
        await _inner.removeCover(id);
      case 'poster':
        await _inner.setPoster(
          id,
          base64Decode(op['bytes'] as String? ?? ''),
          op['name'] as String? ?? 'poster.jpg',
        );
      case 'removePoster':
        await _inner.removePoster(id);
      case 'fill':
        await _inner.fill(
          id,
          op['rule'] as String? ?? '',
          auto: op['auto'] == true,
        );
    }
  }

  /// Runs [online] while the server answers; when it cannot be reached, or changes are already waiting ahead
  /// of this one (they go first, in order), applies [local] to the kept copy and queues [op].
  Future<T> _change<T>(
    Map<String, Object?> op, {
    required Future<T> Function() online,
    required Future<T> Function() local,
    int? anthologyId,
  }) async {
    final onlyHere = anthologyId != null && anthologyId < 0;
    if (!onlyHere) {
      if (_load().ops.isNotEmpty) await flush();
      if (_load().ops.isEmpty) {
        try {
          return await online();
        } on AnthologyException catch (e) {
          if (!e.unreachable) rethrow;
        }
      }
    }
    final q = _load()..ops.add(op);
    await _save(q);
    return local();
  }

  // ── what the kept copy says ────────────────────────────────────────────────────────────────────────

  Map<String, Object?>? _read(String key) {
    final kept = _cache.read(key);
    if (kept == null) return null;
    try {
      return Map<String, Object?>.from(jsonDecode(kept.body) as Map);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, Object?> body) =>
      _cache.write(key, jsonEncode(body), at: _cache.read(key)?.at ?? _clock());

  Future<void> _forget(String key) => _cache.remove(key);

  List<Map<String, Object?>> _rows(Map<String, Object?> m, String key) => [
    for (final x in (m[key] as List? ?? const []))
      Map<String, Object?>.from(x as Map),
  ];

  /// Changes the row for [id] in the kept list, and the `anthology` of the kept detail, with [patch].
  Future<void> _patch(int id, Map<String, Object?> patch) async {
    final list = _read('/anthologies');
    if (list != null) {
      final rows = _rows(list, 'anthologies');
      for (final r in rows) {
        if (r['id'] == id) r.addAll(patch);
      }
      await _write('/anthologies', {...list, 'anthologies': rows});
    }
    final d = _read('/anthologies/$id');
    if (d != null) {
      final a = Map<String, Object?>.from(d['anthology'] as Map? ?? {})
        ..addAll(patch);
      await _write('/anthologies/$id', {...d, 'anthology': a});
    }
  }

  Future<void> _editDetail(
    int id,
    void Function(
      List<Map<String, Object?>> entries,
      List<Map<String, Object?>> sections,
    )
    change,
  ) async {
    var d = _read('/anthologies/$id');
    if (d == null) {
      // never opened here: start from the list's row, so a change still has a place to show
      final row = _rows(
        _read('/anthologies') ?? const {},
        'anthologies',
      ).where((r) => r['id'] == id).firstOrNull;
      if (row == null) return;
      d = {'anthology': row, 'entries': <Object?>[], 'sections': <Object?>[]};
    }
    final entries = _rows(d, 'entries');
    final sections = _rows(d, 'sections');
    change(entries, sections);
    await _write('/anthologies/$id', {
      ...d,
      'entries': entries,
      'sections': sections,
    });
    await _patch(id, {'entries': entries.length});
  }

  double _position(
    List<Map<String, Object?>> entries,
    List<Map<String, Object?>> sections,
    String kind,
    int item,
  ) {
    for (final e in entries) {
      if (kind != 'section' && e['kind'] == kind && e['item_id'] == item) {
        return (e['position'] as num?)?.toDouble() ?? 0;
      }
    }
    for (final s in sections) {
      if (kind == 'section' && s['id'] == item) {
        return (s['position'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  double _last(
    List<Map<String, Object?>> entries,
    List<Map<String, Object?>> sections,
  ) {
    var top = 0.0;
    for (final e in [...entries, ...sections]) {
      final p = (e['position'] as num?)?.toDouble() ?? 0;
      if (p > top) top = p;
    }
    return top;
  }

  /// A position that puts something after [after] (null: first), between it and whatever followed.
  double _after(
    List<Map<String, Object?>> entries,
    List<Map<String, Object?>> sections,
    ({String kind, int itemId})? after,
    Object? skip,
  ) {
    final all = [
      for (final e in entries)
        if (e != skip) (e['position'] as num?)?.toDouble() ?? 0,
      for (final s in sections)
        if (s != skip) (s['position'] as num?)?.toDouble() ?? 0,
    ]..sort();
    if (after == null) return all.isEmpty ? 1 : all.first - 1;
    final p = _position(entries, sections, after.kind, after.itemId);
    final next = all.where((x) => x > p).firstOrNull;
    return next == null ? p + 1 : (p + next) / 2;
  }

  // ── ids ────────────────────────────────────────────────────────────────────────────────────────────

  /// The id the server knows an anthology by, for one made here and since sent. A screen opened before that
  /// holds the temporary id for as long as it is open, and must go on working.
  int _id(int id) => id < 0 ? _real(_load(), id) : id;

  int _sid(int id) => id < 0 ? _realSection(_load(), id) : id;

  Anthology _as(Anthology a) {
    final id = _id(a.id);
    return id == a.id ? a : Anthology.fromJson({...a.raw, 'id': id});
  }

  // ── reads ──────────────────────────────────────────────────────────────────────────────────────────

  @override
  Future<List<Anthology>> list() async {
    await flush();
    try {
      return await _inner.list();
    } on AnthologyException catch (e) {
      if (!e.unreachable) rethrow;
      final kept = _read('/anthologies');
      if (kept == null) return const [];
      return [
        for (final r in _rows(kept, 'anthologies')) Anthology.fromJson(r),
      ];
    }
  }

  @override
  Future<AnthologyDetail> get(int id) async {
    id = _id(id);
    if (id > 0) {
      await flush();
      try {
        return await _inner.get(id);
      } on AnthologyException catch (e) {
        if (!e.unreachable) rethrow;
      }
    }
    final kept = _read('/anthologies/$id');
    if (kept == null) {
      throw AnthologyException(
        tx('app.anthologies.not_on_the_phone_yet'),
        unreachable: true,
      );
    }
    return AnthologyDetail(
      Anthology.fromJson(Map<String, Object?>.from(kept['anthology'] as Map)),
      [for (final e in _rows(kept, 'entries')) AnthologyEntry.fromJson(e)],
      [for (final s in _rows(kept, 'sections')) AnthologySection.fromJson(s)],
    );
  }

  @override
  Future<FillVocabulary> vocabulary() => _inner.vocabulary();

  @override
  Future<List<RemovedPassage>> removed(int id) {
    id = _id(id);
    return id < 0 ? Future.value(const []) : _inner.removed(id);
  }

  // ── changes ────────────────────────────────────────────────────────────────────────────────────────

  @override
  Future<Anthology> create(String title, String intro) async {
    if (_load().ops.isNotEmpty) await flush();
    if (_load().ops.isEmpty) {
      try {
        return await _inner.create(title, intro);
      } on AnthologyException catch (e) {
        if (!e.unreachable) rethrow;
      }
    }
    final q = _load();
    final tmp = q.next--;
    q.ops.add({'op': 'create', 'tmp': tmp, 'title': title, 'intro': intro});
    await _save(q);
    final row = <String, Object?>{
      'id': tmp,
      'title': title,
      'intro': intro,
      'entries': 0,
    };
    final list = _read('/anthologies') ?? {'anthologies': <Object?>[]};
    await _write('/anthologies', {
      ...list,
      'anthologies': [row, ..._rows(list, 'anthologies')],
    });
    await _write('/anthologies/$tmp', {
      'anthology': row,
      'entries': <Object?>[],
      'sections': <Object?>[],
    });
    return Anthology.fromJson(row);
  }

  @override
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  }) {
    a = _as(a);
    return _change(
      {'op': 'edit', 'id': a.id, 'title': title, 'intro': intro},
      anthologyId: a.id,
      online: () => _inner.edit(a, title: title, intro: intro),
      local: () => _patch(a.id, {'title': title, 'intro': intro}),
    );
  }

  @override
  Future<void> setSwitches(Anthology a, Map<String, bool> switches) {
    a = _as(a);
    return _change(
      {'op': 'switches', 'id': a.id, 'switches': switches},
      anthologyId: a.id,
      online: () => _inner.setSwitches(a, switches),
      local: () => _patch(a.id, {...switches}),
    );
  }

  @override
  Future<void> delete(int id) {
    id = _id(id);
    return _change(
      {'op': 'delete', 'id': id},
      anthologyId: id,
      online: () => _inner.delete(id),
      local: () async {
        final list = _read('/anthologies');
        if (list != null) {
          await _write('/anthologies', {
            ...list,
            'anthologies': [
              for (final r in _rows(list, 'anthologies'))
                if (r['id'] != id) r,
            ],
          });
        }
        await _forget('/anthologies/$id');
        await _forget('/anthologies/$id/removed');
        if (id < 0) {
          // it was never sent: its creation and everything queued against it go
          final q = _load();
          q.ops.removeWhere(
            (o) =>
                o['id'] == id ||
                (o['op'] == 'create' && o['tmp'] == id) ||
                (o['op'] == 'delete' && o['id'] == id),
          );
          await _save(q);
        }
      },
    );
  }

  @override
  Future<bool> add(int id, String kind, int itemId) {
    id = _id(id);
    return _change(
      {'op': 'add', 'id': id, 'kind': kind, 'item': itemId},
      anthologyId: id,
      online: () => _inner.add(id, kind, itemId),
      local: () async {
        var added = true;
        final known = await lookup?.call(kind, itemId);
        await _editDetail(id, (entries, sections) {
          if (entries.any((e) => e['kind'] == kind && e['item_id'] == itemId)) {
            added = false;
            return;
          }
          entries.add({
            'kind': kind,
            'item_id': itemId,
            'position': _last(entries, sections) + 1,
            'quote': '',
            'note': '',
            'source': '',
            'credit': '',
            'color': 'yellow',
            'language': '',
            'locator': '',
            ...?known,
          });
        });
        return added;
      },
    );
  }

  @override
  Future<void> removeEntry(int id, String kind, int itemId) {
    id = _id(id);
    return _change(
      {'op': 'remove', 'id': id, 'kind': kind, 'item': itemId},
      anthologyId: id,
      online: () => _inner.removeEntry(id, kind, itemId),
      local: () => _editDetail(
        id,
        (entries, _) => entries.removeWhere(
          (e) => e['kind'] == kind && e['item_id'] == itemId,
        ),
      ),
    );
  }

  @override
  Future<void> setNote(int id, String kind, int itemId, String note) {
    id = _id(id);
    return _change(
      {'op': 'note', 'id': id, 'kind': kind, 'item': itemId, 'note': note},
      anthologyId: id,
      online: () => _inner.setNote(id, kind, itemId, note),
      local: () => _editDetail(id, (entries, _) {
        for (final e in entries) {
          if (e['kind'] == kind && e['item_id'] == itemId) e['note'] = note;
        }
      }),
    );
  }

  Map<String, Object?>? _ref(({String kind, int itemId})? r) =>
      r == null ? null : {'kind': r.kind, 'item': r.itemId};

  @override
  Future<void> move(
    int id,
    String kind,
    int itemId, {
    ({String kind, int itemId})? after,
  }) {
    id = _id(id);
    itemId = kind == 'section' ? _sid(itemId) : itemId;
    return _change(
      {
        'op': 'move',
        'id': id,
        'kind': kind,
        'item': itemId,
        'after': _ref(after),
      },
      anthologyId: kind == 'section' && itemId < 0 ? -1 : id,
      online: () => _inner.move(id, kind, itemId, after: after),
      local: () => _editDetail(id, (entries, sections) {
        final list = kind == 'section' ? sections : entries;
        final mine = list
            .where(
              (x) => kind == 'section'
                  ? x['id'] == itemId
                  : x['kind'] == kind && x['item_id'] == itemId,
            )
            .firstOrNull;
        if (mine == null) return;
        mine['position'] = _after(entries, sections, after, mine);
      }),
    );
  }

  @override
  Future<AnthologySection> addSection(
    int id,
    String title,
    String prose, {
    ({String kind, int itemId})? after,
  }) async {
    id = _id(id);
    if (id > 0) {
      if (_load().ops.isNotEmpty) await flush();
      if (_load().ops.isEmpty) {
        try {
          return await _inner.addSection(id, title, prose, after: after);
        } on AnthologyException catch (e) {
          if (!e.unreachable) rethrow;
        }
      }
    }
    final q = _load();
    final tmp = q.next--;
    q.ops.add({
      'op': 'section',
      'id': id,
      'tmp': tmp,
      'title': title,
      'prose': prose,
      'after': _ref(after),
    });
    await _save(q);
    final section = <String, Object?>{
      'id': tmp,
      'position': 0.0,
      'title': title,
      'prose': prose,
    };
    await _editDetail(id, (entries, sections) {
      section['position'] = after == null
          ? _last(entries, sections) + 1
          : _after(entries, sections, after, null);
      sections.add(section);
    });
    return AnthologySection.fromJson(section);
  }

  @override
  Future<void> editSection(int id, int sectionId, String title, String prose) {
    id = _id(id);
    sectionId = _sid(sectionId);
    return _change(
      {
        'op': 'editSection',
        'id': id,
        'sid': sectionId,
        'title': title,
        'prose': prose,
      },
      anthologyId: sectionId < 0 ? -1 : id,
      online: () => _inner.editSection(id, sectionId, title, prose),
      local: () => _editDetail(id, (_, sections) {
        for (final s in sections) {
          if (s['id'] == sectionId) {
            s['title'] = title;
            s['prose'] = prose;
          }
        }
      }),
    );
  }

  @override
  Future<void> deleteSection(int id, int sectionId) {
    id = _id(id);
    sectionId = _sid(sectionId);
    return _change(
      {'op': 'deleteSection', 'id': id, 'sid': sectionId},
      anthologyId: sectionId < 0 ? -1 : id,
      online: () => _inner.deleteSection(id, sectionId),
      local: () => _editDetail(
        id,
        (_, sections) => sections.removeWhere((s) => s['id'] == sectionId),
      ),
    );
  }

  @override
  Future<void> setGrouping(int id, String groupBy) {
    id = _id(id);
    return _change(
      {'op': 'group', 'id': id, 'by': groupBy},
      anthologyId: id,
      online: () => _inner.setGrouping(id, groupBy),
      local: () => _patch(id, {'group_by': groupBy}),
    );
  }

  @override
  Future<void> setFront(
    int id,
    String epigraph,
    String dedication, {
    String? description,
  }) {
    id = _id(id);
    return _change(
      {
        'op': 'front',
        'id': id,
        'epigraph': epigraph,
        'dedication': dedication,
        'description': ?description,
      },
      anthologyId: id,
      online: () =>
          _inner.setFront(id, epigraph, dedication, description: description),
      local: () => _patch(id, {
        'epigraph': epigraph,
        'dedication': dedication,
        'description': ?description,
      }),
    );
  }

  @override
  Future<void> restore(int id, String kind, int itemId) {
    id = _id(id);
    return _change(
      {'op': 'restore', 'id': id, 'kind': kind, 'item': itemId},
      anthologyId: id,
      online: () => _inner.restore(id, kind, itemId),
      local: () async {
        final r = _read('/anthologies/$id/removed');
        if (r == null) return;
        await _write('/anthologies/$id/removed', {
          ...r,
          'removed': [
            for (final x in _rows(r, 'removed'))
              if (!(x['kind'] == kind && x['item_id'] == itemId)) x,
          ],
        });
      },
    );
  }

  /// A picture as large as this is not kept in a queue stored with the phone's small settings.
  static const _largestPicture = 1500000;

  @override
  Future<String> setCover(int id, Uint8List bytes, String fileName) async {
    id = _id(id);
    if (bytes.length > _largestPicture && (id < 0 || !await _reachable())) {
      return _needsServer();
    }
    return _change(
      {'op': 'cover', 'id': id, 'name': fileName, 'bytes': base64Encode(bytes)},
      anthologyId: id,
      online: () => _inner.setCover(id, bytes, fileName),
      local: () async => '',
    );
  }

  @override
  Future<void> removeCover(int id) {
    id = _id(id);
    return _change(
      {'op': 'removeCover', 'id': id},
      anthologyId: id,
      online: () => _inner.removeCover(id),
      local: () => _patch(id, {'cover_path': ''}),
    );
  }

  @override
  Future<String> setPoster(int id, Uint8List bytes, String fileName) async {
    id = _id(id);
    if (bytes.length > _largestPicture && (id < 0 || !await _reachable())) {
      return _needsServer();
    }
    return _change(
      {
        'op': 'poster',
        'id': id,
        'name': fileName,
        'bytes': base64Encode(bytes),
      },
      anthologyId: id,
      online: () => _inner.setPoster(id, bytes, fileName),
      local: () async => '',
    );
  }

  @override
  Future<void> removePoster(int id) {
    id = _id(id);
    return _change(
      {'op': 'removePoster', 'id': id},
      anthologyId: id,
      online: () => _inner.removePoster(id),
      local: () => _patch(id, {'poster_path': ''}),
    );
  }

  @override
  Future<FillResult> fill(
    int id,
    String rule, {
    bool preview = false,
    bool auto = false,
  }) {
    id = _id(id);
    // a count of what a search would find needs the server's library; saving the search to run does not
    if (preview) return _inner.fill(id, rule, preview: true, auto: auto);
    return _change(
      {'op': 'fill', 'id': id, 'rule': rule, 'auto': auto},
      anthologyId: id,
      online: () => _inner.fill(id, rule, auto: auto),
      local: () async {
        await _patch(id, {'rule': rule, 'rule_auto': auto});
        return const FillResult(
          added: 0,
          matched: 0,
          skipped: 0,
          capped: false,
        );
      },
    );
  }

  @override
  Future<ExportedFile> export(int id, {bool epub = false}) async {
    id = _id(id);
    if (id > 0) {
      try {
        return await _inner.export(id, epub: epub);
      } on AnthologyException catch (e) {
        if (!e.unreachable || epub) rethrow;
      }
    } else if (epub) {
      return _needsServer();
    }
    // Markdown can be made from the kept copy; an EPUB is built by the server
    final d = await get(id);
    return ExportedFile(_fileName(d.anthology.title), _markdown(d));
  }

  /// Whether the server answers right now (a bare question, so a large picture is not queued when it need not be).
  Future<bool> _reachable() async {
    try {
      await _inner.vocabulary();
      return true;
    } on AnthologyException catch (e) {
      return !e.unreachable;
    }
  }

  String _fileName(String title) {
    final safe = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '${safe.isEmpty ? 'anthology' : safe}.md';
  }

  Uint8List _markdown(AnthologyDetail d) {
    final out = StringBuffer('# ${d.anthology.title}\n\n');
    final description = (d.anthology.raw['description'] as String?) ?? '';
    if (description.trim().isNotEmpty) out.write('${description.trim()}\n\n');
    if (d.anthology.intro.trim().isNotEmpty) {
      out.write('${d.anthology.intro.trim()}\n\n');
    }
    for (final slot in d.slots) {
      final s = slot.section;
      if (s != null) {
        out.write('## ${s.title}\n\n');
        if (s.prose.trim().isNotEmpty) out.write('${s.prose.trim()}\n\n');
        continue;
      }
      final e = slot.entry!;
      for (final line in e.quote.trim().split('\n')) {
        out.write('> $line\n');
      }
      final by = [e.credit, e.source].where((x) => x.trim().isNotEmpty);
      if (by.isNotEmpty) out.write('>\n> ${by.join(', ')}\n');
      out.write('\n');
      if (e.note.trim().isNotEmpty) out.write('${e.note.trim()}\n\n');
    }
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  Future<T> _needsServer<T>() => Future.error(
    AnthologyException(tx('app.anthologies.not_sent_to_the_server_yet')),
  );
}

/// The waiting changes, and the real ids of what was made while waiting.
class _Queue {
  _Queue();

  final List<Map<String, Object?>> ops = [];

  /// A temporary id (`a:-1`, `s:-2`) and the real one the server gave it.
  final Map<String, int> map = {};

  /// The next temporary id.
  int next = -1;

  factory _Queue.fromJson(Map<String, Object?> j) {
    final q = _Queue();
    for (final o in (j['ops'] as List? ?? const [])) {
      q.ops.add(Map<String, Object?>.from(o as Map));
    }
    for (final e in (j['map'] as Map? ?? const {}).entries) {
      q.map['${e.key}'] = (e.value as num).toInt();
    }
    q.next = (j['next'] as num?)?.toInt() ?? -1;
    return q;
  }

  Map<String, Object?> toJson() => {'ops': ops, 'map': map, 'next': next};
}
