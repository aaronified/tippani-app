import 'package:tippani/search/search_models.dart';
import 'package:tippani/search/search_service.dart';

/// A server search that answers what it is given, and records what it was asked.
class FakeSearch implements ServerSearch {
  FakeSearch({
    this.available = true,
    this.results = const SearchResults(fromServer: true),
    this.vocab = SearchVocabulary.empty,
  });

  @override
  bool available;

  SearchResults results;
  SearchVocabulary vocab;

  /// Make the next searches fail, as when the server cannot be reached.
  bool fail = false;

  final asked =
      <({String words, SearchScope scope, List<SearchFacet> facets})>[];

  @override
  Future<SearchResults> search(
    String words, {
    SearchScope scope = SearchScope.all,
    List<SearchFacet> facets = const [],
  }) async {
    asked.add((words: words, scope: scope, facets: facets));
    if (fail) throw Exception('the server could not be reached');
    return results;
  }

  @override
  Future<SearchVocabulary> vocabulary() async => vocab;
}
