import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/admin/admin_service.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

void main() {
  late FakeServer server;
  late PairedAdminService admin;
  Map<String, Object?>? sent;
  String? uploaded;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    server = FakeServer();
    sent = null;
    uploaded = null;
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
      clientFactory: server.factory,
    );
    await controller.load();
    await controller.pair('ABCD2345', 'My phone');
    admin = PairedAdminService(controller);
    server.extra = (r, path) async {
      if (r.method == 'POST' && path == '/admin/restore/upload') {
        uploaded = r.body;
        return server.json({'ok': true});
      }
      if (r.method == 'POST' && path == '/admin/restore') {
        sent = jsonDecode(r.body) as Map<String, Object?>;
        return server.json({'ok': true});
      }
      return null;
    };
  });

  // A backup from before 1.4.1 carries no key, and the server refuses to restore one without
  // {"confirm": "RESTORE"} (a 400 that names it). A keyed one ignores the word.
  test(
    'a restore sends the word the server asks of an unsealed backup',
    () async {
      await admin.restoreKept();
      expect(sent, {'confirm': 'RESTORE'});
    },
  );

  test('a restore with a password sends the word as well', () async {
    await admin.restoreKept(password: 'hunter2');
    expect(sent, {'password': 'hunter2', 'confirm': 'RESTORE'});
  });

  test('an uploaded backup carries the word as a form field', () async {
    await admin.restoreUpload(Uint8List.fromList([1, 2, 3]), 'old.tippani');
    expect(uploaded, contains('name="confirm"'));
    expect(uploaded, contains('RESTORE'));
  });
}
