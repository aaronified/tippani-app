# Releasing

How a release of the app is cut, and what the owner has to provide once. The workflow is `.github/workflows/release.yml`; the decision behind it
is [ADR-0013](ADR-0013-The-Release-Is-Cut-By-A-Workflow.md), and the names the update check reads are
[ADR-0008](ADR-0008-Releases-Are-app-v-Tags.md).

**Status: scaffolded, not yet runnable.** Nothing here has been run against GitHub. It needs the five secrets below, and until they are set the
workflow fails in its first seconds, naming each one that is missing. That is on purpose: a release with no key would be signed with the debug key
and could never be upgraded.

## What the owner provides, once

| Secret | What it is |
| --- | --- |
| `KEYSTORE_BASE64` | The release keystore, base64 on one line. |
| `KEYSTORE_PASSWORD` | The keystore's store password. |
| `KEY_ALIAS` | The alias of the signing key inside the keystore. |
| `KEY_PASSWORD` | That key's password. |
| `RELEASE_DEPLOY_KEY` | The private half of an SSH deploy key with write access, so the release commit can be pushed to a protected `main`. |

### The signing key

Make a new keystore for this app (do not reuse Lexodle's or Fluenough's: it would tie the apps' security together).

```sh
keytool -genkeypair -v -keystore release.jks -alias tippani-app -keyalg RSA -keysize 4096 -validity 36500
base64 -w0 release.jks          # paste this as KEYSTORE_BASE64
```

Then set the four secrets in **Settings > Secrets and variables > Actions**, or with the GitHub CLI:

```sh
gh secret set KEYSTORE_BASE64 -R aaronified/tippani-app < <(base64 -w0 release.jks)
gh secret set KEYSTORE_PASSWORD -R aaronified/tippani-app
gh secret set KEY_ALIAS -R aaronified/tippani-app
gh secret set KEY_PASSWORD -R aaronified/tippani-app
```

**Back the keystore up somewhere you trust, apart from this repository.** Losing it means no installed copy of the app can ever be upgraded, and
Android offers no way to recover from that.

### The deploy key

The release commit (the version bump and the dated changelog) is pushed to `main`. If `main` is protected by a ruleset that asks for a pull request
and passing checks, `GITHUB_TOKEN` cannot bypass it and a deploy key can.

```sh
ssh-keygen -t ed25519 -N "" -C "tippani-app release" -f release_key
gh repo deploy-key add release_key.pub -R aaronified/tippani-app --allow-write --title "release workflow"
gh secret set RELEASE_DEPLOY_KEY -R aaronified/tippani-app < release_key
```

Then add **Deploy keys** to the ruleset's bypass list (Settings > Rules). Delete `release_key` and `release_key.pub` from your machine afterwards.
The workflow rebuilds the key from whatever the secret holds, so a paste that lost its BEGIN and END lines still works; `ssh-keygen` checks it is
a private key before anything is committed.

If `main` is not protected, the deploy key is still used, and still needs write access.

## Cutting a release

1. Make sure `## [Unreleased]` in `CHANGELOG.md` has the entries for what you are releasing, written for the person using the app. The workflow
   refuses to release an empty one. Every pull request adds its own line there.
2. **Actions > Release > Run workflow**, from `main`, and type the version: `0.2.0`, with no `app-v`.
3. The **prepare** job checks it is new and higher, runs `tools/prepare_release.py` (bumps `pubspec.yaml` and `appVersion`, moves Unreleased under
   the version with today's date), pushes that commit to `main` with the deploy key, and tags it `app-v0.2.0`.
4. The **release** job checks the secrets and the tag against the version files, tests, builds a release APK with `--build-name 0.2.0` and the run
   number as the version code, and **checks the APK's certificate against the keystore's**. If they differ, nothing is published. It then attaches
   `tippani-app-v0.2.0.apk` with the changelog section as the notes.
5. Phones that have the app see "Version 0.2.0 is available" the next time they open it.

A tag pushed by hand (`git tag app-v0.2.0 && git push origin app-v0.2.0`) runs the release job alone, and fails before it builds if the tag does
not match `pubspec.yaml` and `lib/harness/version.dart`.

## Things that will bite

- **Do not rename `release.yml`.** The version code is the workflow's run number; a renamed workflow starts again at 1, and Android refuses to
  install a lower code over a higher one.
- **The first install of a release-signed APK over a debug one is refused.** Uninstall the debug build first, once.
- **The tag form is `app-vX.Y.Z`.** A `v0.2.0` tag is the Tippani server's, and the update check ignores it on purpose.
- **A release with no APK reads as "up to date"** to the update check, because the file is uploaded a little after the release appears.
- **"Install unknown apps"** has to be allowed for the app once, on the phone, for the in-app update to install.

## Checking it without releasing

```sh
python3 -m unittest discover -s tools -p 'test_*.py'      # the release tools' own tests
python3 tools/check_release_version.py app-v0.1.0         # does a tag match the version files?
python3 tools/prepare_release.py --notes 0.1.0            # the notes a release would carry
```

The workflow itself can only be proven by running it once the secrets are set; the first release is the test, so cut it as `0.1.0` and look at the
run before telling anyone.
