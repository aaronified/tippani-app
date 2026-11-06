import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'capabilities.dart';

enum ApiFailure {
  /// Nothing answered: no route to the host, a refused connection, a bad certificate.
  network,

  /// Something answered too slowly.
  timeout,

  /// The server refused the credential (401 or 403). A revoked device token looks like this.
  unauthorised,

  /// The server answered with an error of its own.
  server,

  /// Something answered, but not in a shape this app reads.
  badResponse,
}

class ApiException implements Exception {
  const ApiException(this.failure, [this.detail = '', this.status]);

  final ApiFailure failure;
  final String detail;
  final int? status;

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

  Uri _uri(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return base.replace(
      path: '${base.path.endsWith('/') ? base.path : '${base.path}/'}$clean',
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

  /// GET [path] and decode the JSON answer.
  Future<Object?> getJson(String path) =>
      _send(() => _client.get(_uri(path), headers: _headers));

  Future<Object?> _send(Future<http.Response> Function() request) async {
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
    if (status == 401 || status == 403) {
      throw ApiException(ApiFailure.unauthorised, _errorText(response), status);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(ApiFailure.server, _errorText(response), status);
    }
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        ApiFailure.badResponse,
        'the answer was not JSON',
        status,
      );
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
