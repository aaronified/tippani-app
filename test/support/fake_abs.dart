import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An Audiobookshelf server in memory, answering the way the owner's 2.37.2 does for the routes the app uses.
///
/// Refresh tokens rotate: a refresh token works once, then it is spent. A test that refreshes twice with
/// the same token gets 401, which is what a real server does and what a careless client would trip over.
class FakeAbs {
  FakeAbs() {
    client = MockClient.streaming((request, body) async {
      final text = await utf8.decodeStream(body);
      final r = await _handle(request, text);
      return http.StreamedResponse(
        Stream.value(utf8.encode(r.body)),
        r.statusCode,
        headers: r.headers,
      );
    });
  }

  late final http.Client client;

  String version = '2.37.2';

  /// When false the server answers `/status` like some other program would.
  bool isAbs = true;
  List<String> authMethods = ['local', 'openid'];
  String user = 'test', password = '1234', userId = 'u-test';

  /// Failed logins allowed before the server answers 429.
  int loginLimit = 10;
  int failedLogins = 0;

  /// Every request as `METHOD path`, in order.
  final calls = <String>[];

  int _n = 0;
  String access = '', refresh = '';
  final spentRefresh = <String>{};

  /// When true the next authenticated request is refused once, as if the access token had just expired.
  bool expireAccess = false;

  /// The browser sign-in's redirect addresses the server accepts.
  List<String> allowedRedirects = [
    'audiobookshelf://oauth',
    'tippani://oauth/abs',
  ];

  final bookmarks = <int, Map<String, Object?>>{};
  final sessions = <String, Map<String, Object?>>{};

  final book = <String, Object?>{
    'id': 'li-1',
    'libraryId': 'lib-1',
    'size': 9463408,
    'addedAt': 1,
    'updatedAt': 2,
    'media': {
      'duration': 1147.6,
      'numChapters': 2,
      'metadata': {
        'title': 'Sapiens',
        'authorName': 'Yuval Noah Harari',
        'narratorName': 'Derek Perkins',
        'asin': 'B00ICN066A',
        'isbn': null,
        'language': 'English',
        'publishedYear': '2015',
      },
      'chapters': [
        {'id': 0, 'title': 'One', 'start': 0, 'end': 600.5},
        {'id': 1, 'title': 'Two', 'start': 600.5, 'end': 1147.6},
      ],
      'tracks': [
        {
          'index': 1,
          'startOffset': 0,
          'duration': 1147.6,
          'mimeType': 'audio/mp4',
          'contentUrl': '/api/items/li-1/file/1',
        },
      ],
    },
  };

  String _mint() {
    _n++;
    access = 'access-$_n';
    refresh = 'refresh-$_n';
    return jsonEncode({
      'user': {
        'id': userId,
        'username': user,
        'type': 'user',
        'accessToken': access,
        'refreshToken': refresh,
        'bookmarks': <Object?>[],
      },
    });
  }

  static const _jsonType = {'content-type': 'application/json'};

