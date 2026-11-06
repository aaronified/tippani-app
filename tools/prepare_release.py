#!/usr/bin/env python3
"""Prepare a release: bump the version files and date the changelog.

Usage:
    python3 tools/prepare_release.py 0.2.0           # in the repository root
    python3 tools/prepare_release.py 0.2.0 --root path/to/copy
    python3 tools/prepare_release.py --notes 0.2.0   # print that version's notes

Exit status: 0 on success, 1 when the release cannot be prepared (nothing is written then), 2 if the arguments
are wrong.

What it changes, all or nothing:
  - pubspec.yaml: `version:` becomes X.Y.Z+<current build number + 1>.
  - lib/harness/version.dart: `const appVersion` becomes 'X.Y.Z'.
  - CHANGELOG.md: the body of `## [Unreleased]` moves under a new `## [X.Y.Z] - <today, UTC>` heading, and
    `## [Unreleased]` is left empty above it.
With --notes it changes nothing and prints the body of `## [X.Y.Z]` from CHANGELOG.md: the release workflow publishes
that as the release's notes, so the changelog is the one list of what changed.
It then runs the same check as tools/check_release_version.py. It refuses an empty Unreleased section and a version
that is not higher than the current one. The release workflow runs it (.github/workflows/release.yml) and commits
the result, so no release pull request is opened by hand.

Requires only the Python standard library.
"""

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_release_version  # noqa: E402

VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
PUBSPEC_LINE = re.compile(
    r"""^version:[ \t]*(?P<q>["']?)(?P<name>\d+\.\d+\.\d+)(?:\+(?P<build>\d+))?(?P=q)[ \t]*(?:#.*)?$""",
    re.MULTILINE,
)
APP_VERSION_LINE = re.compile(r"^(const appVersion = ')[^']*(';)", re.MULTILINE)
UNRELEASED = "## [Unreleased]"
HEADING = re.compile(r"^## \[", re.MULTILINE)


class ReleaseError(Exception):
    """A release that cannot be prepared; the message says why."""


def parse(version: str) -> tuple[int, int, int]:
    match = VERSION.match(version)
    if not match:
        raise ReleaseError(f"'{version}' is not a version like 0.2.0.")
    major, minor, patch = (int(part) for part in match.groups())
    return major, minor, patch


def bump_pubspec(text: str, version: str) -> str:
    match = PUBSPEC_LINE.search(text)
    if not match:
        raise ReleaseError("pubspec.yaml has no top-level 'version: X.Y.Z+N' line.")
    if parse(version) <= parse(match.group("name")):
        raise ReleaseError(
            f"The new version {version} is not higher than the current version {match.group('name')}."
        )
    build = int(match.group("build") or 0) + 1
    return text[: match.start()] + f"version: {version}+{build}" + text[match.end():]


def bump_app_version(text: str, version: str) -> str:
    new, count = APP_VERSION_LINE.subn(lambda m: f"{m.group(1)}{version}{m.group(2)}", text)
    if count != 1:
        raise ReleaseError("lib/harness/version.dart has no single `const appVersion = '...';` line.")
    return new


def move_unreleased(text: str, version: str, today: str) -> str:
    start = text.find(UNRELEASED)
    if start < 0:
        raise ReleaseError(f"CHANGELOG.md has no '{UNRELEASED}' heading.")
    body_start = start + len(UNRELEASED)
    following = HEADING.search(text, body_start)
    body_end = following.start() if following else len(text)
    body = text[body_start:body_end].strip()
    if not body:
        raise ReleaseError(
            "CHANGELOG.md's '## [Unreleased]' section is empty. Each pull request adds its line there; "
            "there is nothing to release."
        )
    rest = text[body_end:]
    new = f"{text[:body_start]}\n\n## [{version}] - {today}\n\n{body}\n"
    if rest:
        new += "\n" + rest
    return new


def notes_for(text: str, version: str) -> str:
    """The body of `## [version] - <date>` in CHANGELOG.md: the release notes."""
    parse(version)
    start = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n", text, re.MULTILINE)
    if not start:
        raise ReleaseError(f"CHANGELOG.md has no section for {version}.")
    following = HEADING.search(text, start.end())
    body = text[start.end() : following.start() if following else len(text)].strip()
    if not body:
        raise ReleaseError(f"CHANGELOG.md's section for {version} is empty.")
    return body + "\n"


def prepare(root: Path, version: str, today: str) -> None:
    parse(version)
    files = {
        "pubspec": root / "pubspec.yaml",
        "version_dart": root / "lib" / "harness" / "version.dart",
        "changelog": root / "CHANGELOG.md",
    }
    try:
        texts = {k: p.read_text(encoding="utf-8") for k, p in files.items()}
    except OSError as error:
        raise ReleaseError(f"Cannot read {error.filename}: {error.strerror}.")
    new = {
        "pubspec": bump_pubspec(texts["pubspec"], version),
        "version_dart": bump_app_version(texts["version_dart"], version),
        "changelog": move_unreleased(texts["changelog"], version, today),
    }
    error = check_release_version.check(f"app-v{version}", new["pubspec"], new["version_dart"])
    if error:
        raise ReleaseError(error)
    for key, path in files.items():
        path.write_text(new[key], encoding="utf-8", newline="")


def main(argv: list[str]) -> int:
    args = argv[1:]
    root = Path(".")
    if len(args) >= 2 and args[-2] == "--root":
        root = Path(args[-1])
        args = args[:-2]
    if len(args) == 2 and args[0] == "--notes":
        try:
            changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
            print(notes_for(changelog, args[1]), end="")
        except (ReleaseError, OSError) as error:
            print(f"::error::{error}")
            return 1
        return 0
    if len(args) != 1:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    try:
        prepare(root, args[0], today)
    except ReleaseError as error:
        print(f"::error::{error}")
        return 1
    print(f"Prepared release {args[0]}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
