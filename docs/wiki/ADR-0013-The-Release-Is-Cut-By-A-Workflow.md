# ADR-0013: A release is cut by a workflow, signed with a key that is never in the repository

- **Status:** Accepted. Scaffolded 6 November 2026, after Fluenough and Lexodle; in use since `app-v0.2.0`, with the keys added by the owner.

**Decided.** The owner runs the **Release** workflow from `main` and types a version. Its prepare job runs `tools/prepare_release.py` (bumps
`pubspec.yaml` and `appVersion`, moves the changelog's Unreleased entries under the version, refuses an empty Unreleased or a version that is not
higher), pushes that commit to `main` with a **deploy key**, and tags it. Its release job checks the tag against the version files, tests, builds a
release APK signed with the owner's keystore from repository secrets, **verifies the APK's certificate against the keystore's before publishing**,
and attaches `tippani-app-vX.Y.Z.apk` with the changelog section as the notes. It fails in its first seconds, naming each one, if a secret is missing.

**Why.** A debug-signed APK cannot be upgraded by a release-signed one, and an installed phone then has to uninstall, losing its data. A release
commit pushed to a protected `main` needs a bypass that `GITHUB_TOKEN` does not have and a deploy key can.

**Consequences.** Five secrets: `RELEASE_DEPLOY_KEY`, `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`. Losing the keystore means
no installation can ever be upgraded, so it is backed up apart from the repository. A tag pushed by hand still runs the release job alone.
