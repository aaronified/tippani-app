import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'abs_models.dart';

/// Why a call to Audiobookshelf failed. The words for the reader are chosen where it is shown.
enum AbsFailure {
  /// No answer: offline, wrong address, or the server is down.
  network,

  /// No answer in time.
  timeout,

  /// The server refused the credential and a refresh did not help: sign in again.
  unauthorised,

  /// The signed-in user may not do this.
  forbidden,

  /// Too many sign-in attempts. ABS counts failed logins in one bucket for every client, so wait.
  rateLimited,

  /// The server failed.
  server,

  /// The server sent something this app does not understand.
  badResponse,

  /// The item or route is not there.
  notFound,
}

class AbsException implements Exception {
  const AbsException(this.failure, [this.detail = '']);
  final AbsFailure failure;
  final String detail;
  @override
  String toString() => 'AbsException(${failure.name}): $detail';
}

/// A call to one Audiobookshelf server as one user.
///
/// It signs in, keeps the token pair fresh and asks for what the app needs. When the access token is
/// refused it refreshes once and tries again. Refresh tokens rotate, so only one refresh runs at a time and
/// every caller waits for that one: a second refresh with the old token could sign the user out.
class AbsClient {
  AbsClient(
    String baseUrl, {
    http.Client? client,
    this._tokens,
    this.onTokens,
    this.timeout = const Duration(seconds: 20),
    this.clientName = 'Tippani',
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _http = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final String clientName;

  /// Called with every new token pair, so the caller can keep it. Never called with a null.
  final Future<void> Function(AbsTokens tokens)? onTokens;

  final http.Client _http;
  AbsTokens? _tokens;
  Future<AbsTokens>? _refreshing;

  AbsTokens? get tokens => _tokens;
  bool get signedIn => _tokens != null;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Never _fail(AbsFailure f, [String detail = '']) =>
      throw AbsException(f, detail);

  AbsFailure _failureFor(int status) => switch (status) {
    401 => AbsFailure.unauthorised,
    403 => AbsFailure.forbidden,
    404 => AbsFailure.notFound,
    429 => AbsFailure.rateLimited,
    >= 500 => AbsFailure.server,
    _ => AbsFailure.badResponse,
  };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String> headers = const {},
    String? bearer,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers.addAll(headers);
    if (bearer != null) req.headers['Authorization'] = 'Bearer $bearer';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      _fail(AbsFailure.timeout);
    } on http.ClientException catch (e) {
      _fail(AbsFailure.network, e.message);
    }
  }

