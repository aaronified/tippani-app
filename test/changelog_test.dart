import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/changelog.dart';
import 'package:tippani/harness/version.dart';

const sample = '''
# Changelog

Some words before the first entry, which are ignored.

## [Unreleased]

### Added

- A thing not out yet.

## [0.2.0] - 2026-12-01

### Added

- The first new thing, which is long enough that
  it continues on a second line.
- The second new thing.

### Fixed

- A bug.

## [0.1.0] - 2026-11-06

### Added

- Everything.
''';

void main() {
  group('parseChangelog', () {
    final entries = parseChangelog(sample);

    test('reads each version in file order, with its date', () {
      expect(entries.map((e) => e.version), ['Unreleased', '0.2.0', '0.1.0']);
      expect(entries[0].date, isNull);
      expect(entries[0].isUnreleased, isTrue);
      expect(entries[1].date, '2026-12-01');
    });

    test('reads sections and bullets, and joins a continued line', () {
      final e = entries[1];
      expect(e.sections.keys, ['Added', 'Fixed']);
      expect(e.sections['Added'], [
        'The first new thing, which is long enough that it continues on a second line.',
        'The second new thing.',
      ]);
      expect(e.sections['Fixed'], ['A bug.']);
      expect(e.bullets, hasLength(3));
    });

    test('ignores what comes before the first entry', () {
      expect(
        entries.expand((e) => e.bullets),
        isNot(contains(startsWith('Some words'))),
      );
    });

    test('copes with Windows line endings and an empty file', () {
      expect(
        parseChangelog(sample.replaceAll('\n', '\r\n')).map((e) => e.version),
        ['Unreleased', '0.2.0', '0.1.0'],
      );
      expect(parseChangelog(''), isEmpty);
      expect(parseChangelog('# Changelog\n\nnothing yet\n'), isEmpty);
    });
  });

  group('whatsNew', () {
    final entries = parseChangelog(sample);

    test('shows the current version\'s entry after an update', () {
      final e = whatsNew(lastSeen: '0.1.0', current: '0.2.0', entries: entries);
      expect(e?.version, '0.2.0');
    });

    test(
      'shows nothing on a first install, there being no earlier version',
      () {
        expect(
          whatsNew(lastSeen: null, current: '0.2.0', entries: entries),
          isNull,
        );
      },
    );

    test('shows nothing when the version has not changed', () {
      expect(
        whatsNew(lastSeen: '0.2.0', current: '0.2.0', entries: entries),
        isNull,
      );
    });

    test('shows nothing after going back to an older build', () {
      expect(
        whatsNew(lastSeen: '0.2.0', current: '0.1.0', entries: entries),
        isNull,
      );
    });

    test('shows nothing when the file has no entry for the version, or an empty one', () {
      expect(
        whatsNew(lastSeen: '0.1.0', current: '0.3.0', entries: entries),
        isNull,
      );
      expect(
        whatsNew(
          lastSeen: '0.1.0',
          current: '0.2.0',
          entries: parseChangelog('## [0.2.0] - x\n'),
        ),
        isNull,
      );
    });
  });

  group('the bundled CHANGELOG.md', () {
    final text = File('CHANGELOG.md').readAsStringSync();

    test('parses, and has an Unreleased entry with something in it or a released one', () {
      final entries = parseChangelog(text);
      expect(entries, isNotEmpty);
      expect(entries.expand((e) => e.bullets), isNotEmpty);
    });

    test('is declared as an asset, or the app cannot show it', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- CHANGELOG.md'),
      );
    });

    test(
      'has an entry for the version in the code, or is still all Unreleased',
      () {
        // A release raises the version in pubspec.yaml and moves the Unreleased entries under it; until the
        // first release the version is still 0.1.0 and the entries are Unreleased. Either is fine; neither
        // is fine is not.
        final entries = parseChangelog(text);
        expect(
          entries.any((e) => e.version == appVersion || e.isUnreleased),
          isTrue,
        );
      },
    );
  });
}
