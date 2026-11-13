import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/offline_writes.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';

/// THE WIRE, NOT THE FAKE. The other tests answer through a mock whose close() does nothing, so a request closed
/// before it finishes would pass them. This one talks to a real HTTP server on loopback through the real client.
void main() {
  test('a queued write goes out over a real connection and is not cut off when the client is closed', () async {
    // flutter_test answers every real request with 400; this test is about the real wire
    HttpOverrides.global = null;
    final seen = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add('${req.method} ${req.uri.path} $body');
      // answer slowly: a client closed too early cuts this request off
      await Future<void>.delayed(const Duration(milliseconds: 150));
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{}');
      await req.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'server_url': 'http://127.0.0.1:${server.port}',
    });
    final settings = SettingsStore(
      await SharedPreferences.getInstance(),
      MemoryTokenVault(),
    );
    await settings.setToken('a-token');
    final controller = AppController(settings);
    await controller.load();
    expect(controller.paired, isTrue);
    final writes = OfflineWrites(controller, settings);

    final r = await writes.write('PUT', '/tags/1', const {
      'name': 'living',
    }, local: () async {});
    expect(r.sent, isTrue, reason: 'the server was up and answered');
    expect(seen.where((s) => s.startsWith('PUT /api/tags/1')), hasLength(1));
    expect(writes.pending.value, 0);
  });
}
