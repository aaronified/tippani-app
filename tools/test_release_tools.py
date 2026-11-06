"""Tests for the release tools. Run with: python3 -m unittest discover -s tools -p 'test_*.py'

What is pinned is every way a release could go out wrong without anything failing: a tag that does not match the
version the app reports (the update check would keep offering the update the phone already has), a version that
is not higher, an empty changelog, a half-written release, and a server's v-tag read as an app release.
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_release_version as check  # noqa: E402
import prepare_release as prep  # noqa: E402

TOOLS = Path(__file__).resolve().parent

PUBSPEC = "name: tippani\nversion: 0.1.0+3\nenvironment:\n  sdk: ^3.13.5\n"
VERSION_DART = "/// The version.\nconst appVersion = '0.1.0';\n\nconst releaseRepo = 'aaronified/tippani-app';\n"
CHANGELOG = """# Changelog

Intro words.

## [Unreleased]

### Added

- A new thing.
- Another.

## [0.1.0] - 2026-11-06

### Added

- The first.
"""


def tree(pubspec=PUBSPEC, version_dart=VERSION_DART, changelog=CHANGELOG) -> Path:
    root = Path(tempfile.mkdtemp())
    (root / "lib" / "harness").mkdir(parents=True)
    (root / "pubspec.yaml").write_text(pubspec, encoding="utf-8")
    (root / "lib" / "harness" / "version.dart").write_text(version_dart, encoding="utf-8")
    (root / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
    return root


class CheckReleaseVersion(unittest.TestCase):
    def test_agreeing_files_pass(self):
        self.assertIsNone(check.check("app-v0.1.0", PUBSPEC, VERSION_DART))

    def test_the_servers_v_tag_is_not_an_app_release(self):
        self.assertIn("not a version tag", check.check("v0.1.0", PUBSPEC, VERSION_DART))
        self.assertIn("not a version tag", check.check("app-v0.1", PUBSPEC, VERSION_DART))
        self.assertIn("not a version tag", check.check("app-v0.1.0-rc1", PUBSPEC, VERSION_DART))
        self.assertIn("not a version tag", check.check("very-old", PUBSPEC, VERSION_DART))

    def test_a_tag_ahead_of_either_file_fails_and_says_which_numbers(self):
        err = check.check("app-v0.2.0", PUBSPEC, VERSION_DART)
        self.assertIn("pubspec.yaml says 0.1.0", err)
        self.assertIn("version.dart says 0.1.0", err)
        self.assertIn("git push --delete origin app-v0.2.0", err)

    def test_pubspec_bumped_but_not_the_constant_fails(self):
        err = check.check("app-v0.2.0", "version: 0.2.0+4\n", VERSION_DART)
        self.assertIsNotNone(err)
        self.assertIn("version.dart says 0.1.0", err)

    def test_the_constant_bumped_but_not_pubspec_fails(self):
        self.assertIsNotNone(check.check("app-v0.2.0", PUBSPEC, "const appVersion = '0.2.0';\n"))

    def test_the_build_number_is_ignored(self):
        self.assertIsNone(check.check("app-v0.1.0", "version: 0.1.0+99\n", VERSION_DART))
        self.assertIsNone(check.check("app-v0.1.0", "version: '0.1.0'  # quoted\n", VERSION_DART))

    def test_a_missing_version_line_is_an_error_not_a_pass(self):
        self.assertIn("no top-level 'version:'", check.check("app-v0.1.0", "name: x\n", VERSION_DART))
        self.assertIn("no `const appVersion", check.check("app-v0.1.0", PUBSPEC, "// nothing\n"))

    def test_an_indented_version_is_not_the_top_level_one(self):
        self.assertIsNone(check.pubspec_version("dependencies:\n  version: 9.9.9\n"))


class PrepareRelease(unittest.TestCase):
    def test_it_bumps_all_three_files_and_dates_the_changelog(self):
        root = tree()
        prep.prepare(root, "0.2.0", "2026-12-01")
        self.assertIn("version: 0.2.0+4", (root / "pubspec.yaml").read_text())
        self.assertIn("const appVersion = '0.2.0';", (root / "lib/harness/version.dart").read_text())
        log = (root / "CHANGELOG.md").read_text()
        self.assertIn("## [Unreleased]\n\n## [0.2.0] - 2026-12-01\n\n### Added\n\n- A new thing.", log)
        self.assertIn("## [0.1.0] - 2026-11-06", log)
        self.assertEqual(log.count("## [Unreleased]"), 1)

    def test_the_other_lines_of_version_dart_are_left_alone(self):
        root = tree()
        prep.prepare(root, "0.2.0", "2026-12-01")
        self.assertIn("const releaseRepo = 'aaronified/tippani-app';", (root / "lib/harness/version.dart").read_text())

    def test_a_version_that_is_not_higher_changes_nothing(self):
        for bad in ("0.1.0", "0.0.9", "0.1.0"):
            root = tree()
            with self.assertRaises(prep.ReleaseError):
                prep.prepare(root, bad, "2026-12-01")
            self.assertEqual((root / "pubspec.yaml").read_text(), PUBSPEC)
            self.assertEqual((root / "CHANGELOG.md").read_text(), CHANGELOG)

    def test_a_malformed_version_changes_nothing(self):
        for bad in ("v0.2.0", "app-v0.2.0", "0.2", "0.2.0.1", "", "latest"):
            root = tree()
            with self.assertRaises(prep.ReleaseError, msg=bad):
                prep.prepare(root, bad, "2026-12-01")
            self.assertEqual((root / "pubspec.yaml").read_text(), PUBSPEC)

    def test_an_empty_unreleased_section_refuses_and_changes_nothing(self):
        empty = CHANGELOG.replace("### Added\n\n- A new thing.\n- Another.\n\n", "")
        root = tree(changelog=empty)
        with self.assertRaises(prep.ReleaseError) as ctx:
            prep.prepare(root, "0.2.0", "2026-12-01")
        self.assertIn("empty", str(ctx.exception))
        self.assertEqual((root / "pubspec.yaml").read_text(), PUBSPEC, "nothing is half-written")
        self.assertEqual((root / "lib/harness/version.dart").read_text(), VERSION_DART)

    def test_a_missing_changelog_heading_or_version_line_changes_nothing(self):
        for kwargs in ({"changelog": "# Changelog\n"}, {"pubspec": "name: x\n"}, {"version_dart": "// none\n"}):
            root = tree(**kwargs)
            before = {p.name: p.read_text() for p in (root / "pubspec.yaml", root / "CHANGELOG.md")}
            with self.assertRaises(prep.ReleaseError):
                prep.prepare(root, "0.2.0", "2026-12-01")
            self.assertEqual({p.name: p.read_text() for p in (root / "pubspec.yaml", root / "CHANGELOG.md")}, before)

    def test_it_works_when_unreleased_is_the_only_section(self):
        root = tree(changelog="# C\n\n## [Unreleased]\n\n- Only.\n")
        prep.prepare(root, "0.2.0", "2026-12-01")
        self.assertEqual((root / "CHANGELOG.md").read_text(), "# C\n\n## [Unreleased]\n\n## [0.2.0] - 2026-12-01\n\n- Only.\n")


class Notes(unittest.TestCase):
    def test_notes_are_the_versions_own_section_only(self):
        notes = prep.notes_for(CHANGELOG, "0.1.0")
        self.assertEqual(notes, "### Added\n\n- The first.\n")

    def test_unreleased_entries_are_not_in_a_released_versions_notes(self):
        self.assertNotIn("A new thing", prep.notes_for(CHANGELOG, "0.1.0"))

    def test_no_section_or_an_empty_one_is_an_error(self):
        with self.assertRaises(prep.ReleaseError):
            prep.notes_for(CHANGELOG, "9.9.9")
        with self.assertRaises(prep.ReleaseError):
            prep.notes_for("## [0.3.0] - x\n\n## [0.2.0] - y\n\n- z\n", "0.3.0")

    def test_the_dots_in_a_version_are_not_wildcards(self):
        with self.assertRaises(prep.ReleaseError):
            prep.notes_for("## [0x1x0] - d\n\n- a\n", "0.1.0")


class Commands(unittest.TestCase):
    """The scripts as the workflow runs them: exit status and the ::error:: line."""

    def run_tool(self, *args):
        return subprocess.run([sys.executable, *map(str, args)], capture_output=True, text=True)

    def test_check_exits_zero_and_one(self):
        root = tree()
        ok = self.run_tool(TOOLS / "check_release_version.py", "app-v0.1.0", "--root", root)
        self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
        bad = self.run_tool(TOOLS / "check_release_version.py", "app-v0.9.0", "--root", root)
        self.assertEqual(bad.returncode, 1)
        self.assertTrue(bad.stdout.startswith("::error::"))

    def test_check_with_no_arguments_is_a_usage_error(self):
        self.assertEqual(self.run_tool(TOOLS / "check_release_version.py").returncode, 2)

    def test_prepare_then_check_agree(self):
        root = tree()
        done = self.run_tool(TOOLS / "prepare_release.py", "0.3.0", "--root", root)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.run_tool(TOOLS / "check_release_version.py", "app-v0.3.0", "--root", root).returncode, 0)

    def test_notes_prints_the_section_for_the_workflow(self):
        root = tree()
        out = self.run_tool(TOOLS / "prepare_release.py", "--notes", "0.1.0", "--root", root)
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout, "### Added\n\n- The first.\n")
        missing = self.run_tool(TOOLS / "prepare_release.py", "--notes", "7.7.7", "--root", root)
        self.assertEqual(missing.returncode, 1)

    def test_the_real_repository_is_consistent_right_now(self):
        """The files in this repository agree with each other, so a tag for the current version would pass."""
        repo = TOOLS.parent
        pub = check.pubspec_version((repo / "pubspec.yaml").read_text(encoding="utf-8"))
        app = check.app_version((repo / "lib/harness/version.dart").read_text(encoding="utf-8"))
        self.assertIsNotNone(pub)
        self.assertEqual(pub, app)


if __name__ == "__main__":
    unittest.main()
