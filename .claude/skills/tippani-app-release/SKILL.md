---
name: tippani-app-release
description: Prepare and cut a Tippani app release (app-vX.Y.Z) via the Release workflow and tools/prepare_release.py. Use only when the owner asks to release; runs on sonnet.
---

# Tippani app release

Changelog writing and the release are a **`sonnet`** agent's job; a higher-model session delegates and reviews. Base: kit `changelog-release`.

Facts (docs/wiki/Releasing.md, ADR-0008, ADR-0013):
- Tags are `app-vX.Y.Z`; the APK is `tippani-app-vX.Y.Z.apk`. The update check reads exactly those names.
- Never edit the version by hand. The Release workflow runs `tools/prepare_release.py X.Y.Z` (bumps `pubspec.yaml` `X.Y.Z+<build+1>`
  and `lib/harness/version.dart`, dates `[Unreleased]`), commits, tags, builds and signs, and publishes the notes (`--notes`).
- It needs five secrets (keystore ×4, `RELEASE_DEPLOY_KEY`); the page says it is scaffolded and unrun — if a run is requested, report that status.
- `prepare_release.py` refuses an empty Unreleased and a version not higher than current.

Before: tools tests + `check_wiki.py` + `flutter analyze`/`test` green (or reported as not run); entries have the `Title: words` form;
version chosen by semver from the diff since the last `app-v*` tag. Do not trigger the workflow or push a tag unless asked in this turn.
