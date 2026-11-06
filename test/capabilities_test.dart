import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/api/capabilities.dart';

Capabilities caps({
  int revision = 8,
  int minClient = 1,
  Set<String> features = const {},
}) => Capabilities(
  version: '3.6.2',
  apiRevision: revision,
  minClientRevision: minClient,
  features: features,
);

void main() {
  group('Capabilities.fromJson', () {
    test('reads the server answer', () {
      final c = Capabilities.fromJson({
        'version': '3.6.2',
        'api_revision': 8,
        'min_client_revision': 1,
        'features': ['device-tokens', 'trash-bin'],
      })!;
      expect(c.version, '3.6.2');
      expect(c.apiRevision, 8);
      expect(c.has('trash-bin'), isTrue);
      expect(c.has('nope'), isFalse);
    });

    test('anything that is not a capabilities answer is null, not a crash', () {
      expect(Capabilities.fromJson(null), isNull);
      expect(Capabilities.fromJson('<html></html>'), isNull);
      expect(Capabilities.fromJson([1, 2]), isNull);
      expect(Capabilities.fromJson({'version': '1'}), isNull);
      expect(Capabilities.fromJson({'api_revision': '8'}), isNull);
    });

    test('a missing min_client_revision means any client, and bad features are ignored', () {
      final c = Capabilities.fromJson({
        'api_revision': 3,
        'features': ['a', 1, null, 'b'],
      })!;
      expect(c.minClientRevision, 1);
      expect(c.features, {'a', 'b'});
    });
  });

  group('compatibilityOf', () {
    test('a server inside the range is ok', () {
      expect(compatibilityOf(caps(revision: 8)), Compatibility.ok);
      expect(
        compatibilityOf(caps(revision: 12)),
        Compatibility.ok,
        reason: 'a newer server is fine until it says otherwise',
      );
    });

    test('a server older than the app needs is called too old', () {
      expect(
        compatibilityOf(caps(revision: 2), minServer: 5),
        Compatibility.serverTooOld,
      );
    });

    test('a server that has moved past this build says the app is too old', () {
      expect(
        compatibilityOf(caps(revision: 20, minClient: 10), builtFor: 8),
        Compatibility.appTooOld,
      );
    });

    test('the boundaries are inclusive', () {
      expect(
        compatibilityOf(caps(revision: 5), minServer: 5),
        Compatibility.ok,
      );
      expect(
        compatibilityOf(caps(revision: 20, minClient: 8), builtFor: 8),
        Compatibility.ok,
      );
    });
  });
}
