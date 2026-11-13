---
name: tippani-app-gate
description: Pre-commit gate for the Tippani Android app (Flutter) — format, analyze, test, release-tool and wiki checks, changelog rules. Use before every commit or push in this repo; replaces the generic claude-kit pre-commit-gate stages with this repo's commands.
---

# Tippani app pre-commit gate

Base: the kit's `pre-commit-gate`. CI (`.github/workflows/ci.yml`) is the authority; the gate runs the same steps in the same order.

| # | Stage | Command |
|---|---|---|
| 0 | Sync | `git fetch`; stay on the session branch; `python3 <kit>/skills/git-sync/scripts/kit_guard.py --staged` exits 0 |
| 1 | Tools + wiki | `python3 -m unittest discover -s tools -p 'test_*.py'`, `python3 tools/check_wiki.py` |
| 2 | Format | `dart format --output=none --set-exit-if-changed lib test` |
| 3 | Analyze | `flutter analyze` |
| 4 | Test | `flutter test` (no device, no network; HTTP client is faked) |
| 5 | Build | `flutter build apk --debug` when native/Gradle/pubspec changed |
| 6 | Docs | same commit: `CHANGELOG.md` under `## [Unreleased]`, ADR page + `ADR-Index.md` for a decision, `Developing.md`/`Plan.md` if layout or behaviour changed |
| 7 | Rate | `tippani-app-rate` |
| 8 | Commit | Conventional Commits, subject what / body why + rejected alternative |

**Flutter may be absent in a cloud container** (`which flutter`). Then run only stages 0 and 1, say plainly that
format, analyze and test did not run, and leave them to CI; never report GREEN for them.

## Rules

- Never delete, skip, loosen or `--no-verify` to reach green; a wrong test is a question to the owner.
- Changelog entries are for the person using the app, in plain words, each starting with a **short title and a colon**
  ("Sync conflicts has its own place: …") — the app shows only the title. `changelog_headers_test.dart` and `changelog_test.dart` enforce the form.
- `appVersion` must equal `pubspec.yaml`; never edit the version by hand — the Release workflow does it.
- The device token is never in a backup, log or changelog; logs record counts and ids, never titles or quote words.
- Server-side needs are filed as issues on aaronified/tippani, not worked around here; if the server's routes change, the fake in `test/support/fake_server.dart` changes with them.
- Android only, Tabler icons only, Material You only (ADR-0001/0005).
- Screens are tested against `test/support/memory_library.dart`; the store against real SQLite (`library_store_test.dart`).
- A subagent's finding is a lead: verify at its line. Retrieval and fan-out run on `haiku`.

End with exactly one of **GREEN** (sha), **BLOCKED** (yes/no question), **DIRTY-STOP**.
