import 'package:tippani/api/server_call.dart';
import 'package:tippani/metadata/metadata_service.dart';

/// Metadata kept in memory, so the screens can be tested without a server.
class FakeMetadata implements MetadataService {
  @override
  bool available = true;

  final calls = <String>[];

  List<GapWork> worksList = const [
    GapWork(
      kind: 'book',
      id: 1,
      title: 'Walden',
      creator: 'Thoreau',
      gaps: ['Cover', 'Synopsis'],
    ),
    GapWork(
      kind: 'book',
      id: 2,
      title: 'Middlemarch',
      creator: 'George Eliot',
      gaps: ['Year'],
    ),
    GapWork(kind: 'movie', id: 3, title: 'Casablanca'),
  ];
  List<List<DuplicateWork>> dups = [
    const [
      DuplicateWork(kind: 'book', id: 10, title: 'Dracula', quotes: 1),
      DuplicateWork(
        kind: 'book',
        id: 11,
        title: 'Dracula',
        quotes: 4,
        hasCover: true,
      ),
    ],
  ];
  List<ReverifyItem> checkResult = const [];
  String? refuse;
  List<ApplyItem> applied = [];

  @override
  Future<List<GapWork>> works() async => worksList;

  @override
  Future<List<List<DuplicateWork>>> duplicates() async => dups;

  @override
  Future<void> merge({
    required bool book,
    required int into,
    required List<int> from,
  }) async {
    calls.add('merge ${book ? 'book' : 'movie'} $into <- ${from.join(',')}');
    if (refuse != null) throw ServerException(refuse!);
    dups = const [];
  }

  @override
  Future<List<ReverifyItem>> check(List<GapWork> works) async {
    calls.add('check ${works.map((w) => '${w.kind}${w.id}').join(',')}');
    if (refuse != null) throw ServerException(refuse!);
    return checkResult;
  }

  @override
  Future<List<ApplyResult>> apply(List<ApplyItem> items) async {
    calls.add('apply ${items.length}');
    applied = items;
    return [
      for (final i in items) ApplyResult(type: i.type, id: i.id, ok: true),
    ];
  }

  @override
  Future<void> fillAll() async => calls.add('fillAll');

  @override
  Future<void> fetchCovers({bool missingOnly = true}) async =>
      calls.add('covers $missingOnly');
}
