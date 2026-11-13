import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/api_client.dart';
import 'package:tippani/api/offline_cache.dart';
import 'package:tippani/settings/settings_store.dart';

// The screens that only read keep what the server last said and show it when the server cannot be reached
// (ADR-0022). What matters is which answers are kept, which are not, and that only "could not reach it" falls
// back: a refusal is the server's word.

Future<OfflineCache> _cache({
  int maxBytes = 3000000,
  int maxEntries = 400,
}) async {
  SharedPreferences.setMockInitialValues({});
  return OfflineCache(
    SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
    maxBytes: maxBytes,
    maxEntries: maxEntries,
  );
}

http.Response _json(String body, [int status = 200]) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ApiClient _client(OfflineCache cache, MockClientHandler handler) => ApiClient(
  base: Uri.parse('https://q.example.org/api'),
  token: 't',
  client: MockClient(handler),
)..offline = cache;

void main() {
  group('which answers are kept', () {
    test('the screens that display what the server holds', () {
      for (final p in [
        '/anthologies',
        '/anthologies/4',
        '/anthologies/4/removed',
        '/quotes/annotation/12/context?before=3&after=3',
        '/quotes/utterance/7/context',
        '/stats?offset=60',
        '/tags',
        '/trash',
        '/people/records',
        '/people/id/9',
        '/characters/3',
        '/cleanup?bucket=open',
        '/metadata/library',
        '/context-rules/book/5',
        '/review/daily?offset=0',
        '/review/scores?offset=0',
        '/import/staged?limit=50',
        '/auth/devices',
        '/quotes/starters',
      ]) {
        expect(OfflineCache.isCacheablePath(p), isTrue, reason: p);
      }
    });

    test('never what sync or the pairing reads', () {
      for (final p in [
        '/books',
        '/movies',
        '/annotations',
        '/dialogues',
        '/quotes',
        '/quotes?id=4',
        '/boards',
        '/auth/me',
        '/capabilities',
        '/review/answer',
        '/jobs',
        '/anthologiesx',
      ]) {
        expect(OfflineCache.isCacheablePath(p), isFalse, reason: p);
      }
    });
  });

  group('a read when the server cannot be reached', () {
    test('returns the last answer, and says when it is from', () async {
      final cache = await _cache();
      var up = true;
      final c = _client(cache, (r) async {
        if (!up) throw const SocketException('no route');
        return _json('{"anthologies":[{"id":1,"title":"Proverbs"}]}');
      });
      expect(cache.servedFrom.value, isNull);
      final live = await c.getJson('/anthologies');
      expect(live, {
        'anthologies': [
          {'id': 1, 'title': 'Proverbs'},
        ],
      });

      up = false;
      final offline = await c.getJson('/anthologies');
      expect(offline, live);
      expect(cache.servedFrom.value, isNotNull);

      up = true;
      await c.getJson('/anthologies');
      expect(cache.servedFrom.value, isNull, reason: 'the server is back');
    });

    test('is a failure when nothing was kept for that path', () async {
      final cache = await _cache();
      final c = _client(cache, (r) async => throw const SocketException('x'));
      await expectLater(
        c.getJson('/anthologies'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.network,
          ),
        ),
      );
    });

    test(
      'is a failure for a path that is never kept, even with others kept',
      () async {
        final cache = await _cache();
        var up = true;
        final c = _client(cache, (r) async {
          if (!up) throw const SocketException('x');
          return _json('[]');
        });
        await c.getJson('/books');
        up = false;
        await expectLater(c.getJson('/books'), throwsA(isA<ApiException>()));
      },
    );

    test(
      'a refusal is the server\'s word and is not covered by an old answer',
      () async {
        final cache = await _cache();
        var refuse = false;
        final c = _client(cache, (r) async {
          if (refuse) return _json('{"error":"no"}', 403);
          return _json('{"tags":[]}');
        });
        await c.getJson('/tags');
        refuse = true;
        await expectLater(
          c.getJson('/tags'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.failure,
              'failure',
              ApiFailure.forbidden,
            ),
          ),
        );
      },
    );

    test(
      'a path with a query is kept apart from the same path with another',
      () async {
        final cache = await _cache();
        var up = true;
        final c = _client(cache, (r) async {
          if (!up) throw const SocketException('x');
          return _json('{"q":"${r.url.query}"}');
        });
        await c.getJson('/stats?offset=0');
        await c.getJson('/stats?offset=60');
        up = false;
        expect(await c.getJson('/stats?offset=0'), {'q': 'offset=0'});
        expect(await c.getJson('/stats?offset=60'), {'q': 'offset=60'});
      },
    );
  });

  group('the bounds', () {
    test('the oldest go first, and an anthology is never dropped', () async {
      final cache = await _cache(maxEntries: 3);
      await cache.write('/anthologies/1', '{"a":1}');
      await cache.write('/tags', '[1]');
      await cache.write('/stats', '[2]');
      await cache.write('/trash', '[3]');
      await cache.write('/people/records', '[4]');
      expect(cache.read('/anthologies/1'), isNotNull);
      expect(cache.read('/tags'), isNull);
      expect(cache.read('/stats'), isNull);
      expect(cache.read('/trash'), isNotNull);
      expect(cache.read('/people/records'), isNotNull);
    });

    test('clear forgets everything', () async {
      final cache = await _cache();
      await cache.write('/anthologies', '{}');
      await cache.clear();
      expect(cache.read('/anthologies'), isNull);
    });
  });

  group('the bounds, harder', () {
    test('an answer larger than the whole cache is not kept and pushes nothing out', () async {
      final cache = await _cache(maxBytes: 2000);
      await cache.write('/tags', '[1]');
      await cache.write('/stats', '[2]');
      await cache.write('/trash', 'x' * 5000);
      expect(cache.read('/trash'), isNull);
      expect(cache.read('/tags'), isNotNull);
      expect(cache.read('/stats'), isNotNull);
    });

    test(
      'the oldest go when the bytes pass the cap, not only when the count does',
      () async {
        final cache = await _cache(maxBytes: 600);
        await cache.write('/tags', 'a' * 200);
        await cache.write('/stats', 'b' * 200);
        await cache.write('/trash', 'c' * 200);
        expect(cache.read('/tags'), isNull);
        expect(cache.read('/trash'), isNotNull);
      },
    );

    test('the reader\'s own anthologies keep to their share and never push out the rest', () async {
      final cache = await _cache(maxBytes: 3000);
      await cache.write('/tags', 't' * 300);
      for (var i = 1; i <= 6; i++) {
        await cache.write('/anthologies/$i', 'a' * 700);
      }
      expect(
        cache.read('/tags'),
        isNotNull,
        reason: 'anthologies may fill only two thirds',
      );
      expect(cache.read('/anthologies/6'), isNotNull);
      expect(
        cache.read('/anthologies/1'),
        isNull,
        reason: 'the oldest of them went',
      );
    });

    test('clear forgets an entry the index never named', () async {
      SharedPreferences.setMockInitialValues({
        'offline./orphan': '{"b":"x","t":1}',
      });
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final cache = OfflineCache(store);
      expect(cache.read('/orphan'), isNotNull);
      await cache.clear();
      expect(cache.read('/orphan'), isNull);
    });
  });

  group('the client', () {
    test(
      'a read of what was just saved is never answered from the kept copy',
      () async {
        final cache = await _cache();
        var up = true;
        final c = _client(cache, (r) async {
          if (!up) throw const SocketException('x');
          return _json('{"tmdb_key_set":false}');
        });
        await c.getJson('/admin/metadata-keys');
        up = false;
        await expectLater(
          c.getJsonLive('/admin/metadata-keys'),
          throwsA(isA<ApiException>()),
        );
        expect(await c.getJson('/admin/metadata-keys'), {
          'tmdb_key_set': false,
        });
      },
    );

    test('an empty answer forgets the older one', () async {
      final cache = await _cache();
      var empty = false;
      var up = true;
      final c = _client(cache, (r) async {
        if (!up) throw const SocketException('x');
        return empty ? http.Response('', 200) : _json('{"a":1}');
      });
      await c.getJson('/tags');
      empty = true;
      await c.getJson('/tags');
      up = false;
      await expectLater(c.getJson('/tags'), throwsA(isA<ApiException>()));
    });
  });
}