  /// The body as JSON. ABS answers many writes with a bare `OK`, so a body that is not JSON is `null` here,
  /// and a caller that needs an object says so with a type check.
  Object? _json(http.Response r) {
    if (r.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// `GET /status`: no credential needed. Use it to check an address and learn the sign-in methods.
  Future<AbsStatus> status() async {
    final r = await _send('GET', '/status');
    if (r.statusCode != 200) _fail(_failureFor(r.statusCode));
    final j = _json(r);
    if (j is! Map || j['app'] != 'audiobookshelf') {
      _fail(AbsFailure.badResponse, 'not an Audiobookshelf server');
    }
    return AbsStatus.fromJson(j);
  }

  Future<AbsTokens> _adopt(http.Response r, {AbsTokens? previous}) async {
    final t = AbsTokens.fromJson(_json(r), previous: previous);
    if (t == null) _fail(AbsFailure.badResponse, 'no token in the answer');
    _tokens = t;
    await onTokens?.call(t);
    return t;
  }

  /// `POST /login` with a username and password. Do not call this in a loop: ABS limits failed logins
  /// to a handful per ten minutes for everyone.
  Future<AbsTokens> loginWithPassword(String username, String password) async {
    final r = await _send(
      'POST',
      '/login',
      headers: const {'x-return-tokens': 'true'},
      body: {'username': username, 'password': password},
    );
    if (r.statusCode != 200) _fail(_failureFor(r.statusCode));
    return _adopt(r);
  }

  /// Finishes a browser sign-in: `GET /auth/openid/callback` with the code, the verifier and the session
  /// cookie [cookie] kept from [startOpenId].
  Future<AbsTokens> finishOpenId({
    required String code,
    required String state,
    required String verifier,
    required String cookie,
  }) async {
    final r = await _send(
      'GET',
      '/auth/openid/callback',
      query: {'code': code, 'state': state, 'code_verifier': verifier},
      headers: {'Cookie': cookie, 'x-return-tokens': 'true'},
    );
    if (r.statusCode != 200) _fail(_failureFor(r.statusCode));
    return _adopt(r);
  }

  /// Asks ABS where to send the person to sign in: the identity provider's address and the session cookie
  /// to send back with the code. Redirects are not followed, because the answer *is* the redirect.
  Future<AbsOpenIdStart> startOpenId({
    required String redirectUri,
    required String state,
    required String challenge,
  }) async {
    final req = http.Request(
      'GET',
      _uri('/auth/openid', {
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }),
    )..followRedirects = false;
    http.Response r;
    try {
      r = await http.Response.fromStream(
        await _http.send(req).timeout(timeout),
      );
    } on TimeoutException {
      _fail(AbsFailure.timeout);
    } on http.ClientException catch (e) {
      _fail(AbsFailure.network, e.message);
    }
    final location = r.headers['location'];
    if (r.statusCode < 300 || r.statusCode >= 400 || location == null) {
      // 400 here usually means the redirect address is not on ABS's allowed list.
      _fail(
        r.statusCode == 400 ? AbsFailure.forbidden : _failureFor(r.statusCode),
        'redirect not allowed or sign-in not set up',
      );
    }
    final setCookie = r.headers['set-cookie'] ?? '';
    return AbsOpenIdStart(
      authorizeUrl: Uri.parse(location),
      cookie: _cookiePairs(setCookie),
    );
  }

  /// Turns a `Set-Cookie` header into the `name=value; …` line a request sends back.
  static String _cookiePairs(String setCookie) {
    final pairs = <String>[];
    // Several cookies may be joined by commas; an `Expires=` date also holds one, so split on a comma that
    // is followed by a cookie name and an equals sign.
    for (final part in setCookie.split(RegExp(r',(?=\s*[^;,\s]+=)'))) {
      final first = part.split(';').first.trim();
      if (first.contains('=')) pairs.add(first);
    }
    return pairs.join('; ');
  }

  Future<AbsTokens> _refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final t = _tokens;
    if (t == null || t.refresh.isEmpty) {
      return Future.error(const AbsException(AbsFailure.unauthorised));
    }
    final f = () async {
      final r = await _send(
        'POST',
        '/auth/refresh',
        headers: {'x-refresh-token': t.refresh},
      );
      if (r.statusCode != 200) {
        // The refresh token is spent or revoked: the person has to sign in again.
        _tokens = null;
        _fail(
          r.statusCode == 401 || r.statusCode == 403
              ? AbsFailure.unauthorised
              : _failureFor(r.statusCode),
        );
      }
      return _adopt(r, previous: t);
    }();
    _refreshing = f;
    return f.whenComplete(() => _refreshing = null);
  }

  /// Makes the access token fresh now. Used before a long stream, where a 401 mid-stream is awkward.
  Future<AbsTokens> refreshNow() => _refresh();

  Future<Object?> _authed(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    var t = _tokens;
    if (t == null) _fail(AbsFailure.unauthorised);
    var r = await _send(
      method,
      path,
      query: query,
      body: body,
      bearer: t.access,
    );
    if (r.statusCode == 401) {
      t = await _refresh();
      r = await _send(method, path, query: query, body: body, bearer: t.access);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      _fail(_failureFor(r.statusCode));
    }
    return _json(r);
  }

  Future<List<AbsLibrary>> libraries() async {
    final j = await _authed('GET', '/api/libraries');
    final list = j is Map ? j['libraries'] : null;
    if (list is! List) _fail(AbsFailure.badResponse, 'no libraries list');
    return [for (final l in list) AbsLibrary.fromJson(l)];
  }

  /// One page of a library's books. [page] counts from zero.
  Future<AbsBookPage> books(
    String libraryId, {
    int page = 0,
    int limit = 100,
    String sort = 'media.metadata.title',
  }) async {
    final j = await _authed(
      'GET',
      '/api/libraries/$libraryId/items',
      query: {
        'limit': '$limit',
        'page': '$page',
        'sort': sort,
        'minified': '1',
      },
    );
    final m = j is Map ? j : const {};
    final results = m['results'];
    if (results is! List) _fail(AbsFailure.badResponse, 'no results list');
    return AbsBookPage([
      for (final b in results) AbsBook.fromJson(b),
    ], m['total'] is num ? (m['total'] as num).toInt() : results.length);
  }

  Future<AbsBookDetail> book(String itemId) async {
    final j = await _authed(
      'GET',
      '/api/items/$itemId',
      query: {'expanded': '1'},
    );
    if (j is! Map) _fail(AbsFailure.badResponse, 'no item');
    return AbsBookDetail.fromJson(j);
  }

  Future<AbsMe> me() async {
    final j = await _authed('GET', '/api/me');
    if (j is! Map) _fail(AbsFailure.badResponse, 'no user');
    return AbsMe.fromJson(j);
  }

  /// Opens a play session. The server picks direct play when the phone says it can play the formats.
  Future<AbsPlaySession> openPlaySession(
    String itemId, {
    required String deviceId,
    List<String> mimeTypes = const [
      'audio/mpeg',
      'audio/mp4',
      'audio/flac',
      'audio/ogg',
      'audio/aac',
    ],
  }) async {
    final j = await _authed(
      'POST',
      '/api/items/$itemId/play',
      body: {
        'deviceInfo': {'clientName': clientName, 'deviceId': deviceId},
        'mediaPlayer': clientName,
        'forceDirectPlay': true,
        'forceTranscode': false,
        'supportedMimeTypes': mimeTypes,
      },
    );
    if (j is! Map) _fail(AbsFailure.badResponse, 'no session');
    return AbsPlaySession.fromJson(j);
  }

  /// Reports progress on an open session. [listened] is the seconds heard since the last report.
  Future<void> syncSession(
    String sessionId, {
    required double currentTime,
    required double listened,
    required double duration,
  }) async {
    await _authed(
      'POST',
      '/api/session/$sessionId/sync',
      body: {
        'currentTime': currentTime,
        'timeListened': listened,
        'duration': duration,
      },
    );
  }

  Future<void> closeSession(
    String sessionId, {
    required double currentTime,
    required double listened,
  }) async {
    await _authed(
      'POST',
      '/api/session/$sessionId/close',
      body: {'currentTime': currentTime, 'timeListened': listened},
    );
  }

  /// Sends a listening session made offline. [session] is ABS's own session shape.
  Future<void> uploadLocalSession(Map<String, Object?> session) async {
    await _authed('POST', '/api/session/local', body: session);
  }

  Future<AbsBookmark> createBookmark(
    String itemId, {
    required int time,
    required String title,
  }) async {
    final j = await _authed(
      'POST',
      '/api/me/item/$itemId/bookmark',
      body: {'time': time, 'title': title},
    );
    return AbsBookmark.fromJson(j);
  }

  Future<void> deleteBookmark(String itemId, int time) async {
    await _authed('DELETE', '/api/me/item/$itemId/bookmark/$time');
  }

  /// The headers that let a player fetch [contentUrl] from this server.
  Map<String, String> streamHeaders() {
    final t = _tokens;
    if (t == null) _fail(AbsFailure.unauthorised);
    return {'Authorization': 'Bearer ${t.access}'};
  }

  Uri streamUri(String contentUrl) => _uri(contentUrl);

  void close() => _http.close();
}

/// Where a browser sign-in goes next, and the cookie to send back with the code.
class AbsOpenIdStart {
  const AbsOpenIdStart({required this.authorizeUrl, required this.cookie});
  final Uri authorizeUrl;
  final String cookie;
}
