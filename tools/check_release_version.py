#!/usr/bin/env python3
"""Fail if a release tag, pubspec.yaml and the app's own version constant disagree.

Usage:
    python3 tools/check_release_version.py app-v0.2.0        # reads the two files in the repository root
    python3 tools/check_release_version.py app-v0.2.0 --root path/to/copy

Exit status: 0 when they agree, 1 when they differ or a version cannot be read, 2 if the arguments are wrong.

The release workflow builds with `--build-name` taken from the tag, so the APK's versionName is the tag. The app
itself reports `appVersion` (lib/harness/version.dart), and the update check compares that with the newest release.
Tagging a commit whose version files were not bumped publishes an APK that calls itself the previous version, and
the update check then keeps offering the update the phone already has. The workflow runs this before it builds
anything.

Only the version name is compared: pubspec.yaml's `+build` part is ignored, because the workflow sets the build
number from its run number.

Requires only the Python standard library, so it runs before anything is installed.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# A release of the app is tagged app-vX.Y.Z so it is never mistaken for one of the server's v-tags.
TAG = re.compile(r"^app-v(\d+\.\d+\.\d+)$")
# A top-level `version:` line, its value optionally quoted, then an optional trailing comment.
VERSION_LINE = re.compile(r"""^version:[ \t]*(?P<q>["']?)(?P<value>[^"'#\s]+)(?P=q)[ \t]*(?:#.*)?$""")
# `const appVersion = '0.1.0';`
APP_VERSION_LINE = re.compile(r"""^const appVersion = '(?P<value>[^']*)';""", re.MULTILINE)


def pubspec_version(text: str) -> str | None:
    """The version name in a pubspec's text, without `+build`, or None."""
    for line in text.splitlines():
        match = VERSION_LINE.match(line.rstrip("\r"))
        if match:
            return match.group("value").split("+", 1)[0]
    return None


def app_version(text: str) -> str | None:
    """The value of `const appVersion` in lib/harness/version.dart's text, or None."""
    match = APP_VERSION_LINE.search(text)
    return match.group("value") if match else None


def check(tag: str, pubspec_text: str, version_dart_text: str) -> str | None:
    """None when the tag names both files' version, else the error to show."""
    tag_match = TAG.match(tag)
    if not tag_match:
        return f"'{tag}' is not a version tag like app-v0.2.0."
    want = tag_match.group(1)
    pub = pubspec_version(pubspec_text)
    if pub is None:
        return "pubspec.yaml has no top-level 'version:' line to compare the tag with."
    app = app_version(version_dart_text)
    if app is None:
        return "lib/harness/version.dart has no `const appVersion = '...';` line to compare the tag with."
    if pub != want or app != want:
        return (
            f"The tag {tag} does not match the version files: pubspec.yaml says {pub} and "
            f"lib/harness/version.dart says {app}. Bump both to {want}, commit, and tag that commit instead "
            f"(delete this tag first: git push --delete origin {tag} && git tag -d {tag})."
        )
    return None


def main(argv: list[str]) -> int:
    args = argv[1:]
    root = Path(".")
    if len(args) == 3 and args[1] == "--root":
        root = Path(args[2])
        args = args[:1]
    if len(args) != 1:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    try:
        pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
        version_dart = (root / "lib" / "harness" / "version.dart").read_text(encoding="utf-8")
    except OSError as error:
        print(f"::error::Cannot read {error.filename}: {error.strerror}.")
        return 1
    error = check(args[0], pubspec, version_dart)
    if error:
        print(f"::error::{error}")
        return 1
    print(f"{args[0]} matches pubspec.yaml and lib/harness/version.dart.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
