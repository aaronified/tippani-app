import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tippani/api/api_client.dart';

/// A stand-in for a Tippani server, answering the routes the app calls the way the real one does
/// (`internal/httpapi`): capabilities, pairing, the device list, `/auth/me` and the admin log. State is
/// plain fields a test sets, and `requests` records what was asked, so a test can assert on the wire.
class FakeServer {
  FakeServer({this.admin = false, this.revision = 9});

  bool admin;
  int revision;

  /// The one pairing code the server will accept, once.
  String? code = 'ABCD2345';
  String claimedToken = 'tok-1234';
  String username = 'alice';

  /// False after the web Settings unpaired this phone: every authenticated route answers 401.
  bool tokenValid = true;

  /// 429 on the claim route, as when it is rate limited.
  bool rateLimit = false;

  /// The id of the device whose token this is; the real server marks that row `current`.
  int currentId = 2;

  final devices = <Map<String, Object?>>[
    {
      'id': 1,
      'name': 'Old tablet',
      'created_at': '2026-10-01 10:00:00',
      'last_seen_at': '2026-11-01 09:00:00',
    },
    {
      'id': 2,
      'name': 'My Android phone',
      'created_at': '2026-11-06 09:00:00',
      'last_seen_at': '',
    },
  ];

  /// The log lines the server holds, newest first.
  final logLines = <Map<String, Object?>>[];

  final requests = <http.Request>[];

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  bool _authed(http.Request r) =>
      tokenValid && r.headers['Authorization'] == 'Bearer $claimedToken';

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path.replaceFirst(RegExp(r'^.*?/api'), '');
    if (r.method == 'GET' && path == '/capabilities') {
      return _json({
        'version': '3.6.2',
        'api_revision': revision,
        'min_client_revision': 1,
        'features': <String>[],
      });
    }
    if (r.method == 'POST' && path == '/auth/devices/claim') {
      if (rateLimit) {
        return _json({'error': 'too many attempts, try again shortly'}, 429);
      }
      final body = jsonDecode(r.body) as Map;
      if (code == null || body['code'] != code) {
        return _json({'error': 'invalid or expired pairing code'}, 401);
      }
      code = null;
      currentId = 3;
      devices.add({
        'id': 3,
        'name': body['name'],
        'created_at': '2026-11-06 12:00:00',
        'last_seen_at': '',
      });
      return _json({'token': claimedToken, 'username': username}, 201);
    }
    if (!_authed(r)) return _json({'error': 'not logged in'}, 401);
    if (r.method == 'GET' && path == '/auth/me') {
      return _json({'id': 1, 'username': username, 'is_admin': admin});
    }
    if (r.method == 'GET' && path == '/auth/devices') {
      return _json({
        'devices': [
          for (final d in devices)
            {...d, if (revision >= 9 && d['id'] == currentId) 'current': true},
        ],
      });
    }
    final del = RegExp(r'^/auth/devices/(\d+)$').firstMatch(path);
    if (r.method == 'DELETE' && del != null) {
      final id = int.parse(del[1]!);
      final before = devices.length;
      devices.removeWhere((d) => d['id'] == id);
      return devices.length == before
          ? _json({'error': 'device not found'}, 404)
          : http.Response('', 204);
    }
    if (r.method == 'GET' && path == '/admin/logs') {
      if (!admin) return _json({'error': 'admin only'}, 403);
      final q = r.url.queryParameters;
      final levels = (q['level'] ?? '')
          .split(',')
          .where((l) => l.isNotEmpty)
          .toSet();
      final keyword = (q['q'] ?? '').toLowerCase();
      final before = int.tryParse(q['before'] ?? '');
      final limit = int.tryParse(q['limit'] ?? '') ?? 200;
      var rows = [
        for (final l in logLines)
          if ((levels.isEmpty || levels.contains(l['level'])) &&
              (keyword.isEmpty ||
                  (l['line'] as String).toLowerCase().contains(keyword)) &&
              (before == null || (l['id'] as int) < before))
            l,
      ];
      final more = rows.length > limit;
      if (more) rows = rows.sublist(0, limit);
      return _json({'lines': rows, 'more': more, 'from': 1000, 'upto': 99});
    }
    return _json({
      'error': 'no such route in the fake: ${r.method} $path',
    }, 404);
  }

  MockClient get client => MockClient(handle);

  ApiClient Function(Uri, String?) get factory =>
      (base, token) => ApiClient(base: base, token: token, client: client);

  List<String> get paths => [
    for (final r in requests)
      '${r.method} ${r.url.path.replaceFirst(RegExp(r'^.*?/api'), '')}',
  ];
}
