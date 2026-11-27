import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/imports/quote_markdown.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

/// A file sent to the import queue, once: the client against a server that names a batch after its file, polls a job
/// and lists its batches as the real one does. A retry that would queue the same bookmark twice is what this stops.
void main() {
  Future<(PairedImportService, FakeServer)> rig() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://q.example.org',
    });
    final server = FakeServer();
    final controller = AppController(
      SettingsStore(await SharedPreferences.getInstance(), MemoryTokenVault()),
      clientFactory: server.factory,
    );
    await controller.load();
    await controller.pair('ABCD2345', 'Phone');
    return (PairedImportService(controller, poll: Duration.zero), server);
  }

  final file = bookQuoteMarkdown(
    title: 'Dust of Dreams',
    author: 'Steven Erikson',
    text: 'Tavore said nothing.',
    location: '3:42:10',
  );

  test(
    'a file goes up once, named as asked, read as Tippani Markdown',
    () async {
      final (svc, server) = await rig();
      expect(await svc.queueOnce('bookmark-3f9a.md', file), isTrue);

      final up = server.importUploads.single;
      expect(up.name, 'bookmark-3f9a.md');
      expect(up.as, 'md', reason: 'the app says markdown, the server says md');
      expect(up.text, contains('> Tavore said nothing.'));
      expect(up.text, contains('- location: 3:42:10'));
    },
  );

  test(
    'the same name again sends nothing, and a different one goes up',
    () async {
      final (svc, server) = await rig();
      expect(await svc.queueOnce('bookmark-3f9a.md', file), isTrue);
      expect(await svc.queueOnce('bookmark-3f9a.md', file), isFalse);
      expect(server.importUploads, hasLength(1));

      expect(await svc.queueOnce('bookmark-b210.md', file), isTrue);
      expect(server.importUploads.map((u) => u.name), [
        'bookmark-3f9a.md',
        'bookmark-b210.md',
      ]);
    },
  );

  test(
    'a server that cannot be reached is said, and nothing is marked sent',
    () async {
      final (svc, server) = await rig();
      server.unreachable = true;
      await expectLater(
        svc.queueOnce('bookmark-3f9a.md', file),
        throwsA(isA<ServerException>()),
      );
      server.unreachable = false;
      expect(await svc.queueOnce('bookmark-3f9a.md', file), isTrue);
    },
  );
}
