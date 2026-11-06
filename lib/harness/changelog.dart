import 'package:flutter/services.dart' show rootBundle;

import 'update_check.dart' show isNewer;

/// One version's entry in `CHANGELOG.md`: its heading, its date if it has one, and its bullets under
/// the section headings (Added, Changed, Fixed...).
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.sections,
  });

  /// `0.1.2`, or `Unreleased`.
  final String version;
  final String? date;

  /// Section heading to its bullets, in file order.
  final Map<String, List<String>> sections;

  bool get isUnreleased => version.toLowerCase() == 'unreleased';

  /// Every bullet, whatever its section.
  List<String> get bullets => [for (final b in sections.values) ...b];
}

final _versionHeading = RegExp(r'^##\s+\[([^\]]+)\](?:\s*-\s*(.+))?\s*$');
final _sectionHeading = RegExp(r'^###\s+(.+?)\s*$');

/// Reads a Keep a Changelog file. A line `## [x.y.z] - date` opens an entry, `### Added` opens a
/// section, `- text` opens a bullet and an indented line continues it. Anything before the first entry
/// is ignored.
List<ChangelogEntry> parseChangelog(String markdown) {
  final entries = <ChangelogEntry>[];
  String? version;
  String? date;
  var sections = <String, List<String>>{};
  String section = '';
  StringBuffer? bullet;

  void closeBullet() {
    if (bullet != null && version != null) {
      final text = bullet.toString().trim();
      if (text.isNotEmpty) sections.putIfAbsent(section, () => []).add(text);
    }
    bullet = null;
  }

  void closeEntry() {
    closeBullet();
    if (version != null) {
      entries.add(
        ChangelogEntry(version: version, date: date, sections: sections),
      );
    }
    sections = <String, List<String>>{};
    section = '';
  }

  for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final v = _versionHeading.firstMatch(raw);
    if (v != null) {
      closeEntry();
      version = v[1]!.trim();
      date = v[2]?.trim();
      continue;
    }
    if (version == null) continue;
    final s = _sectionHeading.firstMatch(raw);
    if (s != null) {
      closeBullet();
      section = s[1]!;
      continue;
    }
    if (raw.startsWith('- ') || raw.startsWith('* ')) {
      closeBullet();
      bullet = StringBuffer(raw.substring(2));
    } else if (bullet?.isNotEmpty ?? false) {
      // (flow analysis cannot promote `bullet` across the closures above, so it is asked through ?.)
      if (raw.startsWith(' ') && raw.trim().isNotEmpty) {
        bullet?.write(' ${raw.trim()}');
      } else if (raw.trim().isEmpty) {
        closeBullet();
      }
    } else if (raw.trim().isEmpty) {
      closeBullet();
    }
  }
  closeEntry();
  return entries;
}

/// The entry for [version], or null when the file has none.
ChangelogEntry? entryFor(List<ChangelogEntry> entries, String version) {
  for (final e in entries) {
    if (e.version == version) return e;
  }
  return null;
}

/// Reads the changelog bundled into the app (`CHANGELOG.md`, declared as an asset). Empty when it is not
/// there, so a missing asset is an empty screen and not a crash.
Future<List<ChangelogEntry>> loadChangelog() async {
  try {
    return parseChangelog(await rootBundle.loadString('CHANGELOG.md'));
  } catch (_) {
    return const [];
  }
}

/// Whether this start should show what is new, and the entry to show.
///
/// A first install has no earlier version, so it shows nothing: "what is new" is a question about an
/// update. Going back to an older build shows nothing either. The caller records [current] as seen
/// whether or not anything is shown, so the dialog appears once per update.
ChangelogEntry? whatsNew({
  required String? lastSeen,
  required String current,
  required List<ChangelogEntry> entries,
}) {
  if (lastSeen == null || lastSeen == current) return null;
  if (!isNewer(current, lastSeen)) return null;
  final entry = entryFor(entries, current);
  if (entry == null || entry.bullets.isEmpty) return null;
  return entry;
}
