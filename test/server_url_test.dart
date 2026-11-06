import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/settings/server_url.dart';

void main() {
  group('normaliseServerUrl', () {
    test('a bare host or host:port takes https', () {
      expect(
        normaliseServerUrl('quotes.example.org'),
        'https://quotes.example.org',
      );
      expect(
        normaliseServerUrl('192.168.1.20:8124'),
        'https://192.168.1.20:8124',
      );
    });

    test('keeps the scheme the reader typed', () {
      expect(
        normaliseServerUrl('http://192.168.1.20:8124'),
        'http://192.168.1.20:8124',
      );
    });

    test('drops a trailing slash and a trailing /api, and trims', () {
      expect(
        normaliseServerUrl('  https://q.example.org/  '),
        'https://q.example.org',
      );
      expect(
        normaliseServerUrl('https://q.example.org/api'),
        'https://q.example.org',
      );
      expect(
        normaliseServerUrl('https://q.example.org/api/'),
        'https://q.example.org',
      );
    });

    test('keeps a path the server is mounted under', () {
      expect(
        normaliseServerUrl('https://example.org/tippani/'),
        'https://example.org/tippani',
      );
      expect(
        normaliseServerUrl('https://example.org/tippani/api'),
        'https://example.org/tippani',
      );
    });

    test('refuses what cannot be an address', () {
      expect(normaliseServerUrl(''), isNull);
      expect(normaliseServerUrl('   '), isNull);
      expect(normaliseServerUrl('ftp://example.org'), isNull);
      expect(normaliseServerUrl('https://'), isNull);
    });
  });

  test('apiBaseOf adds /api to the stored origin', () {
    expect(
      apiBaseOf('https://q.example.org').toString(),
      'https://q.example.org/api',
    );
    expect(
      apiBaseOf('https://example.org/tippani').toString(),
      'https://example.org/tippani/api',
    );
  });

  group('isRiskyCleartext', () {
    test('https is never risky', () {
      expect(isRiskyCleartext('https://203.0.113.9'), isFalse);
    });

    test('plain http on this device or a private network is not risky', () {
      for (final u in [
        'http://localhost:8124',
        'http://10.0.2.2:8124',
        'http://192.168.1.20:8124',
        'http://10.1.2.3',
        'http://172.16.0.5',
        'http://172.31.255.1',
        'http://100.100.1.1',
        'http://nas.local',
      ]) {
        expect(isRiskyCleartext(u), isFalse, reason: u);
      }
    });

    test('plain http to anywhere else is risky', () {
      for (final u in [
        'http://203.0.113.9',
        'http://quotes.example.org',
        'http://172.32.0.1',
        'http://100.128.0.1',
      ]) {
        expect(isRiskyCleartext(u), isTrue, reason: u);
      }
    });
  });
}
