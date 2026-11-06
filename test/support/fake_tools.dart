import 'package:tippani/api/server_call.dart';
import 'package:tippani/tools/server_tools.dart';

/// The server's bin and statistics, in memory, for screen tests.
class FakeTools implements ServerTools {
  FakeTools({this.available = true});

  @override
  bool available;

  ServerException? fail;
  final entries = <BinEntry>[];
  final calls = <String>[];
  LibraryStats statsToShow = LibraryStats.fromJson({});

  void _check() {
    final f = fail;
    if (f != null) throw f;
  }

  BinEntry put(
    int id,
    String label, {
    String kind = 'annotation',
    int children = 0,
  }) {
    final e = BinEntry(
      id: id,
      kind: kind,
      label: label,
      childCount: children,
      deletedAt: '2026-11-06',
    );
    entries.add(e);
    return e;
  }

  @override
  Future<Bin> bin() async {
    _check();
    return Bin(30, List.of(entries));
  }

  @override
  Future<void> restore(int id) async {
    _check();
    calls.add('restore $id');
    entries.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteForever(int id) async {
    _check();
    calls.add('forever $id');
    entries.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> emptyBin() async {
    _check();
    calls.add('empty');
    entries.clear();
  }

  @override
  Future<LibraryStats> stats() async {
    _check();
    return statsToShow;
  }
}
