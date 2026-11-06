import 'dart:convert';
import 'dart:io';

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

  // ---- the library routes (POST /books, /movies, /annotations, /dialogues, /quotes) --------------------

  /// What each create route has been given, in order, by route: `/books`, `/movies`, `/annotations`,
  /// `/dialogues`, `/quotes`. Each entry is the JSON body plus the id the fake gave it.
  final created = <String, List<Map<String, Object?>>>{};

  var _nextId = 100;

  /// A title the server refuses with a 400, as it does for a field it cannot take.
  String? refuseTitle;

  /// After this many successful creates the network drops (the next request throws), as when a phone
  /// leaves wifi half way. Null never drops.
  int? dropAfter;

  /// A create that answers 201 but with no id in it, as a proxy or a changed server might.
  bool omitId = false;

  /// Every create answers with this status instead (429, 500...), when set.
  int? failCreatesWith;

  static const _createRoutes = {
    '/books',
    '/movies',
    '/annotations',
    '/dialogues',
    '/quotes',
  };

  static const _colors = [
    'yellow',
    'blue',
    'pink',
    'orange',
    'green',
    'purple',
  ];

  http.Response _create(String path, Map body) {
    final all = created.values.fold<int>(0, (n, l) => n + l.length);
    if (dropAfter != null && all >= dropAfter!) {
      throw const SocketException('the network went away');
    }
    if (failCreatesWith != null) {
      return _json({'error': 'try later'}, failCreatesWith!);
    }
    final rows = created.putIfAbsent(path, () => []);
    String? bad;
    if (path == '/books' || path == '/movies') {
      if ((body['title'] as String? ?? '').trim().isEmpty) {
        bad = 'title is required';
      }
      if (refuseTitle != null && body['title'] == refuseTitle) {
        bad = 'title is not acceptable';
      }
      if (path == '/movies' &&
          !const ['movie', 'show', 'game'].contains(body['media_type'])) {
        bad = "media_type must be 'movie', 'show' or 'game'";
      }
    } else {
      if (!_colors.contains(body['color'])) bad = 'color must be one of them';
      if (!const ['manual', 'ocr'].contains(body['source'])) {
        bad = 'source must be manual or ocr';
      }
      if ((body['quote'] as String? ?? '').isEmpty) {
        bad = 'quote or note is required';
      }
      final parent = path == '/annotations'
          ? 'book_id'
          : path == '/dialogues'
          ? 'movie_id'
          : null;
      if (parent != null) {
        final owner = path == '/annotations' ? '/books' : '/movies';
        final known = (created[owner] ?? []).any(
          (b) => b['id'] == body[parent],
        );
        if (!known) {
          return _json({'error': 'work not found'}, 404);
        }
      }
    }
    if (bad != null) return _json({'error': bad}, 400);
    if (path != '/books' && path != '/movies') {
      final parent = body['book_id'] ?? body['movie_id'];
      for (final r in rows) {
        if (r['quote'] == body['quote'] &&
            (r['book_id'] ?? r['movie_id']) == parent) {
          return _json({'error': 'duplicate', 'existing': r}, 409);
        }
      }
    }
    final row = <String, Object?>{...body, 'id': _nextId++};
    rows.add(row);
    return omitId ? _json({'ok': true}, 201) : _json(row, 201);
  }

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
    if (r.method == 'POST' && _createRoutes.contains(path)) {
      return _create(path, jsonDecode(r.body) as Map);
    }
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
