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

## Sending the library to the server

`lib/sync/push_sync.dart` (`PushSync`, one per app, held by the harness) and `lib/screens/sync_screen.dart` (Settings > Send library to
server, shown when paired). The design and what it deliberately does not do are [ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md);
the sync that reads the server back is [ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md), below.

- **The log gets counts and item numbers**, never a title or the words of a quote, like every other line the app logs.
- **`ApiException.body`** keeps the server's JSON for a refused request: a 409 on a quote carries `{"existing": {...}}`, and the push links
  to that row instead of creating a copy.
- **The fake server** (`test/support/fake_server.dart`) answers the five create routes with the validation that matters here (colour,
  source, media type, a title it can refuse, duplicate quotes with the existing row, a network that drops after N creates), so the push is
  tested over the wire shape and not against its own assumptions. If the server's create routes change, change the fake with them.
- **`setWorkServerId` and `setQuoteServerId` do not touch `updated_at`.** Being on the server is not an edit; if it were, every push would
  make every item look changed to the pull.

## The Share screen

`lib/screens/share_screen.dart` (`ShareScreen`), `lib/library/share_format.dart` (`ShareFormat`, `shareFieldsOf`, `shareDefaults`,
`buildShareText`, `shareCredit`) and `QuoteCard.show`. It mirrors the web dialog (`web/frontend/src/share.jsx` in the Tippani repository): the
same five formats, the same parts, the same parts off by default. Keep the two in step when one changes. The picture is the card with only the
switched-on parts drawn; the text formats are the same parts as text, regenerated on every change.

## Reading aloud

`lib/speech/speaker.dart` speaks through Android's TTS service. `chooseVoice` is a plain function (tested): the reader's own pick for its
language, else the best installed voice (quality first, then online before on-phone). `lib/speech/speech_settings.dart` keeps the choices in
SharedPreferences. Screens take a `Speaker`, so tests use a fake.

## The quote screen, sharing and saving

`lib/screens/quote_screen.dart` (`QuoteScreen`), `lib/screens/quote_card.dart` (`QuoteCard`, `captureCard`) and `lib/library/quote_text.dart`
(`quoteAttribution`, `quoteShareText`). A quote in the library or on a work's page opens here, not in the editor; Edit is in its app bar.

- **The picture is the screen.** `QuoteCard` is what the reader sees and what `captureCard` draws into a PNG (a `RepaintBoundary`, scaled to
  about 1080 pixels wide). Sit it on a solid ground, as `QuoteScreen` does, or the rounded corners come out transparent and a chat app paints
  them black.
- **Sharing and saving go through functions the screen is given** (`ShareText`, `ShareImage`, `BackupPicker.save`), so a test stands in for the
  share sheet and the file picker. Nothing here reaches a server.
- **Testing a picture needs real time.** Drawing an image is not driven by the widget test's clock: run the tap inside `tester.runAsync` and
  wait for the result (see `waitFor` in `test/library/quote_screen_test.dart`). One message per test: a snackbar made while a picture is
  drawing gets a real timer, and two of them in one test fire after it ends.

## Syncing with the server (the pull)

`lib/sync/pull_sync.dart` (`PullSync`, held by the harness as `harness.pull`), `lib/sync/fingerprint.dart` and `lib/screens/pull_screen.dart`
(Settings > Sync with server, shown when paired). The design is [ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md); read it first.

