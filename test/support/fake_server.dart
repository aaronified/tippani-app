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

  // ---- reading and editing the library (GET lists, GET /books/{id}, PUT /{route}/{id}) -------------------

  /// Every PUT the fake accepted, in order: the route (`/annotations/101`) and the body it was given.
  final updated = <({String path, Map<String, Object?> body})>[];

  /// Every list read answers with this status instead (500...), when set.
  int? failReadsWith;

  /// Every PUT answers with this status instead (400, 404...), when set.
  int? failUpdatesWith;

  /// Every DELETE of a work or quote the fake accepted, in order: the route (`/annotations/101`).
  final deleted = <String>[];

  /// Every DELETE of a work or quote answers with this status instead (409, 500...), when set.
  int? failDeletesWith;

  /// The cover pictures the server holds, by file name. `GET /covers/{name}` serves them.
  final covers = <String, List<int>>{};

  /// Every `GET /covers/{name}` asked for, in order.
  final coverReads = <String>[];

  /// Every cover upload accepted: the route (`/books/3/cover`) and the form body it came in.
  final coverUploads = <String>[];

  /// Cover reads and uploads answer with this status instead, when set.
  int? failCoversWith;

  /// The context the server stored, by kind and id (`annotation/3`): the answer to `GET /quotes/{kind}/{id}/context`.
  final contexts = <String, Map<String, Object?>>{};

  /// Every context read asked for, in order: the path with its query (`/quotes/annotation/3/context?before=4`).
  final contextReads = <String>[];

  /// A context read answers with this status instead, when set.
  int? failContextWith;

  /// The cast the server holds, by route and id (`/books/3`, `/movies/4`): `{character, actor}` rows.
  final casts = <String, List<Map<String, Object?>>>{};

  /// Every `GET /{books|movies}/{id}/cast` asked for, in order.
  final castReads = <String>[];

  /// A cast read answers with this status instead, when set.
  int? failCastWith;

  /// Puts a row on the server as if it had been made on the web, and returns its id. [path] is a create
  /// route (`/books`, `/annotations`...). The row is what the server's list would give back.
  int seed(String path, Map<String, Object?> fields, {int? id}) {
    id ??= _nextId++;
    created.putIfAbsent(path, () => []).add({...fields, 'id': id});
    return id;
  }

  /// Changes a row on the server directly, as an edit made on the web would.
  void edit(String path, int id, Map<String, Object?> fields) {
    final row = created[path]!.firstWhere((r) => r['id'] == id);
    row.addAll(fields);
  }

  /// Removes a row, as a delete on the web would.
  void remove(String path, int id) =>
      created[path]!.removeWhere((r) => r['id'] == id);

  /// The row now held for [id] on [path].
  Map<String, Object?> row(String path, int id) =>
      created[path]!.firstWhere((r) => r['id'] == id);

  static const _listKeys = {
    '/books': 'books',
    '/movies': 'movies',
    '/annotations': 'annotations',
    '/dialogues': 'dialogues',
    '/quotes': 'utterances',
  };

  http.Response _read(String path) {
    if (failReadsWith != null) {
      return _json({'error': 'try later'}, failReadsWith!);
    }
    return _json({
      _listKeys[path]!: [
        for (final r in created[path] ?? const <Map<String, Object?>>[]) r,
      ],
    });
  }

  http.Response _update(String route, int id, Map body) {
    if (failUpdatesWith != null) {
      return _json({'error': 'refused'}, failUpdatesWith!);
    }
    final rows = created[route] ?? [];
    final i = rows.indexWhere((r) => r['id'] == id);
    if (i < 0) return _json({'error': 'not found'}, 404);
    final isWork = route == '/books' || route == '/movies';
    if (isWork && (body['title'] as String? ?? '').trim().isEmpty) {
      return _json({'error': 'title is required'}, 400);
    }
    if (!isWork && (body['quote'] as String? ?? '').isEmpty) {
      return _json({'error': 'quote or note is required'}, 400);
    }
    updated.add((path: '$route/$id', body: Map<String, Object?>.from(body)));
    rows[i] = {...Map<String, Object?>.from(body), 'id': id};
    return _json(rows[i]);
  }

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
    final ctx = RegExp(
      r'^/quotes/(annotation|dialogue|utterance)/(\d+)/context$',
    ).firstMatch(path);
    if (r.method == 'GET' && ctx != null) {
      contextReads.add(r.url.hasQuery ? '$path?${r.url.query}' : path);
      if (failContextWith != null) {
        return _json({'error': 'try later'}, failContextWith!);
      }
      final c = contexts['${ctx[1]}/${ctx[2]}'];
      return c == null
          ? _json({'error': 'this quote has no context'}, 404)
          : _json(c);
    }
    final castRoute = RegExp(r'^(/books|/movies)/(\d+)/cast$').firstMatch(path);
    if (r.method == 'GET' && castRoute != null) {
      castReads.add('${castRoute[1]}/${castRoute[2]}');
      if (failCastWith != null) {
        return _json({'error': 'try later'}, failCastWith!);
      }
      return _json({
        'actor_role': 'actor',
        'cast': casts['${castRoute[1]}/${castRoute[2]}'] ?? [],
      });
    }
    final cover = RegExp(r'^/covers/([^/]+)$').firstMatch(path);
    if (r.method == 'GET' && cover != null) {
      coverReads.add(cover[1]!);
      if (failCoversWith != null) {
        return _json({'error': 'try later'}, failCoversWith!);
      }
      final bytes = covers[cover[1]!];
      return bytes == null
          ? _json({'error': 'not found'}, 404)
          : http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/png'},
            );
    }
    final upload = RegExp(r'^(/books|/movies)/(\d+)/cover$').firstMatch(path);
    if (r.method == 'POST' && upload != null) {
      if (failCoversWith != null) {
        return _json({'error': 'refused'}, failCoversWith!);
      }
      final rows = created[upload[1]!] ?? [];
      final i = rows.indexWhere((x) => x['id'] == int.parse(upload[2]!));
      if (i < 0) return _json({'error': 'not found'}, 404);
      final type = r.headers['content-type'] ?? '';
      if (!type.startsWith('multipart/form-data') ||
          !String.fromCharCodes(r.bodyBytes).contains('name="file"')) {
        return _json({'error': 'a picture is needed'}, 400);
      }
      coverUploads.add('${upload[1]}/${upload[2]}/cover');
      final name =
          '${(0x0abc000000000000 + coverUploads.length).toRadixString(16).padLeft(16, '0')}.png';
      covers[name] = r.bodyBytes;
      rows[i][upload[1] == '/books' ? 'cover_path' : 'poster_path'] = name;
      return _json({'cover_path': name});
    }
    if (r.method == 'POST' && _createRoutes.contains(path)) {
      return _create(path, jsonDecode(r.body) as Map);
    }
    if (r.method == 'GET' && _listKeys.containsKey(path)) return _read(path);
    final one = RegExp(
      r'^(/books|/movies|/annotations|/dialogues|/quotes)/(\d+)$',
    ).firstMatch(path);
    if (one != null) {
      final route = one[1]!;
      final id = int.parse(one[2]!);
      if (r.method == 'GET') {
        final rows = created[route] ?? [];
        final hit = rows.where((x) => x['id'] == id);
        return hit.isEmpty
            ? _json({'error': 'not found'}, 404)
            : _json(hit.first);
      }
      if (r.method == 'PUT') {
        return _update(route, id, jsonDecode(r.body) as Map);
      }
      if (r.method == 'DELETE') {
        if (failDeletesWith != null) {
          return _json({'error': 'refused'}, failDeletesWith!);
        }
        final rows = created[route] ?? [];
        if (!rows.any((x) => x['id'] == id)) {
          return _json({'error': 'not found'}, 404);
        }
        rows.removeWhere((x) => x['id'] == id);
        // a book or film takes its quotes with it, as the real server's bin does
        final childKey = route == '/books'
            ? ('/annotations', 'book_id')
            : route == '/movies'
            ? ('/dialogues', 'movie_id')
            : null;
        if (childKey != null) {
          created[childKey.$1]?.removeWhere((x) => x[childKey.$2] == id);
        }
        deleted.add('$route/$id');
        return _json({'ok': true});
      }
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
