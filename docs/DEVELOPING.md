# Developing

## Build and test

You need Flutter (the version in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml); CI pins it) and the Android SDK.

```sh
flutter pub get
dart format lib test        # CI fails on unformatted code
flutter analyze
flutter test
flutter build apk --debug
```

`flutter test` needs no device and no network: the HTTP client is injected, and the tests give it a fake.

## Layout

| Path | What it is |
| --- | --- |
| `lib/main.dart` | Opens the stored settings and starts the app. |
| `lib/app.dart` | The theme (the phone's own colours where it has them, Tippani's red where it does not) and the bottom bar. A later phase adds its screen there. |
| `lib/app_controller.dart` | The state more than one screen needs: which server, and whether it answered and is compatible. |
| `lib/api/capabilities.dart` | The version handshake: the revision this build was written for, and the oldest server it accepts. |
| `lib/api/api_client.dart` | The one way the app speaks to a server: Bearer token, timeouts, and typed failures (network, timeout, unauthorised, server, bad response). |
| `lib/settings/server_url.dart` | Turns what a reader types into the address the app keeps, and says when plain `http` would send a credential across the internet. |
| `lib/settings/settings_store.dart` | The server address in preferences; the device token in secure storage and nowhere else. |
| `lib/pairing/` | The pairing code, the claim, and the device list. |
| `lib/screens/` | Home, Settings, the connect, pair and devices screens. |
| `lib/harness/` | The base every feature stands on: version, update check and installer, the log, backup and restore, the changelog. See [The harness](#the-harness). |
| `test/` | One file per unit above, and `connect_flow_test.dart` for the screens. |

## The harness

`lib/harness/` is what every screen of the app can rely on, built once in `main` and handed down as a `Harness`. A new feature screen
gets a log line, a backup section and an update toast without writing any of them.

| Part | What it does |
| --- | --- |
| `version.dart`, `update_check.dart` | `appVersion` (a test fails if it differs from `pubspec.yaml`). On open the app asks GitHub for the latest release of this repository; only a tag `app-vX.Y.Z` counts, so the server's tags are never mistaken for an app release. A release whose APK is not uploaded yet reads as up to date. |
| `update_controller.dart`, `update_ui.dart` | A newer version shows a toast with **Download**; one press downloads, with progress and Cancel, then opens Android's installer. A check that cannot reach GitHub on open is silent; one the reader asks for in Settings says what happened. Nothing downloads until Download is pressed. |
| `apk_install.dart` | The download and the installer, through `ota_update`, into the app's own storage (no storage permission). A download whose SHA-256 differs from the release's is refused; one already on the phone with the right checksum is installed without downloading again. |
| `changelog.dart`, `changelog_screen.dart` | `CHANGELOG.md` is bundled as an asset. After an update the entry for the new version appears once; **What's new** in Settings lists every version. A first install shows nothing: there is nothing to be new since. |
| `app_log.dart`, `log_screen.dart` | A log of what the app did, written to its own storage, readable, copyable and shareable in Settings. Credentials are redacted before a line is kept, and callers pass what happened, never what was said. |
| `backup.dart`, `backup_screen.dart` | A backup is a JSON file of sections, one per `BackupContributor`. It is written to the app's storage and to Downloads, restored from either or from a file, and refused with a sentence if it is not ours, too big or from a newer app. **The device token is never in it.** |
| `files.dart`, `MainActivity.kt` | One narrow interface over one native channel: backups, the log, the Downloads copy (MediaStore, no permission) and the installer. Tests use `MemoryAppFiles`. |

**Adding a feature to the harness.** A feature with data worth keeping (the offline capture queue) implements `BackupContributor` and
adds itself to the list in `Harness.open`; it is then backed up and restored with no change to the backup code. A feature that wants
a changelog line adds one to `CHANGELOG.md` under Unreleased.

**Releasing, once the release workflow exists.** Raise `version:` in `pubspec.yaml` and `appVersion` together, move the Unreleased
entries under the new version in `CHANGELOG.md`, tag `app-vX.Y.Z`, and attach `tippani-app-vX.Y.Z.apk`. The update check reads exactly
those names.

## Pairing and the account

- **Pairing is a typed code.** Tippani's web Settings > Devices > Pair a device shows an 8-character code, good for five minutes
  and once. `normalisePairingCode` ignores case, spaces and dashes and reads `O`, `I` and `L` as the server's alphabet does. The
  claim (`POST /auth/devices/claim`) carries no credential; the token it returns goes to secure storage and never to the log.
- **401 and 403 are different.** 401 means the server no longer accepts the token (the phone was unpaired on the web): the app
  forgets it and Home says so. 403 means the token is good but not allowed (an admin-only route asked by a non-admin): it never
  unpairs the phone.
- **`isAdmin` is asked, not stored.** `GET /auth/me` on open and after pairing; a demoted admin loses the admin screens the next
  time the app opens.
- **Unpairing** asks the server to forget this phone (the row `GET /auth/devices` marks `current`, server API revision 9) and then
  forgets the token here whether or not the server could be reached. On an older server the device list says it cannot tell which
  row is this phone.

## The two logs

**App log** is this phone's own record (`lib/harness/app_log.dart`). **Server log** is the Tippani server's, read from
`GET /admin/logs` by an admin (`server_log.dart`, `server_log_screen.dart`): levels, a window set by the server's clock, a keyword,
paging with the first answer's window sent back so lines logged meanwhile are in neither page. They are never mixed on a screen,
in Copy or in Share, and the server's lines are redacted on the way out like the app's.

## Decisions made in the scaffold

- **Package id** `io.github.aaronified.tippani`, as the plan suggested.
- **Cleartext http is allowed** (`android:usesCleartextTraffic`), because a self-hosted server on the home network is usually plain
  http and Android blocks it by default. The connect screen warns before it keeps an http address that is not on a private network.
- **The app refuses a server outside its range.** `builtForRevision` and `minServerRevision` in `lib/api/capabilities.dart` are the
  contract with [Tippani](https://github.com/aaronified/tippani): raise `minServerRevision` when a screen starts to need something a
  later server revision added, and the app will say "update the server" instead of calling a route that is not there.
- **The log is written a moment after each line**, not on every line, and a test turns that timer off (a pending timer fails a widget
  test); the Share button writes it first.
- **`dynamic_color` is pinned to 1.8.x.** From 2.x it builds on the separate `material_ui` package, whose `ColorScheme` is not the one
  in Flutter's own material library, so the two cannot be mixed in one app yet.

## Not built

Pairing, capture, the offline queue, donation, bug reports and the signed release, with the workflow that publishes what the update
check looks for, are the rest of the [plan](PLAN.md)'s task list, in that order.
