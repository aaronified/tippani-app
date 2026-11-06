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

  test('401 and 403 are unauthorised, with the server\'s own words', () async {
    for (final status in [401, 403]) {
      final c = clientFor(
        (r) async => json('{"error":"token revoked"}', status),
      );
      try {
        await c.getJson('/quotes');
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.failure, ApiFailure.unauthorised);
        expect(e.detail, 'token revoked');
        expect(e.status, status);
      }
    }
  });

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
