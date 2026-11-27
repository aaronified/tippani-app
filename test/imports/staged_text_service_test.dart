import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/api/capabilities.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/imports/import_service.dart';
import 'package:tippani/settings/settings_store.dart';

import '../support/fake_server.dart';

/// The words of a waiting quote, changed through the paired server: the client's request against a server that answers
/// as the real one does. A screen test cannot catch a request the server would refuse, and this one can.
void main() {
  Capabilities caps(Set<String> features) => Capabilities(
    version: '3.9.1',
    apiRevision: 13,
    minClientRevision: 1,
    features: features,
  );

  Future<(PairedImportService, FakeServer, AppController)> rig() async {
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
    return (PairedImportService(controller), server, controller);
  }

  test(
    'the words are offered only when the server names the feature',
    () async {
      final (svc, _, controller) = await rig();
      expect(svc.canEditText, isFalse, reason: 'not asked yet');
      await controller.connect(
        'https://q.example.org',
        ServerCheck.answered(caps({'trash-bin'})),
      );
      expect(svc.canEditText, isFalse);
      await controller.connect(
        'https://q.example.org',
        ServerCheck.answered(caps({'staged-text-edit'})),
      );
      expect(svc.canEditText, isTrue);
    },
  );

  test(
    'new words reach the waiting quote, and a field not sent is left alone',
    () async {
      final (svc, server, _) = await rig();
      await svc.editText(
        7,
        const StagedTextEdit(quote: '  It was the best.  '),
      );

      expect(server.stagedWords[7]!['quote'], 'It was the best.');
      expect(server.stagedWords[7]!['note'], '');
      final sent = server.requests.last;
      expect(sent.method, 'PATCH');
      expect(sent.url.path, endsWith('/import/staged/quotes/7'));
      expect(sent.body, '{"quote":"  It was the best.  "}');
    },
  );

  test('a note is added without touching the quote', () async {
    final (svc, server, _) = await rig();
    await svc.editText(7, const StagedTextEdit(note: 'from a bookmark'));
    expect(server.stagedWords[7]!['quote'], 'It was the best of times.');
    expect(server.stagedWords[7]!['note'], 'from a bookmark');
  });

  test('words equal to another waiting quote\'s are refused with the server\'s sentence', () async {
    final (svc, server, _) = await rig();
    await expectLater(
      svc.editText(
        7,
        const StagedTextEdit(quote: 'it was the WORST of times.'),
      ),
      throwsA(
        isA<ServerException>().having(
          (e) => e.message,
          'message',
          contains('already has those words'),
        ),
      ),
    );
    expect(server.stagedWords[7]!['quote'], 'It was the best of times.');
  });

  test(
    'a quote left with no words, and a quote that is not there, are refused',
    () async {
      final (svc, server, _) = await rig();
      await expectLater(
        svc.editText(7, const StagedTextEdit(quote: '  ')),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        svc.editText(99, const StagedTextEdit(quote: 'x')),
        throwsA(isA<ServerException>()),
      );
      expect(server.stagedWords[7]!['quote'], 'It was the best of times.');
    },
  );
}
