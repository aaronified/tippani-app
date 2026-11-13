import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'capabilities.dart';
import 'offline_cache.dart';

enum ApiFailure {
  /// Nothing answered: no route to the host, a refused connection, a bad certificate.
  network,

  /// Something answered too slowly.
  timeout,

  /// The server does not accept the credential (401). A revoked device token looks like this.
  unauthorised,

  /// The credential is good but not allowed to do this (403): an admin-only route asked by someone who is
  /// not an admin. It is NOT a reason to unpair the phone.
  forbidden,

  /// The server is limiting how often this can be asked (429). The pairing claim is limited on purpose.
  rateLimited,

  /// The server answered with an error of its own.
  server,

  /// Something answered, but not in a shape this app reads.
  badResponse,
}

class ApiException implements Exception {
  const ApiException(this.failure, [this.detail = '', this.status, this.body]);

  final ApiFailure failure;
  final String detail;
  final int? status;

  /// The server's JSON answer to a refused request, where it sent one. A duplicate (409) carries the row it
  /// clashed with here (`{"error": ..., "existing": {...}}`), which a retrying client needs.
  final Object? body;

  @override
  String toString() =>
      'ApiException($failure${status == null ? '' : ' $status'}: $detail)';
}

/// How long a request may take before the app gives up. A NAS asleep for the night is slow to wake.
const Duration requestTimeout = Duration(seconds: 15);

/// The one way the app speaks to a Tippani server.
///
/// [base] is the server's API root (the address the reader typed, plus `/api`). [token] is a device
/// token, sent as `Authorization: Bearer`; without one only the routes that need no credential
/// (`/capabilities`, the pairing claim) work. The client is injected so a test never touches a network.
class ApiClient {
  ApiClient({
    required this.base,
    this.token,
    http.Client? client,
    this.timeout = requestTimeout,
  }) : _client = client ?? http.Client();

  final Uri base;
  final String? token;
  final Duration timeout;
  final http.Client _client;

