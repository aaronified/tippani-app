import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tippani/api/api_client.dart';

ApiClient clientFor(
  MockClientHandler handler, {
  String? token,
  Duration timeout = const Duration(seconds: 5),
}) => ApiClient(
  base: Uri.parse('https://q.example.org/api'),
  token: token,
  client: MockClient(handler),
  timeout: timeout,
);

http.Response json(String body, [int status = 200]) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const okCaps =
    '{"version":"3.6.2","api_revision":8,"min_client_revision":1,"features":["device-tokens"]}';

Future<ApiFailure?> failureOf(Future<Object?> Function() call) async {
  try {
    await call();
    return null;
  } on ApiException catch (e) {
    return e.failure;
  }
}

void main() {
  test('asks /api/capabilities and reads the answer', () async {
    late Uri seen;
    final c = clientFor((r) async {
      seen = r.url;
      return json(okCaps);
    });
    final caps = await c.capabilities();
    expect(seen.toString(), 'https://q.example.org/api/capabilities');
    expect(caps.apiRevision, 8);
    expect(caps.has('device-tokens'), isTrue);
  });

  test('builds the path under a server mounted at a prefix', () async {
    late Uri seen;
    final c = ApiClient(
      base: Uri.parse('https://example.org/tippani/api'),
      client: MockClient((r) async {
        seen = r.url;
        return json(okCaps);
      }),
    );
    await c.capabilities();
    expect(seen.toString(), 'https://example.org/tippani/api/capabilities');
  });

  test('keeps a query string a query, and not part of the path', () async {
    late Uri seen;
    final c = clientFor((r) async {
      seen = r.url;
      return json('{}');
    });
    await c.getJson('/admin/logs?level=error%2Cwarn&q=50%25+errors&limit=200');
    expect(seen.path, '/api/admin/logs');
    expect(seen.queryParameters, {
      'level': 'error,warn',
      'q': '50% errors',
      'limit': '200',
    });
    await c.getJson('/quotes');
    expect(seen.hasQuery, isFalse);
  });

  test('sends the device token as a Bearer header, and none when there is no token', () async {
    final seen = <Map<String, String>>[];
    Future<http.Response> handler(http.Request r) async {
      seen.add(r.headers);
      return json('{}');
    }

    await clientFor(handler, token: 'abc123').getJson('/quotes');
    await clientFor(handler).getJson('/quotes');
    await clientFor(handler, token: '').getJson('/quotes');
    expect(seen[0]['Authorization'], 'Bearer abc123');
    expect(seen[1].containsKey('Authorization'), isFalse);
    expect(seen[2].containsKey('Authorization'), isFalse);
  });

  test('401 is unauthorised, with the server\'s own words', () async {
    final c = clientFor((r) async => json('{"error":"token revoked"}', 401));
    try {
      await c.getJson('/quotes');
      fail('should have thrown');
    } on ApiException catch (e) {
      expect(e.failure, ApiFailure.unauthorised);
      expect(e.detail, 'token revoked');
      expect(e.status, 401);
    }
  });

  test(
    '403 is forbidden, NOT unauthorised: a good token asked for an admin route',
    () async {
      final c = clientFor((r) async => json('{"error":"admin only"}', 403));
      try {
        await c.getJson('/admin/logs');
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(
          e.failure,
          ApiFailure.forbidden,
          reason: 'unauthorised would unpair the phone',
        );
        expect(e.status, 403);
      }
    },
  );

  test(
    '429 is rate limited, and POST and DELETE carry the token and a JSON body',
    () async {
      final seen = <http.Request>[];
      final c = clientFor((r) async {
        seen.add(r);
        return r.method == 'POST'
            ? json('{"ok":true}', 201)
            : http.Response('', 204);
      }, token: 'tok');
      expect(await c.postJson('/x', {'a': 1}), {'ok': true});
      expect(await c.delete('/x/1'), isNull);
      expect(seen[0].headers['Authorization'], 'Bearer tok');
      expect(seen[0].headers['Content-Type'], startsWith('application/json'));
      expect(seen[0].body, '{"a":1}');
      expect(seen[1].method, 'DELETE');
      expect(seen[1].headers['Authorization'], 'Bearer tok');

      final limited = clientFor(
        (r) async => json('{"error":"slow down"}', 429),
      );
      expect(
        await failureOf(() => limited.postJson('/x', {})),
        ApiFailure.rateLimited,
      );
    },
  );

  test('other error statuses are the server\'s failure', () async {
    expect(
      await failureOf(
        () =>
            clientFor((r) async => json('{"error":"boom"}', 500)).getJson('/x'),
      ),
      ApiFailure.server,
    );
    expect(
      await failureOf(
        () => clientFor((r) async => json('{}', 404)).getJson('/x'),
      ),
      ApiFailure.server,
    );
  });

  test('a refused connection is a network failure', () async {
    final c = clientFor(
      (r) async => throw const SocketException('Connection refused'),
    );
    expect(await failureOf(c.capabilities), ApiFailure.network);
  });

  test('a client error is a network failure', () async {
    final c = clientFor((r) async => throw http.ClientException('no route'));
    expect(await failureOf(c.capabilities), ApiFailure.network);
  });

  test('a slow server is a timeout', () async {
    final c = clientFor(
      (r) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 50),
    );
    expect(await failureOf(c.capabilities), ApiFailure.timeout);
  });

  test('an answer that is not JSON is a bad response, not a crash', () async {
    final c = clientFor(
      (r) async => http.Response('<html>welcome to my router</html>', 200),
    );
    expect(await failureOf(c.capabilities), ApiFailure.badResponse);
  });

  test('JSON that is not a capabilities answer is a bad response', () async {
    final c = clientFor((r) async => json('{"hello":"world"}'));
    expect(await failureOf(c.capabilities), ApiFailure.badResponse);
  });
}