  http.Response _json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _jsonType);

  http.Response _minted() => http.Response(_mint(), 200, headers: _jsonType);

  Future<http.Response> _handle(http.BaseRequest req, String body) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    Map<String, Object?> json() =>
        body.isEmpty ? {} : Map<String, Object?>.from(jsonDecode(body) as Map);

    if (path == '/status') {
      return _json({
        'app': isAbs ? 'audiobookshelf' : 'jellyfin',
        'serverVersion': version,
        'isInit': true,
        'authMethods': authMethods,
        'authFormData': {
          'authOpenIDButtonText': 'Login with Authelia',
          'authOpenIDAutoLaunch': false,
        },
      });
    }
    if (path == '/login') {
      if (failedLogins >= loginLimit) return http.Response('Too many', 429);
      final j = json();
      if (j['username'] != user || j['password'] != password) {
        failedLogins++;
        return http.Response('Unauthorized', 401);
      }
      return _minted();
    }
    if (path == '/auth/openid') {
      final redirect = req.url.queryParameters['redirect_uri'] ?? '';
      if (!allowedRedirects.contains(redirect)) {
        return http.Response('Invalid redirect_uri', 400);
      }
      final state = req.url.queryParameters['state'];
      return http.Response(
        '',
        302,
        headers: {
          'location':
              'https://au.example/api/oidc/authorization?client_id=audiobookshelf&state=$state',
          'set-cookie':
              'auth_cb=abc123; Max-Age=300; Path=/; HttpOnly, other=1; Path=/',
        },
      );
    }
    if (path == '/auth/openid/callback') {
      final q = req.url.queryParameters;
      if (q['code'] != 'good-code' || (req.headers['Cookie'] ?? '').isEmpty) {
        return http.Response('Bad', 400);
      }
      return _minted();
    }
    if (path == '/auth/refresh') {
      final t = req.headers['x-refresh-token'] ?? '';
      if (t != refresh || spentRefresh.contains(t)) {
        return http.Response('Unauthorized', 401);
      }
      spentRefresh.add(t);
      return _minted();
    }

    // Everything below needs the current access token.
    final bearer = (req.headers['Authorization'] ?? '').replaceFirst(
      'Bearer ',
      '',
    );
    if (expireAccess) {
      expireAccess = false;
      return http.Response('Unauthorized', 401);
    }
    if (bearer.isEmpty || bearer != access) {
      return http.Response('Unauthorized', 401);
    }

    if (path == '/api/libraries') {
      return _json({
        'libraries': [
          {'id': 'lib-1', 'name': 'My Books', 'mediaType': 'book'},
          {'id': 'lib-2', 'name': 'Podcasts', 'mediaType': 'podcast'},
        ],
      });
    }
    if (path == '/api/libraries/lib-1/items') {
      return _json({
        'results': [book],
        'total': 143,
        'page': int.parse(req.url.queryParameters['page'] ?? '0'),
      });
    }
    if (path == '/api/items/li-1') return _json(book);
    if (path == '/api/me') {
      return _json({
        'id': userId,
        'username': user,
        'bookmarks': bookmarks.values.toList(),
        'mediaProgress': [
          {
            'libraryItemId': 'li-1',
            'currentTime': 30.5,
            'duration': 1147.6,
            'isFinished': false,
            'lastUpdate': 99,
          },
        ],
      });
    }
    if (path == '/api/items/li-1/play') {
      final id = 'sess-${sessions.length + 1}';
      final media = book['media'] as Map<String, Object?>;
      sessions[id] = {'id': id, 'open': true};
      return _json({
        'id': id,
        'libraryItemId': 'li-1',
        'startTime': 30.5,
        'duration': 1147.6,
        'chapters': media['chapters'],
        'audioTracks': media['tracks'],
      });
    }
    final sync = RegExp(r'^/api/session/([^/]+)/(sync|close)$')
        .firstMatch(path);
    if (sync != null) {
      final s = sessions[sync.group(1)];
      if (s == null) return http.Response('Not found', 404);
      s['last'] = json();
      if (sync.group(2) == 'close') s['open'] = false;
      return http.Response('OK', 200);
    }
    if (path == '/api/session/local') {
      sessions['local-${sessions.length}'] = json();
      return http.Response('OK', 200);
    }
    if (path == '/api/me/item/li-1/bookmark' && req.method == 'POST') {
      final j = json();
      final time = (j['time'] as num).toInt();
      final b = {
        'libraryItemId': 'li-1',
        'time': time,
        'title': j['title'],
        'createdAt': 1000 + bookmarks.length,
      };
      bookmarks[time] = b;
      return _json(b);
    }
    final del = RegExp(r'^/api/me/item/li-1/bookmark/(\d+)$').firstMatch(path);
    if (del != null && req.method == 'DELETE') {
      bookmarks.remove(int.parse(del.group(1)!));
      return http.Response('OK', 200);
    }
    return http.Response('Not found', 404);
  }
}