  /// The address for [path], which may carry a query (`/admin/logs?level=error`). The query is kept as a
  /// query: handing the whole string to Uri as a path would percent-encode the `?` and ask for a route
  /// that does not exist.
  Uri _uri(String path) {
    final parsed = Uri.parse(path);
    final clean = parsed.path.startsWith('/')
        ? parsed.path.substring(1)
        : parsed.path;
    final prefix = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(
      path: '$prefix$clean',
      query: parsed.hasQuery ? parsed.query : null,
    );
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// Asks the server what it is. No credential needed.
  Future<Capabilities> capabilities() async {
    final body = await getJson('/capabilities');
    final caps = Capabilities.fromJson(body);
    if (caps == null) {
      throw const ApiException(
        ApiFailure.badResponse,
        'not a Tippani capabilities answer',
      );
    }
    return caps;
  }

  /// POST [body] as JSON to [path] and decode the JSON answer (null for an empty one).
  Future<Object?> postJson(String path, Map<String, Object?> body) => _send(
    () => _client.post(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  /// PUT [body] as JSON to [path] and decode the JSON answer (null for an empty one).
  Future<Object?> putJson(String path, Map<String, Object?> body) => _send(
    () => _client.put(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  /// PATCH [body] as JSON to [path] and decode the JSON answer (null for an empty one).
  Future<Object?> patchJson(String path, Map<String, Object?> body) => _send(
    () => _client.patch(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  /// DELETE [path], with [body] as JSON when there is one. A 204 is an empty answer, so this returns null on
  /// success.
  Future<Object?> delete(String path, {Map<String, Object?>? body}) => _send(
    () => body == null
        ? _client.delete(_uri(path), headers: _headers)
        : _client.delete(
            _uri(path),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ),
  );

  /// Where a screen that only reads finds the server's last answer when the server cannot be reached; set by
  /// [AppController] on the clients it hands out. Null in a client made for a call that must be live.
  OfflineCache? offline;

  /// GET [path] and decode the JSON answer. For the paths [OfflineCache.isCacheablePath] allows, the answer is
  /// kept, and when the server cannot be reached (no network, or too slow) the kept one is returned instead:
  /// every other failure, a refusal included, is the server's word and is thrown.
  Future<Object?> getJson(String path) =>
      _getThrough(path, OfflineCache.isCacheablePath(path));

  /// [getJson] for a screen that has asked to show the server's last answer whatever the path (the account
  /// page: `/auth/me` is not kept for everyone, because the app learns it was unpaired from it).
  Future<Object?> getJsonKept(String path) => _getThrough(path, true);

  Future<Object?> _getThrough(String path, bool keep) async {
    final cache = offline;
    Future<http.Response> ask() => _client.get(_uri(path), headers: _headers);
    if (cache == null || !keep) {
      return _send(ask);
    }
    try {
      final response = await _checked(ask);
      final decoded = _decode(response);
      if (response.body.isNotEmpty) {
        try {
          await cache.write(path, utf8.decode(response.bodyBytes));
        } on Object {
          // a full or failing store must not break a read that worked
        }
      }
      cache.servedFrom.value = null;
      return decoded;
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.network || e.failure == ApiFailure.timeout) {
        final kept = cache.read(path);
        if (kept != null) {
          cache.servedFrom.value = kept.at;
          return jsonDecode(kept.body);
        }
      }
      rethrow;
    }
  }

  /// GET [path] and return the raw bytes (a picture).
  Future<Uint8List> getBytes(String path) async =>
      (await _checked(() => _client.get(_uri(path), headers: _headers)))
          .bodyBytes;

  /// POST one file to [path] as a multipart form, in the form field [field], and decode the JSON answer.
  Future<Object?> postFile(
    String path,
    String field,
    Uint8List bytes,
    String fileName, {
    Map<String, String> fields = const {},
  }) => sendFile('POST', path, field, bytes, fileName, fields: fields);

  /// Sends one file to [path] with [method] (POST or PUT) as a multipart form, in the form field [field], and
  /// decode the JSON answer.
  Future<Object?> sendFile(
    String method,
    String path,
    String field,
    Uint8List bytes,
    String fileName, {
    Map<String, String> fields = const {},
  }) => _send(() async {
    final req = http.MultipartRequest(method, _uri(path))
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(field, bytes, filename: fileName),
      );
    return http.Response.fromStream(await _client.send(req));
  });

  Future<Object?> _send(Future<http.Response> Function() request) async =>
      _decode(await _checked(request));

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        ApiFailure.badResponse,
        'the answer was not JSON',
        response.statusCode,
      );
    }
  }

  /// Makes the request and turns every way it can fail into an [ApiException]. A good answer is returned as is.
  Future<http.Response> _checked(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        ApiFailure.timeout,
        'the server did not answer in time',
      );
    } on SocketException catch (e) {
      throw ApiException(ApiFailure.network, e.message);
    } on HandshakeException catch (e) {
      throw ApiException(ApiFailure.network, e.message);
    } on http.ClientException catch (e) {
      throw ApiException(ApiFailure.network, e.message);
    }
    final status = response.statusCode;
    if (status == 403) {
      throw ApiException(ApiFailure.forbidden, _errorText(response), status);
    }
    if (status == 401) {
      throw ApiException(ApiFailure.unauthorised, _errorText(response), status);
    }
    if (status == 429) {
      throw ApiException(ApiFailure.rateLimited, _errorText(response), status);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(
        ApiFailure.server,
        _errorText(response),
        status,
        _bodyOf(response),
      );
    }
    return response;
  }

  Object? _bodyOf(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// The server's own words where it gave any: its errors are `{"error": "..."}`.
  String _errorText(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } on FormatException {
      // not JSON; fall through to the status line
    }
    return response.reasonPhrase ?? '';
  }

  void close() => _client.close();
}