- **Who moved is read from `synced_hash`, never from `updated_at`.** The server does not give a work's `updated_at`. `fingerprint.dart` turns
  the fields that sync into a canonical form on both sides (`quoteFields` and `serverQuoteFields`, `workFields` and `serverWorkFields`) and
  hashes it. If you add a synced field, add it to **both** forms, or the two sides will never compare equal, and add a test in
  `test/sync/fingerprint_test.dart`. A field the server cannot keep must be left out of the compared form (a film quote's chapter is).
- **Ids mean nothing without the table.** Book 5 and film 5 both exist, and so do annotation 5, dialogue 5 and quote 5. Every lookup is by
  `(Realm, id)`; `test/sync/pull_sync_test.dart` has a test with colliding ids.
- **Everything is read before anything changes**, so a connection that fails half way changes nothing. Writes then go one item at a time; a
  refused write (400, 409) is reported and the sync goes on, a 404 counts the item as gone on the server, anything else stops it.
- **A write to the server is the server's own row with the phone's fields over it** (`_putQuote`, `_putWork`). The server's update replaces
  the whole record, and the phone holds only some of it, so building a body from the phone alone would wipe a sticker or a description.
- **Conflicts are never stored.** `PullScreen` holds them in memory; closing it forgets them, and the next sync finds them again.
- **`setWorkServerId` and `markWorkSynced` do not touch `updated_at`.** Being linked or agreed is not an edit.
- **The fake server** answers the list routes (`/books`, `/movies`, `/annotations`, `/dialogues`, `/quotes`, whose key is `utterances`),
  `GET /books/{id}` and `PUT /{route}/{id}`, and has `seed`, `edit` and `remove` so a test can do what the web would.

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

The pull (once the conflict screen exists), the daily quiz and the rest of phases 1 to 4, then capture, the offline queue, donation, bug reports and the first
signed release (the workflow exists; the keys do not), are the rest of the [plan](Plan.md)'s task list, in that order.

## Sync, in four parts

`lib/sync/`: `push_sync.dart` (sends what is only on the phone, linking a twin the server already has), `pull_sync.dart` (reads the server, applies
changes both ways, deletes, conflicts), `fingerprint.dart` (what counts as the same item and as a change), and `auto_sync.dart` (when to run). The
decisions are ADR-0015 to ADR-0018. Tests drive the first three against `test/support/fake_server.dart`; `auto_sync_test.dart` drives the timers
with the test clock and a settable clock for the back-off. A widget test that starts an `AutoSync` must dispose it before it ends (see `testAuto`),
and the harness leaves it unstarted in tests (`Harness.runAutoSync`).

## The look

`lib/theme/app_theme.dart` (`buildTheme`) is the one place that sets shape, type and spacing over the phone's Material You colours: Inter for the
interface and Source Serif 4 for the words of a quote (`quoteStyle`), both bundled as variable fonts in `assets/fonts` with their SIL OFL licences.
Colours are never picked there, only taken from the scheme. `QuoteTile`, `WorkTile`, `MonogramCover` and `EmptyState` are in `library_widgets.dart`.

To see every screen without a phone, build the browser preview and open it in a phone-sized window (an iPhone user agent shows how the page
transitions and scrolling feel on iOS):

    flutter create --platforms=web .        # once; web/ is not committed
    flutter build web -t tool/preview/main.dart

`tool/preview/main.dart` runs the real app over made-up books, films, boards and quotes held in memory, with no server. Two things differ from a
phone: the sync fingerprint's 64-bit constant does not compile for the web (patch it locally for the preview and do not commit that), and `flutter
build web` adds `web/**` to `analysis_options.yaml` (restore the file).

## The sections

`Shell` (`lib/app.dart`) builds Library, Catalogue and Quotes from one `LibraryScreen` with a `LibrarySection` each, then Anthologies where the harness has an
`AnthologyService`, then Settings. The icons are the web app's four SVGs in `NavSection` (`nav_icons.dart`), tinted by the icon theme of the bar. The
screens sit in an `IndexedStack`, so each listens to `LibraryStore.changes` and to the automatic sync finishing to stay current when another section
or a sync changes the library. A harness with no library (a test of the server screens alone) shows a Home tab instead.

## The changelog in the app

`CHANGELOG.md` is bundled into the app and parsed by `parseChangelog`. The app shows each change by `changeHeader` only (the text before a colon if it is
at most 70 characters, else the whole line if it is short, else the first sentence cut at 100), and `ChangelogScreen` (Settings > What's new) ends with
a link to `changelogUrl` on GitHub, opened through an injectable `OpenLink`. So **start every changelog entry with a short title and a colon**; the
details go after it and are read on GitHub.

## Choosing words on the picture

`CaptureScreen` asks the recogniser for hOCR first. `parseHocr` is lenient (it never throws; a word with no box or no text is skipped) and gives a
`RecognisedPage`; `PageSelection` holds the chosen word indexes and builds the text. `PageSelector` uses one `ImmediateMultiDragGestureRecognizer`
for everything on the picture: a finger that lands and lifts without moving far is a tap, one that moves draws a box. That recogniser is deliberate:
the picture sits in a scrolling page, and an ordinary tap-and-pan recogniser loses to the page's scroll on any mostly vertical drag. The same is
true of the crop handles in `AdjustScreen`. If hOCR is empty or throws, the screen falls back to `TextRecogniser.read`.

## Straighten and crop

`page_geometry.dart` is plain Dart over a `Luma` (brightness bytes), so it is tested with drawn pages: `estimateSkewDegrees` projects the ink onto rows for each
angle and takes the angle that piles it up most (coarse at a degree, then a tenth), and `textBounds` is the ink's 1st to 99th percentile box once
turned. `PageAdjuster` is the seam to the picture work: `DevicePageAdjuster` decodes at 480 px to look and at up to 3000 px to make the picture
(`dart:ui` canvas: white ground, turn about the centre, draw, cut), and `AdjustScreen` previews with Flutter's own rotation so what is shown is what is made.
The preview rotates about the picture's centre and the crop is in fractions of the picture's own box, which is exactly how `render` draws it.

## Capture

`CaptureScreen` (a photographed page, read by Tesseract) and `VoiceScreen` (speech to text through the phone's recogniser) each pop a `CapturedText`;
`QuoteFormScreen` puts it in the words (`_put`) and is the only place a quote is made from them. They take a `PhotoSource`, a `TextRecogniser` and a
`VoiceListener`, so a test stands in for the camera, Tesseract and the microphone.

## Boards

A board (`Board` in `models.dart`, table `boards`, `quotes.board_id` with `ON DELETE SET NULL`) is a shelf for standalone quotes, mirroring the server's.
The store forces `board_id` to null for a quote that has a work. Names are unique in any letter case. `quotes()` takes `boardId` and `unfiled`;
the Library filters with them and groups client-side (`_groupedQuotes`). They are not synced yet: when they are, the quote fingerprint must
carry the board by its server id, and a board needs a `server_id` and a pending-deletion route like works and quotes have.

## Work details

`PairedWorkDetails` (`lib/tools/work_details_source.dart`) reads a work's own record and its cast when a work's page opens, and the page keeps
the answer in `works.details` as JSON (`WorkDetails` in `models.dart`, tolerant of anything: it never throws on a record it does not
understand). It is read-only metadata, kept out of the sync fingerprint, so it can never be a conflict. A page asks once per visit, and only
when the details were never fetched or are over a day old; if the server does not answer, what was kept stays on show.

## Covers

`CoverCache` (`lib/library/cover_cache.dart`) fetches `GET /covers/{name}` once into `<app support>/covers/` and answers from disk after. The server
names a cover file once and never reuses the name, so nothing is ever refreshed: a changed cover is a new name, which the pull stores on the work
(`Work.cover`). Names are checked against the server's own pattern before any fetch or file path is built. A failed fetch is not retried for two
minutes. `CoverScope` hands the source to every screen from above the navigator, and `WorkCover` draws a work's picture or a fallback.

## Testing against a real server

`test/live/live_sync_test.dart` runs the real push and pull code against a real Tippani server (it checks what the server really holds
after each step: a book and its quote, a loose quote, a film and its dialogue, an edit each way, and a conflict resolved). It is skipped
unless two variables are set, so `flutter test` stays offline.

1. Build and start a server on an empty data folder (from the Tippani repository; `go build -o tippani-local ./cmd/tippani`), for example
   `TIPPANI_BIND=127.0.0.1:18080 TIPPANI_DATA=./livedata ./tippani-local`.
2. Make the first account: `POST /api/auth/signup` with `{"username":"tester","password":"correct-horse-9"}` (the password may be at most
   20 characters), keeping the session cookie. Then `POST /api/auth/devices/pair` with that cookie answers with a pairing code.
3. `TIPPANI_LIVE_URL=http://127.0.0.1:18080 TIPPANI_LIVE_CODE=<code> flutter test test/live/live_sync_test.dart`.

Start from an empty data folder each time: the two tests share the server, and anything left from an earlier run comes down on the next.
The first run of this test (7 November 2026) found that the server's own names differ from the guesses the fake server was built on in only
small ways (`quote` for a quote's words; case in tags is kept), and that the bodies the sync sends are accepted.
