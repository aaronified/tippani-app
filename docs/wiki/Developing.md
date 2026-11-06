# Developing

## Build and test

You need Flutter (the version in [`.github/workflows/ci.yml`](https://github.com/aaronified/tippani-app/blob/main/.github/workflows/ci.yml); CI pins it) and the Android SDK.

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
| `lib/library/` | The phone's own library: `models.dart`, the SQLite `library_store.dart`, its backup contributor, and `markdown_export.dart`. See [The local library](#the-local-library). |
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

**Releasing.** You do not edit the version by hand: run the Release workflow with the version, and it bumps `pubspec.yaml` and
`appVersion`, dates the Unreleased entries, tags `app-vX.Y.Z` and attaches `tippani-app-vX.Y.Z.apk`. The update check reads exactly
those names. [Releasing](Releasing.md) has the secrets it needs and the steps; it is scaffolded and has not been run yet.

## Decisions and the wiki

Every decision that a later change could undo is a page, `ADR-NNNN-Title.md`, in `docs/wiki/`, listed in
[ADR-Index](ADR-Index.md) with the template to copy. `.github/workflows/wiki.yml` mirrors the folder to the GitHub wiki when it changes
on `main`. `tools/check_wiki.py` runs in CI and fails on a dead link, a page nothing links to, an ADR missing from the index, a gap
or repeat in the numbers, or an ADR with no `Status`. The wiki is published flat, so link to another page by its file name, never to a
repository path.

## The release tools

`tools/` is Python with only the standard library, tested by `python3 -m unittest discover -s tools -p 'test_*.py'` (also in CI):
`check_release_version.py` (tag against `pubspec.yaml` and `appVersion`), `prepare_release.py` (the version bump and the dated
changelog) and `check_wiki.py`.

## The local library

The app works with no server, so the quotes live on the phone (`lib/library/`). `LibraryStore` is the one interface every screen
reads and writes; `SqliteLibraryStore` is SQLite through `sqflite`, with the database in the app's own storage.

- **Works and quotes.** A work is a book, film, show, game or other, with a title, a creator and a year. A quote has its words, a
  translation, language, who said it, chapter, location, a note, a colour, a favourite flag, when it was met, and where it came from
  (`manual`, `capture`, `import`). A quote with no work is a standalone one. Deleting a work deletes its quotes (foreign keys are on).
- **Tags** are case-insensitive and shared; a tag nothing uses is dropped.
- **Search** is `LIKE`, not full text: Android's SQLite does not promise FTS5, and a personal library is small. A `%` or `_` typed in
  a search is the character, not a wildcard. It matches the words, translation, note, speaker, the work's title and creator, and tags.
- **Every id also has a `server_id`**, empty until a paired server has the row. That is where sync will hang.
- **Backup.** `LibraryBackup` is a `BackupContributor`. Restoring REPLACES the library. Every section of a backup is checked before
  any is written (`BackupContributor.check`), so a backup with a damaged library changes nothing, settings included.
- **Testing.** The store is tested against real SQLite (`sqflite_common_ffi`, in memory, `singleInstance: false` so two stores in a
  test are two databases). Widget tests cannot drive real SQLite I/O (their fake clock never completes it), so screen tests use an
  in-memory `LibraryStore` and the store has its own file.

### The library screens

`lib/screens/library_screen.dart` is the first tab (the app opens on it; the server screens are the second tab, called Server). It
reads only a `LibraryStore`, so it works with no server. `quote_form_screen.dart` and `work_form_screen.dart` add and change a quote
or a work; `work_screen.dart` is one work with its quotes; `library_widgets.dart` holds the quote tile and the export plumbing.

- **A search that finishes late must not win.** `_load` numbers its requests and only the newest fills the list; a test makes an old
  search finish after a newer one.
- **Errors sit at the top of a form**, not under the last field, where a phone's keyboard would hide them.
- **Export is Tippani's own Markdown** (`markdown_export.dart`, modelled on the server's `export_handlers.go` and `export_quotes.go`):
  a book is `type: book` with quotes under `## chapter` headings, a film, show or game says `type: movie|show|game`, quotes with no
  work are one `type: quotes` block, a work with no quotes is left out, and yellow (the default colour) is never written. The server
  imports these files, so a library made on the phone can be moved to a server. Share goes through the share sheet; Save uses the
  file picker (no storage permission).
- **Tests.** The screens are tested against `test/support/memory_library.dart`, a `LibraryStore` with no I/O, because a widget test's
  fake clock cannot drive real SQLite. The store itself is tested against real SQLite in `library_store_test.dart`.

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

The daily quiz and the rest of phases 1 to 4, then capture, the offline queue, donation, bug reports and the first
signed release (the workflow exists; the keys do not), are the rest of the [plan](Plan.md)'s task list, in that order.
