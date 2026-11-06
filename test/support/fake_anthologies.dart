import 'package:tippani/anthologies/anthologies.dart';

/// The server's anthologies, in memory, for screen tests.
class FakeAnthologies implements AnthologyService {
  FakeAnthologies({this.available = true});

  @override
  bool available;

  /// When set, every call throws it.
  AnthologyException? fail;

  int _next = 1;
  final _titles = <int, String>{};
  final _intros = <int, String>{};
  final _entries = <int, List<AnthologyEntry>>{};
  final calls = <String>[];

  /// A quote the screens can add, as the detail will show it.
  void put(int id, AnthologyEntry e) => _entries[id]!.add(e);

  void _check() {
    final f = fail;
    if (f != null) throw f;
  }

  Anthology _row(int id) => Anthology(
    id: id,
    title: _titles[id]!,
    intro: _intros[id]!,
    entries: _entries[id]!.length,
    raw: {
      'id': id,
      'title': _titles[id],
      'intro': _intros[id],
      'hide_credit': true,
    },
  );

  Anthology seed(String title, {String intro = ''}) {
    final id = _next++;
    _titles[id] = title;
    _intros[id] = intro;
    _entries[id] = [];
    return _row(id);
  }

  @override
  Future<List<Anthology>> list() async {
    _check();
    return [for (final id in _titles.keys) _row(id)];
  }

  @override
  Future<AnthologyDetail> get(int id) async {
    _check();
    if (!_titles.containsKey(id)) {
      throw const AnthologyException('The server could not do that.');
    }
    return AnthologyDetail(_row(id), List.of(_entries[id]!));
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
    _titles[a.id] = title;
    _intros[a.id] = intro;
  }

  @override
  Future<void> delete(int id) async {
    _check();
    calls.add('delete $id');
    _titles.remove(id);
    _intros.remove(id);
    _entries.remove(id);
  }

  @override
  Future<bool> add(int id, String kind, int itemId) async {
    _check();
    calls.add('add $id $kind $itemId');
    final list = _entries[id]!;
    if (list.any((e) => e.kind == kind && e.itemId == itemId)) return false;
    list.add(
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
    _entries[id]!.removeWhere((e) => e.kind == kind && e.itemId == itemId);
  }
}
