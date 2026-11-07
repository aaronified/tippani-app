// Runs the search code against a real Tippani server holding a book called "The Dispossessed" by Ursula Le Guin with
// a yellow highlight "The only thing that makes life possible is permanent, intolerable uncertainty." Skipped unless
// TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE are set.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/search/search_models.dart';
import 'package:tippani/search/search_service.dart';
import 'package:tippani/settings/settings_store.dart';

final _url = Platform.environment['TIPPANI_LIVE_URL'];
final _code = Platform.environment['TIPPANI_LIVE_CODE'];

void main() {
  final skip = (_url == null || _code == null)
      ? 'set TIPPANI_LIVE_URL and TIPPANI_LIVE_CODE'
      : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real requests

  test(
    'the real server answers the sections, forgives a typo and takes filters',
    () async {
      SharedPreferences.setMockInitialValues({'server_url': _url ?? ''});
      final controller = AppController(
        SettingsStore(
          await SharedPreferences.getInstance(),
          MemoryTokenVault(),
        ),
        log: AppLog(),
      );
      await controller.load();
      expect((await controller.pair(_code ?? '', 'live search')).ok, isTrue);
      final search = PairedSearch(controller);

      final plain = await search.search('dispossessed');
      expect(plain.fromServer, isTrue);
      expect(plain.works.map((w) => w.title), contains('The Dispossessed'));

      final byAuthor = await search.search('le guin');
      expect(byAuthor.people.map((p) => p.name), contains('Ursula Le Guin'));
      expect(byAuthor.people.first.role, 'author');

      final quote = await search.search('intolerable');
      expect(
        quote.quotes.map((q) => q.text).join(),
        contains('permanent, intolerable uncertainty'),
      );
      expect(quote.quotes.first.workTitle, 'The Dispossessed');

      // a typo is forgiven, and the corrected words come back
      final typo = await search.search('intolerabel uncertanty');
      expect(typo.isEmpty, isFalse);

      // a filter with no words, and one that narrows to nothing
      final yellow = await search.search(
        '',
        facets: const [SearchFacet('colour', 'yellow')],
      );
      expect(yellow.quotes, isNotEmpty);
      final none = await search.search(
        'intolerable',
        facets: const [SearchFacet('author', 'Nobody At All')],
      );
      expect(none.quotes, isEmpty);

      final scoped = await search.search(
        'dispossessed',
        scope: SearchScope.movies,
      );
      expect(scoped.works, isEmpty);

      final vocab = await search.vocabulary();
      expect(vocab.of('author'), contains('Ursula Le Guin'));
      expect(vocab.of('colour'), hasLength(6));
      expect(vocab.suggest('le gu').map((f) => f.label), [
        'Author: Ursula Le Guin',
      ]);
    },
    skip: skip,
  );
}
