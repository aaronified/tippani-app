import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tippani/harness/update_check.dart';
import 'package:tippani/harness/version.dart';

const sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> release({
  String tag = 'app-v0.2.0',
  List<Map<String, Object?>>? assets,
  String body = 'Fixes.',
}) => {
  'tag_name': tag,
  'body': body,
  'assets':
      assets ??
      [
        {
          'name': 'tippani-app-v0.2.0.apk',
          'browser_download_url': 'https://github.com/aaronified/tippani-app/releases/download/app-v0.2.0/tippani-app-v0.2.0.apk',
          'digest': 'sha256:$sha',
        },
      ],
};

void main() {
  group('versions', () {
    test('the app version in the code is the one in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*([0-9.]+)\+',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(m, isNotNull);
      expect(
        appVersion,
        m![1],
        reason: 'raise both together, or the update check compares against the wrong number',
      );
    });

    test('parseVersion reads tags with and without their prefix', () {
      expect(parseVersion('app-v0.1.2'), [0, 1, 2]);
      expect(parseVersion('v1.2'), [1, 2]);
      expect(parseVersion('3.4.5'), [3, 4, 5]);
      expect(parseVersion(' 1.0 '), [1, 0]);
      expect(parseVersion(''), isNull);
      expect(parseVersion('app-v'), isNull);
      expect(parseVersion('1.x'), isNull);
      expect(parseVersion('1.-2'), isNull);
    });

    test(
      'isNewer compares number by number, with a missing number as zero',
      () {
        expect(isNewer('0.2.0', '0.1.9'), isTrue);
        expect(isNewer('0.10.0', '0.9.0'), isTrue, reason: 'numbers, not text');
        expect(isNewer('1.0', '0.9.9'), isTrue);
        expect(isNewer('1.0.0', '1.0'), isFalse);
        expect(isNewer('0.1.0', '0.1.0'), isFalse);
        expect(isNewer('0.1.0', '0.2.0'), isFalse);
        expect(isNewer('nonsense', '0.1.0'), isFalse);
        expect(isNewer('0.2.0', 'nonsense'), isFalse);
      },
    );
  });

  group('readRelease', () {
    test(
      'a newer release with its APK is an update, with the digest and notes',
      () {
        final r = readRelease(release(), have: '0.1.0');
        expect(r, isA<UpdateAvailable>());
        final info = (r as UpdateAvailable).release;
        expect(info.version, '0.2.0');
        expect(info.apkName, 'tippani-app-v0.2.0.apk');
        expect(
          info.apkUrl,
          startsWith(
            'https://github.com/aaronified/tippani-app/releases/download/',
          ),
        );
        expect(info.sha256, sha);
        expect(info.notes, 'Fixes.');
      },
    );

    test('the same or an older release is up to date', () {
      expect(readRelease(release(), have: '0.2.0'), isA<UpToDate>());
      expect(readRelease(release(), have: '0.3.0'), isA<UpToDate>());
    });

    test('a release whose APK is not uploaded yet reads as up to date, not as a download of a 404', () {
      expect(readRelease(release(assets: []), have: '0.1.0'), isA<UpToDate>());
      expect(
        readRelease(
          release(
            assets: [
              {
                'name': 'notes.txt',
                'browser_download_url': 'https://example.org/notes.txt',
              },
            ],
          ),
          have: '0.1.0',
        ),
        isA<UpToDate>(),
      );
    });

    test('an APK of some other project is not taken', () {
      expect(
        readRelease(
          release(
            assets: [
              {
                'name': 'lexodle-v9.apk',
                'browser_download_url': 'https://example.org/lexodle.apk',
              },
            ],
          ),
          have: '0.1.0',
        ),
        isA<UpToDate>(),
      );
    });

    test('a digest that is not a SHA-256 is dropped rather than trusted', () {
      final r = readRelease(
        release(
          assets: [
            {
              'name': 'tippani-app-v0.2.0.apk',
              'browser_download_url': 'https://example.org/a.apk',
              'digest': 'md5:abc',
            },
          ],
        ),
        have: '0.1.0',
      );
      expect((r as UpdateAvailable).release.sha256, isNull);
    });

    test('a tag that is not an app release is a bad reply (the server\'s tags are not ours)', () {
      expect(
        readRelease(release(tag: 'v3.6.2'), have: '0.1.0'),
        isA<CheckFailed>(),
      );
      expect(
        readRelease(release(tag: 'nightly'), have: '0.1.0'),
        isA<CheckFailed>(),
      );
      expect(readRelease('x', have: '0.1.0'), isA<CheckFailed>());
      expect(
        readRelease(<String, Object?>{}, have: '0.1.0'),
        isA<CheckFailed>(),
      );
    });
  });

  group('GitHubReleaseCheck', () {
    GitHubReleaseCheck checker(
      MockClientHandler h, {
      Duration timeout = const Duration(seconds: 5),
    }) => GitHubReleaseCheck(client: MockClient(h), timeout: timeout);

    test('asks the releases API of this repository', () async {
      late Uri seen;
      late Map<String, String> headers;
      final c = checker((r) async {
        seen = r.url;
        headers = r.headers;
        return http.Response(jsonEncode(release(tag: 'app-v$appVersion')), 200);
      });
      expect(await c.check(), isA<UpToDate>());
      expect(
        seen.toString(),
        'https://api.github.com/repos/$releaseRepo/releases/latest',
      );
      expect(headers['User-Agent'], 'tippani-app/$appVersion');
      expect(
        headers.containsKey('Authorization'),
        isFalse,
        reason: 'no account, no credential',
      );
    });

    test('403 and 429 are GitHub\'s rate limit', () async {
      for (final status in [403, 429]) {
        final r = await checker((_) async => http.Response('{}', status))
            .check();
        expect((r as CheckFailed).why, CheckFailure.rateLimited);
      }
    });

    test('other statuses and unreadable bodies are a bad reply', () async {
      expect(
        ((await checker((_) async => http.Response('{}', 404)).check())
                as CheckFailed)
            .why,
        CheckFailure.badReply,
      );
      expect(
        ((await checker((_) async => http.Response('<html>', 200)).check())
                as CheckFailed)
            .why,
        CheckFailure.badReply,
      );
    });

    test('no network and no answer are offline', () async {
      expect(
        ((await checker((_) async => throw const SocketException('down'))
                    .check())
                as CheckFailed)
            .why,
        CheckFailure.offline,
      );
      final slow = checker(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 30),
      );
      expect(((await slow.check()) as CheckFailed).why, CheckFailure.offline);
    });
  });
}
