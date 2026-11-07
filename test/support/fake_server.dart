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

  /// The server's boards, as `GET /boards` lists them.
  final boards = <Map<String, Object?>>[];

  /// Every board edit and delete the server was sent.
  final boardWrites = <Map<String, Object?>>[];
  final boardDeletes = <Map<String, Object?>>[];

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

  /// What `GET /review/daily` answers (the whole body).
  Map<String, Object?> reviewDaily = {'items': <Object?>[]};

  /// What `GET /review/practice` answers.
  Map<String, Object?> reviewPractice = {'items': <Object?>[]};

  /// What `GET /review/scores` answers.
  Map<String, Object?> reviewScores = {};

  /// Every `POST /review/answer` body taken, in order.
  final reviewAnswers = <Map<String, Object?>>[];

  /// Every `POST /review/seen` body taken.
  final reviewSeen = <Map<String, Object?>>[];

  /// How many times `DELETE /review/practice` was asked.
  int practiceResets = 0;

  /// While true, an answer cannot reach the server (the network went away).
  bool reviewOffline = false;

  /// A status the answer route refuses with (e.g. 404 for a quote that is gone), or null to take it.
  int? reviewAnswerRefusal;

  /// The server's tags: id, name, color, style, annotations, dialogues. `GET/POST /tags`, `PUT/DELETE /tags/{id}`,
  /// `POST /tags/merge`, with the real server's rules (a name is unique in any capitals: 409).
  final tags = <Map<String, Object?>>[];

  /// Every tag write the server took, as `PUT 3`, `DELETE 3`, `MERGE 3<-4,5`, `POST name`.
  final tagWrites = <String>[];

  /// The people the server knows, by kind ('author', 'actor', 'speaker'): rows of name, image_path, signature_path.
  /// `GET /people?kind=` lists one kind.
  final people = <String, List<Map<String, Object?>>>{};

  /// The characters the server knows (name, image_path). `GET /characters` lists them.
  final characterRows = <Map<String, Object?>>[];

  /// The full record of a person (`GET /people/id/{id}`), by id; `PUT /people/id/{id}` merges into it.
  final personDetails = <int, Map<String, Object?>>{};

  /// The full record of a character (`GET /characters/{id}`), by id.
  final characterDetails = <int, Map<String, Object?>>{};

  /// Every write to a person: the route (`PUT /people/id/3`) and what was sent.
  final personWrites = <(String, Object?)>[];

  /// How many times `GET /people` was asked.
  int peopleReads = 0;

  /// The languages the server has starter proverbs in, and how many in each. `GET /quotes/starters` lists them.
  final starterLanguages = <String, int>{'Bengali': 12, 'English': 10};

  /// Every `POST /quotes/starters` accepted: the language and the board it was for.
  final starterSeeds = <Map<String, Object?>>[];

  /// The pictures uploaded to boards (`POST /boards/{id}/cover`), by board id.
  final boardPictures = <int, List<int>>{};

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

  /// The server's boards: `GET/POST /boards`, `PUT/DELETE /boards/{id}`. A board that holds quotes can only be
  /// deleted with `move_to`, as on the real server. Null when [path] is not a board route.
  http.Response? _tagRoute(http.Request r, String path) {
    int next() =>
        tags.fold<int>(0, (a, t) => (t['id'] as int) > a ? t['id'] as int : a) +
        1;
    bool clash(String name, int? except) => tags.any(
      (t) =>
          t['id'] != except &&
          (t['name'] as String).toLowerCase() == name.toLowerCase(),
    );
    if (path == '/tags/merge' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map;
      final keep = tags.where((t) => t['id'] == body['keep_id']).firstOrNull;
      if (keep == null) return _json({'error': 'not found'}, 404);
      final drops = [for (final d in body['drop_ids'] as List) d as int];
      tags.removeWhere((t) => drops.contains(t['id']));
      tagWrites.add('MERGE ${keep['id']}<-${drops.join(',')}');
      return _json({'tag': keep, 'moved': 0});
    }
    if (path == '/tags') {
      if (r.method == 'GET') return _json({'tags': tags});
      if (r.method == 'POST') {
        final body = jsonDecode(r.body) as Map;
        final name = (body['name'] as String? ?? '').trim();
        if (name.isEmpty) return _json({'error': 'name is required'}, 400);
        if (clash(name, null)) {
          return _json({'error': 'tag already exists'}, 409);
        }
        final row = <String, Object?>{
          'id': next(),
          'name': name,
          'color': body['color'] ?? 'yellow',
          'style': 'sticker',
          'annotations': 0,
          'dialogues': 0,
        };
        tags.add(row);
        tagWrites.add('POST $name');
        return _json(row, 201);
      }
    }
    final one = RegExp(r'^/tags/(\d+)$').firstMatch(path);
    if (one == null) return null;
    final id = int.parse(one[1]!);
    final i = tags.indexWhere((t) => t['id'] == id);
    if (i < 0) return _json({'error': 'tag not found'}, 404);
    if (r.method == 'PUT') {
      final body = jsonDecode(r.body) as Map;
      final name = (body['name'] as String? ?? '').trim();
      if (clash(name, id)) return _json({'error': 'tag already exists'}, 409);
      tags[i] = {
        ...tags[i],
        'name': name,
        'color': body['color'],
        'style': body['style'],
      };
      tagWrites.add('PUT $id');
      return _json(tags[i]);
    }
    if (r.method == 'DELETE') {
      tags.removeAt(i);
      tagWrites.add('DELETE $id');
      return _json({'ok': true});
    }
    return null;
  }

  http.Response? _boardRoute(http.Request r, String path) {
    if (path == '/boards') {
      if (r.method == 'GET') {
        return _json({'boards': boards, 'total': 0});
      }
      if (r.method == 'POST') {
        final body = jsonDecode(r.body) as Map;
        final name = (body['name'] as String? ?? '').trim();
        if (name.isEmpty) return _json({'error': 'name is required'}, 400);
        if (boards.any(
          (b) => (b['name'] as String).toLowerCase() == name.toLowerCase(),
        )) {
          return _json({'error': 'a board called that already exists'}, 409);
        }
        final row = <String, Object?>{
          'id': _nextId++,
          'name': name,
          'description': '',
          'color': (body['color'] as String?)?.isNotEmpty == true
              ? body['color']
              : 'yellow',
          'image_path': '',
          'hidden': false,
          'pos': boards.length,
          'quotes': 0,
          'kind': 'plain',
          'languages': <String>[],
          'text_order': '',
        };
        boards.add(row);
        return _json(row, 201);
      }
    }
    final pic = RegExp(r'^/boards/(\d+)/cover$').firstMatch(path);
    if (pic != null && r.method == 'POST') {
      final id = int.parse(pic[1]!);
      final i = boards.indexWhere((b) => b['id'] == id);
      if (i < 0) return _json({'error': 'board not found'}, 404);
      boardPictures[id] = r.bodyBytes;
      final name = '${id.toRadixString(16).padLeft(16, '0')}.png';
      boards[i] = {...boards[i], 'image_path': name};
      return _json({'id': id, 'image_path': name, 'path': name});
    }
    final one = RegExp(r'^/boards/(\d+)$').firstMatch(path);
    if (one == null) return null;
    final id = int.parse(one[1]!);
    final i = boards.indexWhere((b) => b['id'] == id);
    if (i < 0) return _json({'error': 'board not found'}, 404);
    if (r.method == 'PUT') {
      final body = Map<String, Object?>.from(jsonDecode(r.body) as Map);
      boardWrites.add({...body, 'id': id});
      boards[i] = {...boards[i], ...body};
      return http.Response('', 204);
    }
    if (r.method == 'DELETE') {
      final held = (created['/quotes'] ?? []).where((q) => q['board_id'] == id);
      Map? body;
      if (r.body.isNotEmpty) body = jsonDecode(r.body) as Map;
      final moveTo = body?['move_to'];
      if (held.isNotEmpty) {
        if (moveTo is! int ||
            moveTo == id ||
            !boards.any((b) => b['id'] == moveTo)) {
          return _json({'error': 'say where its quotes go (move_to)'}, 400);
        }
        for (final q in held.toList()) {
          q['board_id'] = moveTo;
        }
      }
      boards.removeAt(i);
      boardDeletes.add({'id': id, 'move_to': moveTo});
      return http.Response('', 204);
    }
    return null;
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
    if (path == '/quotes/starters') {
      if (r.method == 'GET') {
        return _json({
          'languages': [
            for (final e in starterLanguages.entries)
              {'language': e.key, 'count': e.value},
          ],
        });
      }
      final body = jsonDecode(r.body) as Map;
      if (!starterLanguages.containsKey(body['language'])) {
        return _json({
          'error': 'no starter proverbs for ${body['language']}',
        }, 400);
      }
      starterSeeds.add(Map<String, Object?>.from(body));
      return _json({
        'language': body['language'],
        'added': starterLanguages[body['language']],
        'skipped': 0,
      });
    }
    if (path.startsWith('/review/')) {
      if (r.method == 'GET' && path == '/review/daily') {
        return _json(reviewDaily);
      }
      if (r.method == 'GET' && path == '/review/practice') {
        return _json(reviewPractice);
      }
      if (r.method == 'GET' && path == '/review/scores') {
        return _json(reviewScores);
      }
      if (r.method == 'DELETE' && path == '/review/practice') {
        practiceResets++;
        return _json({'ok': true});
      }
      if (r.method == 'POST' && path == '/review/seen') {
        reviewSeen.add(Map<String, Object?>.from(jsonDecode(r.body) as Map));
        return _json({'ok': true});
      }
      if (r.method == 'POST' && path == '/review/answer') {
        if (reviewOffline) {
          throw const SocketException('the network went away');
        }
        if (reviewAnswerRefusal != null) {
          return _json({'error': 'refused'}, reviewAnswerRefusal!);
        }
        final body = Map<String, Object?>.from(jsonDecode(r.body) as Map);
        reviewAnswers.add(body);
        final attempt = body['attempt'];
        return _json({
          'ok': true,
          'result': attempt == null
              ? body['result']
              : (attempt == 'woods' ? 'got' : 'forgot'),
          if (attempt != null) 'answer': 'woods',
          'mode': body['mode'],
          'answered': reviewAnswers.length,
          'got': 0,
          'forgot': 0,
          if (body['mode'] == 'daily') 'remaining': 0,
        });
      }
    }
    if (r.method == 'GET' && path == '/people') {
      peopleReads++;
      return _json({'people': people[r.url.queryParameters['kind']] ?? []});
    }
    final person = RegExp(r'^/people/id/(\d+)(/.*)?$').firstMatch(path);
    if (person != null) {
      final id = int.parse(person[1]!);
      final row = personDetails[id];
      if (row == null) return _json({'error': 'not found'}, 404);
      if (r.method == 'GET' && person[2] == null) return _json(row);
      if (r.method == 'PUT' && person[2] == null) {
        final body = Map<String, Object?>.from(jsonDecode(r.body) as Map);
        personWrites.add(('PUT $path', body));
        personDetails[id] = {
          ...row,
          for (final e in body.entries)
            if (e.key == 'clear_image')
              'image_path': ''
            else if (e.key == 'clear_signature')
              'signature_path': ''
            else
              e.key: e.value,
        };
        return _json(personDetails[id]!);
      }
      personWrites.add(('${r.method} $path', r.bodyBytes.length));
      return _json(row);
    }
    final character = RegExp(r'^/characters/(\d+)$').firstMatch(path);
    if (r.method == 'GET' && character != null) {
      final row = characterDetails[int.parse(character[1]!)];
      return row == null ? _json({'error': 'not found'}, 404) : _json(row);
    }
    if (r.method == 'GET' && path == '/characters') {
      return _json({'characters': characterRows});
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
    final board = _boardRoute(r, path);
    if (board != null) return board;
    final tag = _tagRoute(r, path);
    if (tag != null) return tag;
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
