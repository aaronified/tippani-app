# Tippani for Android: the plan

Source of truth: this file. Moved here from the Tippani repository's wiki (`Plan-Android-App.md`, roadmap §20) when the app
got its own repository; the move is recorded in Tippani's ADR-0931.

Built and in use (releases `app-v0.2.0` to `app-v0.8.1`); the sections below keep the plan as it was written, with what is done and not done marked. Written against Tippani `558059cf` (main, 25 October 2026), and moved on 6 November 2026. The server half is in
[Tippani](https://github.com/aaronified/tippani); the app is this repository. This plan is the app's feature list, what to reuse from
Lexodle and Fluenough, the release and signing set-up, and the open questions.

**Where things are now.** The app is in this repository, at its root, not in a `mobile/` directory of Tippani. Where the text below says
`mobile/`, read the repository root. Where it says a file is in Tippani (`internal/httpapi/...`), it still is. Server work the app needs
is filed as issues on Tippani; this repository's issues are the app's.

## What the app is

A native Flutter client for Android, for one reader's own Tippani server. It is not a wrapper around
the web app. Its first job is the one thing a web page does badly on a phone: photograph a page of a book and turn
a highlighted passage into a quote. It also does the rest of what Tippani does (see feature 5).

Android only. No `ios/` directory ships, because building and signing for iOS needs a Mac. The Dart stays
platform-neutral.

## What the server already gives it

All of this is built (the files are named below):

- **Pairing.** Settings makes a code (`POST /auth/devices/pair`, valid 5 minutes, single use). This plan assumed a QR code; the server shows
  8 characters and the app takes them typed ([ADR-0006](ADR-0006-Pairing-Is-A-Typed-Code.md)). The app claims it (`POST /auth/devices/claim`, rate limited) for a **device token**. Tokens are listed and revoked in
  Settings (`GET/DELETE /auth/devices`). `internal/httpapi/pairing_handlers.go`.
- **Version handshake.** `GET /capabilities` needs no credential and returns an `apiRevision` integer, so the app can
  tell whether it and the server are compatible before it holds a token. `internal/httpapi/capabilities_handler.go`.
- **Offline-friendly writes.** `noted_at` on create keeps a queued capture's real date; a duplicate answers `409` with
  the existing row, so retrying a flush is safe.
- List paging, gzip, and the shared quote shape.

What the server lacks for this plan (small, listed under Tasks): a shared text-cleanup step for captured text, a
photo kept with a quote, and an app-release feed that does not mix with the server's releases.

## Decisions to confirm

1. **Package id. Decided:** `io.github.aaronified.tippani` (Lexodle uses `io.github.aaronified.lexodle`), in use since the scaffold.
2. **A new keystore for this app. Decided and set up.** Reusing Lexodle's would tie two apps' security together. The owner supplied it as
   repository secrets, and every release since `app-v0.2.0` is signed with it.
3. **Licence. Decided: GPL-3.0** (this repository's `LICENSE`), chosen by the owner on 6 November 2026. It is separate from the Tippani server,
   which is MIT; the app only talks to a server over its API. Fluenough's app-store exception is not copied unless asked.
4. **"All Tippani functions" is phased**, not one release (feature 5).
5. **The donation disclaimer's wording.** Fluenough has none to copy: a search of its code, docs and UI found no
   donation disclaimer or donation screen. A draft is under feature 3; the owner confirms or replaces it.
6. **Minimum Android version.** Whatever the installed Flutter gives. Wallpaper colours need Android 12; older phones
   get a fixed fallback palette.

## Features

### 0. The app works on its own

**The owner's requirement (6 November 2026): the app must be able to work independently of a server.** A server is optional.

- **A local library on the phone** (SQLite, in the app's own storage) holds books and quotes: capture, browse, search, edit, tag and
  the daily quiz all work with no server and no network. This is the app's own data; pairing is something added to it, not a way
  in.
- **Pairing adds sync, it does not replace the local library.** When the phone is paired, what was made locally is pushed to the
  server (the offline queue of feature 1 is this push, generalised) and what the server has can be pulled down. `409` on a
  duplicate still makes a retry safe. Who wins on a conflict is chosen per item ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md)), and the pull and the
  automatic sync are built ([ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md), [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md)).
- **Leaving no door shut.** An unpaired phone can export its library as Tippani's own Markdown format, which the server already
  imports, so a reader who starts alone and later installs a server loses nothing.
- **Backup and restore carry the local library** (the harness's `BackupContributor` is where it registers), so a phone that is
  the only copy of someone's quotes can be backed up and restored.
- **What needs a server stays labelled as needing one:** the server log, the device list, the server's metadata lookups, shared
  anthologies and boards. Home no longer opens on "not connected"; it opens on the library.
- **What works alone, decided by the owner (6 November 2026): the core.** The library, quotes, search, add/edit/tag, the daily quiz,
  boards, and export/import run on the local database, and anthologies are kept on the server with a copy and a queue on the phone so they work with
  no server ([ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md)). **Management and admin screens need a paired server to change
  anything and say so:** metadata sources, Checks, jobs, library folders, source files, the server log, the device list. With no server they show the
  phone's last copy of what the server said.
- **Order of work, decided by the owner the same day: all the functions first, then new features.** (1) the local library; (2) phase 1
  core; (3) phase 2 reading side; (4) phase 3 management; (5) phase 4 settings and admin; and only then the new features: capture
  with Tesseract, donation, bug report, and the signed release. Pairing and the harness (both done) are unaffected.

### 1. Capture a page and highlight the passage

The flow: photograph a page, the app recognises the text on the device, the reader selects the passage on the photo,
the app proposes a book, the page and the chapter, the reader corrects anything, and it saves as a quote.

- **On-device OCR with Tesseract, not ML Kit** (the owner's decision, 6 November 2026: nothing proprietary). Tesseract is Apache-2.0,
  runs on the phone with no upload and no server cost, and returns each word's and line's bounding box, which the line selection and the
  page-number and chapter proposals below depend on. Its language data (`tessdata_fast`, also Apache-2.0) is per language, so English
  ships with the app and others (Bengali `ben`, Hindi `hin`, the languages Tippani's readers use) are downloaded when the reader asks.
  Accuracy on a photographed page is lower than ML Kit's, so the correction screen is not optional and the app straightens and
  sharpens the photo before recognising it. Because nothing proprietary is linked, **no GPL additional permission is needed**: the
  earlier note that one would be required before the OCR phase no longer applies. The package to use is chosen when the capture
  phase starts, and must be free software with a native Tesseract inside it; if none is well enough kept, the app wraps Tesseract
  itself through a small native channel, as the harness does for files.
  Neither Lexodle nor Fluenough uses a camera or OCR package; this is new work.
- **Capture:** `camera` or `image_picker`, then crop and straighten.
- **Highlight on the photo:** draw the recognised lines over the photo; the reader drags across them or taps lines to
  select. The selection is the quote text. Each recognised line carries a bounding box, which is also what makes the
  next two steps possible.
- **Page number and chapter from the header and footer, when visible.** The recognised blocks have positions, so:
  the top and bottom bands of the page (about the first and last 8% of its height) are searched; a short line that is
  only digits or a roman numeral is the **page number**; a short centred or running line in the top band that is not
  part of the body is the **chapter or running head**. The app shows what it found, marked as proposed, and the reader
  accepts or edits. If nothing is visible, nothing is proposed. A guess is never silently saved.
- **Clean-up of the recognised text** (rejoin hyphenated line breaks, drop running heads, fix quote marks and
  ligatures) belongs on the **server**, shared with every import source ([Roadmap](https://github.com/aaronified/tippani/blob/main/docs/wiki/Roadmap.md) §7), so the app calls it
  and the cleanup is written once.
- **Saving:** `POST` a quote on the chosen book with `noted_at`, `source`, the page or location, and the chapter. A
  capture made offline queues and flushes when the server is reachable; `409` makes a retry safe.
- **The photo is kept with the quote** (server: one nullable image column on the existing image pipeline), so the
  evidence stays beside the transcription.

### 2. Update check and automatic update

Reuse the design both apps already share: ask the GitHub releases API, compare versions, download the APK with the
`ota_update` plugin into app storage, check its SHA-256 against the asset's `digest`, then Android's installer opens.
Android itself enforces that an upgrade is signed with the same key. See Lexodle `lib/update_check.dart`,
`apk_install_ota.dart`, `update_section.dart` and Fluenough `lib/app/update_checker.dart`,
`lib/core/updates/github_release_check.dart`.

- Take Fluenough's extras: delete the downloaded APK after the update, a 60-second stall check, an "open the download
  page" fallback, and "What's new" read from the release notes.
- The app checks on every open, which is the owner's call ([ADR-0007](ADR-0007-The-Harness-Is-The-Base-Every-Screen-Stands-On.md)); the plan had it off
  by default, as in both other apps. A check can be asked for at any time.
- **The app is released on its own tags.** Tippani's server releases use `vX.Y.Z` and `releases/latest` points at
  them. The app uses tags `app-vX.Y.Z`; now the app has its own repository, the update check reads that repository's latest release and requires
  the `app-v` prefix.
- The app also reads `GET /capabilities` and says plainly when the server is too old or too new for it.
- Needed on Android: the `ota_update` FileProvider and its paths file, core library desugaring, and removing the
  storage permissions. The owner turns on "Install unknown apps" for the app once.

### 3. Donation

Reuse Lexodle's section (`lib/donate.dart`, `tools/make_donate_qr.py`, `assets/donate/upi-qr.svg`, the `upi`
`<queries>` entry in the manifest): the QR code, a copy-ID button, and a "pay with a UPI app" button that opens the
phone's UPI apps with the payee filled in. It takes `flutter_svg` and `url_launcher`.

- **Payee:** UPI ID `das.arani@pingpay`, name `Arani Das`, currency INR, no amount. Regenerate the QR from the same two
  values (the script draws filled squares; segno's stroked rows showed seams on a phone).
- Replace Lexodle's hard-coded copy and its theme helper; keep the style of the rest of the app.
- **Text above the QR code (draft, for the owner to confirm).** The owner's line first, then the disclaimer:
  "If you want to support development, or just want to buy me a cup of tea, donate."
  "Tippani is free and has no ads. Donating is voluntary, buys nothing and is not refundable. Reporting a bug helps just as
  much."

### 4. Report a bug

Reuse Fluenough's chain (its decision ADR-0021): the bug button opens a form; the form opens the reader's own mail app
with a prefilled mail; an hourly GitHub Actions job reads the inbox over IMAP and opens a GitHub issue. No server of
Tippani's and no token in the app.

- **App:** a report form with kinds Support (private), Bug and Feedback (public issues); a title and details; optional
  device info (app version, Android version, screen size, text scale, theme) with the exact lines shown; optional
  attached log, both off by default. Fluenough: `lib/features/report/report_page.dart`,
  `lib/core/feedback/report.dart`, `lib/app/report_mail.dart`.
- **Workflow (I write it):** `.github/workflows/app-feedback-mail.yml` and `scripts/mail_to_issues.py`, adapted from
  Fluenough's `feedback-mail.yml` and `tools/mail_to_issues.py`: subject prefix `[Tippani app]`; label by kind plus
  `from-app`; Support mail never becomes an issue; the sender's address is never copied; a log is never copied into the
  issue; filed mails are tagged in Gmail, never marked read. With no secrets set, the job does nothing and says so.
  Tests in Python, as Fluenough does.
- **The address is created: `tippanidev@gmail.com`.** It goes into the app as a constant and into the secret
  `FEEDBACK_GMAIL_ADDRESS`. **Still for the owner:** turn on 2-step verification and IMAP for it, make an app password, and
  add the repository secrets `FEEDBACK_GMAIL_ADDRESS` and `FEEDBACK_GMAIL_APP_PASSWORD` before the workflow can run. The
  password is never written in the repository or the app.
- The issue text is public. The form says so.

### 5. All of Tippani's functions

Phased, in this order, each phase a release of the app:

1. **Core:** pair with a server, capture (feature 1), browse the library, quotes and search, the daily quiz, add and
   edit a quote.
2. **Reading side:** work details with source file and context, boards and anthologies, share a quote as a picture.
3. **Management:** metadata and people, Checks (imports, cleanup, found files, corrections, locators), bin, stats.
4. **Settings and admin:** profile, devices, backups, jobs, library folders, server settings (admin only).

Every screen calls the same server API as the web app, so a function needs no new server code unless listed under
Tasks. An in-app web view for the long tail is not planned (it needs a token-to-session exchange the server does not
have); phase 3 and 4 screens are built natively. Say if a web-view bridge is acceptable for them.

### 6. Theme

First version: Material 3 with **Android's dynamic colour** (the `dynamic_color` package, `DynamicColorBuilder`),
falling back to a seed palette from Tippani's accent on older phones, with the system light and dark setting. Neither
Lexodle nor Fluenough has dynamic colour yet. **Material You only (the owner, 6 November 2026): the web app's themes, material
sets and textures are not carried over, and are not a later phase.** The app is never asked to reproduce the server's look, and a
synced account's theme preferences are ignored here.

## Release and signing

- **Signing.** Copy Lexodle's mechanism: the keystore comes from secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
  `KEY_ALIAS` and `KEY_PASSWORD` (the owner provides the keystore as for Lexodle; use a new one for this app). The
  workflow decodes it, passes it to Gradle through AGP's injected signing properties (no Gradle edits), builds, then
  verifies the APK's certificate against the keystore's and fails on a mismatch. **It fails if a secret is missing**
  (Fluenough's rule), because a debug-signed APK cannot be upgraded by a release-signed one. The signing material is
  removed at the end of the job.
- **Workflows.** `ci.yml` on pull requests and pushes to `main`: the release tools' tests, the wiki check, `flutter pub get`, a format check,
  `flutter analyze`, `flutter test` and a debug build. `release.yml` on a run by hand (it bumps and tags) or a tag `app-v*`: the same
  checks, then the signed APK named `tippani-app-vX.Y.Z.apk` attached to a GitHub release, with notes from the log since the previous `app-v` tag.
- **Version.** The tag is the version; the build number is the run number. A check fails the release if the tag and
  `pubspec.yaml` disagree.
- **Layout.** The repository root is the Flutter project, with a committed `android/` (Lexodle's way; Fluenough generates it in CI). The wiki, the
  file map in Developing and the CI table are updated with it.

## Tasks

- [ ] Re-verify this plan against the code before starting; correct what moved.
- [ ] **Server:** shared text-cleanup step for captured text (roadmap §7); a nullable photo on a quote. (The app is built for `apiRevision` 9; the server is at 10, which added the anthology poster and description, and the app offers those only when the server names the `anthology-poster` feature.)
- [x] **Scaffold** (done 6 November 2026): package id `io.github.aaronified.tippani`, dynamic-colour theme, a bottom bar, server address
      in preferences, the HTTP client (Bearer token, timeouts, typed failures), the `GET /capabilities` check with the app's own
      revision range, the connect screen, tests, and `ci.yml`. Not in it: pairing (the client can carry a token; nothing yet gets one).
- [x] **Harness** (done 6 November 2026; asked for by the owner, ahead of the feature screens): the update check on open with a toast and
      an in-app download, the changelog after an update and a What's new screen, the log, and backup and restore, built so a later
      feature registers its data for backup instead of changing the backup code. See [Developing](Developing.md#the-harness).
- [x] **Pairing** (done 6 November 2026): claim, store the token in secure storage, list and revoke devices, unpair, and know when the
      server has unpaired this phone. **Corrected from the plan:** Tippani's web Settings shows an 8-character code, not a QR, so the
      app takes the typed code. A QR needs a web change (and a QR drawing library, against Tippani's dependency budget); it is a
      later nicety, not a blocker. The server marks the caller's own device `current` (Tippani API revision 9) so the app never
      offers to revoke the phone in the hand.
- [x] **Server log** (done 6 November 2026; asked for by the owner): an admin's view of `GET /admin/logs` with its filters and paging,
      separate from the app's own log.
- [x] **Local library** (done 6 November 2026; first, see section 0): the SQLite store of works, quotes and tags with search and its
      backup contributor (restore replaces, checked before it writes); the Library tab, which the app now opens on (quotes and works,
      search, favourites, tag filter, add, edit, delete, a work's own page); and export as Tippani Markdown, shared or saved.
      Sorting choices and bulk selection came after (0.7.0). Left for later: the quote's colour board.
- [x] **Push sync** (done 6 November 2026): works and quotes only on the phone go up once when paired, ids kept in `server_id`
      ([ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md)).
- **Order changed by the owner (6 November 2026): the daily quiz comes later.** The reading, sharing and saving sides come first and fast;
      **capture (camera and Tesseract OCR) is needed**, and so is **recording sound and saving from there** (voice capture). Until the owner
      says otherwise, the order is: quote screen and sharing; work details and a reading mode; capture; voice capture; boards and anthologies
      on the phone; management and admin; then the quiz.
- [x] **Quote screen, share and save** (done 6 November 2026): tapping a quote opens it as a card with its note, tags and work; favourite,
      edit, delete, share as text, share as a picture (a PNG drawn from the same card the reader sees), and save that picture to a file.
      Works with no server.
- [x] **Capture, first slice** (done 7 November 2026): Scan a page from the library and from a work: take a photo (the system camera) or choose
      one, Tesseract on the phone reads it (English, Hindi, both; data bundled), the text is tidied and corrected on screen, then the quote form
      saves it with `source: ocr`. Selecting the passage on the photo and straightening and cropping came after (0.4.0, see the changelog).
      **Not yet:** proposing page and chapter, other languages (Bengali `ben`), and an unverified run on a real phone.
- [x] **Metadata lookup, first slice** (done 7 November 2026): Look up details on the work form, through the server's `/books/lookup` and
      `/movies/lookup` (so no provider key is in the app). Books checked against a real server (Open Library); films, shows and games are
      built from the Go handler's shape but **not verified**, because the local server had no TMDB or TheTVDB key. Fills title, author,
      year. Finding a cover online, with a choice of supplier, came after (0.7.0). **Not yet:** genres, description, ISBN lookup.
- [x] **Bin and statistics** (done 7 November 2026): from the paired server's `/trash` and `/stats`: list, restore, delete for good, empty;
      totals, busiest month, most quoted, top tags. Checked against a real server in `test/live`. Statistics breakdowns, Checks and boards came after (0.4.0 to 0.7.0,
      see the changelog). **Not yet:** the bin's per-entry detail.
- [x] **Anthologies, first slice** (done 7 November 2026): kept on the server, not copied to the phone (management screens need a paired
      server, the owner's decision): list, make, rename (the server's own row is sent back with only the title and introduction changed, so
      its display switches survive), delete, read, share as text, take a passage out, and Add to anthology from a synced quote.
      Checked against a real server in `test/live`. Reordering, per-passage commentary, sections, grouping, front matter and the cover came after (see the changelog).
- [x] **The server is a section of Settings** (done 8 November 2026, owner's ask): the Server tab is removed; Settings opens with a Server section (address
      and status via `serverStatusLine`, Check again, the unpaired warning, pairing, and everything that needs a paired server) followed by App. Only
      the test-only harness with no library keeps a Home tab. *Superseded on 9 November 2026 by [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md): the Server tab is back.*
- [x] **The four sections** (done 8 November 2026, owner's ask): the bar is Library (books), Catalogue (films, shows, games), Quotes (with boards) and
      Anthologies, then Settings, with the web app's own four icons (`lib/screens/nav_icons.dart`, `flutter_svg`). One `LibraryScreen`, told which
      `LibrarySection` it is; the default section is the whole library, so earlier uses are unchanged. Each reloads on `LibraryStore.changes` and when a sync ends.
      *Superseded on 9 November 2026 by [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md): the bar is Home, Boards, Server and Settings.*
- [x] **Author, actor and character chips** (done 8 November 2026, owner's ask): `chipsFor` (`lib/library/quote_chips.dart`) gives a book's author chip and a
      chip per named speaker; for a film, show or game each speaker is a character chip with the actor from the work's cast under it (the cast comes
      from the work details, so it is there once a work's page has been opened). `QuoteChipsRow` draws them in the Library list and on the quote screen;
      pressing one filters the library by the name. Portraits and the person's or character's own page came after (0.7.0).
- [x] **Sync policy: on every change and once a day** (done 8 November 2026, owner's ask, [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md)):
      a run four seconds after any change; one daily run at opening, coming back, the network returning, or a day passing while open; a change that could
      not be sent is remembered across restarts and goes at the next of those; no retry timer, no back-off.
- [x] **Context from the server** (done 8 November 2026, owner's ask): the quote screen's Context section reads `GET /quotes/{annotation|dialogue|utterance}/{id}/context`
      (`lib/tools/quote_context.dart`) on demand, shows the text before, the quote as the file has it and the text after, widens by three with
      `?before=&after=` up to what is stored, and says where the chapter ends. How much context a quote or work shows came after (0.7.0, in Settings).
      Kept on the phone for every synced quote since 0.8.2 ([ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md)).
- [x] **Scan: choose words on the picture** (done 7 November 2026): Tesseract's hOCR (`extractHocr`) is parsed (`lib/capture/recognised_page.dart`,
      `parseHocr`) into lines and words with boxes; `PageSelector` draws them over the page and `PageSelection` turns the chosen words into text (reading
      order, hyphens mended, a gap kept as a paragraph break). Falls back to plain `read` text when hOCR gives no words. **Not done:** proposing a page
      number and chapter from the page, and zooming the picture.
- [x] **Scan: straighten and crop** (done 7 November 2026): before a photographed page is read, `AdjustScreen` shows it with the tilt and the text's
      area the app worked out (`lib/capture/page_geometry.dart`: `estimateSkewDegrees` by row projection, `textBounds` by the ink's 1st to 99th
      percentile) and lets the reader turn it (-15 to 15 degrees) and drag the frame's corners; `DevicePageAdjuster` renders the turned and cut picture
      with `dart:ui`, no extra package. Selecting the passage on the picture came after (0.4.0). **Not done:** perspective correction.
- [x] **Capture on the Add screen** (done 7 November 2026): Scan a page and Speak are buttons on the quote form; `CaptureScreen` and `VoiceScreen`
      return a `CapturedText` to the form instead of opening a form of their own; the separate Library and work-page entries are removed. Scanned text
      marks the quote `ocr`; spoken text is `manual` (the server accepts only those two).
- [x] **Boards, on the phone** (done 7 November 2026): `boards` table and `quotes.board_id` (schema 6); make, rename, recolour, delete (quotes kept,
      unfiled); file a standalone quote on a board; filter by a board or by none; group by board; boards are in backups. A quote from a work is never on
      a board, as on the server. Synced: see the next item.
- [x] **Share picture, as on the web** (done 8 November 2026, owner's ask): `lib/share/share_picture.dart` draws the web's picture (640 wide at 2x,
      its palettes, the paper grain over the card, block order and gaps, fonts, tag pills, footer and mark) from the same parts the text formats use;
      Light/Dark, the eight materials and the quote colour stripe are chosen and remembered. The text formats were already the web's five. **Added next (8 November 2026):**
      people's portraits as chips or a faded backdrop, signatures, Swap and the actor/character switch (`lib/share/share_people.dart` asks the
      server on demand: `/people`, `/dialogues?movie_id=` for character pictures, `/covers/<file>`); portraits are baked into plain images so their
      edges are clean. Copying the picture to the clipboard came after (0.7.0).
- [x] **A designed look** (done 8 November 2026, owner's ask: "ultra polished"): `lib/theme/app_theme.dart`, bundled Inter and Source Serif 4,
      card lists, grouped Settings, one row of filter chips, empty states, a browser preview (`tool/preview`) to look at every screen. The server screens (statistics, the bin, anthologies, paired devices) and the share
      screen followed the new look in 0.5.0. **Not done:** motion beyond the system's page transitions.
- [x] **Boards sync** (done 8 November 2026, owner's ask): `lib/sync/board_sync.dart`, schema 7 (`boards.server_id`, `synced_hash`, `server_row`;
      `quotes.board_synced`). A board is its name and colour; the server's own row is kept and sent back with each edit because its board PUT replaces
      the whole board. Boards with the same name are linked, not doubled. Both sides changed: the server's wins. A board deleted here is deleted there with
      `move_to` set to another server board; one deleted there is removed here (with the same wipe guard as quotes). A standalone quote's board is
      compared by the server's board id at the last agreement (`board_synced`), kept out of the quote fingerprint so no existing quote looks changed.
      A server with no `/boards` (404) is skipped. Board pictures and a board's own page came after (0.7.0); a board's hidden flag, kind, languages and text order are edited on the phone too (0.7.0).
- [x] **Work details** (done 7 November 2026): a work's page shows the server's description, genres, publisher, pages, ISBN, series and cast (a
      film's cast, a book's characters). Fetched from `GET /books|movies/{id}` and `/{id}/cast` when the page opens if never fetched or over a day
      old (`lib/tools/work_details_source.dart`), kept on the work (`works.details`, schema 5) as read-only metadata outside the sync fingerprint.
      **Not done:** editing any of it on the phone, and details for a work not yet on the server.
- [x] **Covers** (done 7 November 2026): the server's cover and poster pictures show on a work's page and in the works list, fetched once from
      `GET /covers/{name}` into the app's own storage (`lib/library/cover_cache.dart`); Choose a cover sends a gallery picture to
      `POST /books|movies/{id}/cover`. The cover name is kept on the work (`works.cover`, schema 4) as read-only metadata, outside the fingerprint, so
      a cover change is never a conflict. Setting a cover from an online search came after (0.7.0). **Not done:** covers for a work not yet on the server.
- [x] **Automatic sync, deletes, linked duplicates, a Conflicts menu** (done 7 November 2026, as separate pull requests): `AutoSync` runs a push then a
      pull on open, resume, after edits and on a timer with back-off ([ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md));
      deletes go both ways with a wipe guard ([ADR-0017](ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md)); a work or quote on both sides is
      linked, not copied; conflicts wait in Settings > Sync conflicts. Checked against a real local server. **Not verified on a device.** Boards sync and
      the sync on every change came after ([ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md)). Not done:
      a background run with the app closed.
- [x] **Icon, one Share screen, read-aloud voices** (done 7 November 2026): the web app's icon as launcher, adaptive and monochrome
      (themed) icons; one Share screen with the web dialog's formats and Include toggles and defaults (`lib/library/share_format.dart`,
      `lib/screens/share_screen.dart`); Read aloud picks the best installed voice per language and has a settings screen for voice, speed and
      pitch (`lib/speech`). **Not verified on a device:** how the icon looks on a real launcher, and which voices a real phone lists.
- [x] **Work details and reading mode** (done 7 November 2026): counts, chapter groups in reading order, favourites filter, a Read document
      with text size, translations and notes toggles, and Share all.
- [x] **Read aloud** (done 7 November 2026; the owner asked why the app lacked it: it was never planned). Android's own text-to-speech through
      `flutter_tts` (MIT), no audio stored, no server. Read aloud and Stop on the quote screen; read a whole work from the Read screen. With no
      voice for the language it says so in a message (it is not hidden). `lib/speech/speaker.dart` is the interface tests replace.
- [x] **Voice capture, first slice** (done 7 November 2026): Say a quote on the library and on a work: the phone's speech recogniser
      (`speech_to_text`, BSD-3) turns speech into text you correct, then the quote form saves it. No audio is kept by the app. The recogniser is
      the phone's, which may be Google's and online; the screen says so. The server only accepts `manual` and `ocr` as a quote's source, so
      spoken quotes save as `manual` until the server gains `voice` (a server change, not made). Not yet: keeping the recording beside the quote.
- [ ] **Voice capture, original note** (owner, 6 November 2026: "a way to record sound and save from there"). **Assumed, to be confirmed before it is
      built:** record on the phone, turn the speech into text on the phone (no audio leaves it, and nothing proprietary: the app is GPL-3.0),
      correct the text on the same screen as camera capture, save it as a quote, and keep the recording beside the quote only if the reader
      asks. Open: which on-device speech engine, and whether the server may hold the audio (it has no place for it today).
- [x] **Pull sync** (done 6 November 2026): brings down what is new or changed on the server, sends up the phone's own edits, and leaves what
      changed on both sides to the reader. **Decided by the owner: a conflict is chosen per quote and per work, with both "keep the phone's"
      and "keep the server's" always on offer** ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md)). Built on a stored
      fingerprint of what both sides last agreed, not on timestamps. Checked against a real local server; not verified on a device.
- [x] **Metadata lookups through the server** (owner, 6 November 2026; the lookups and cover search are built, see *Metadata lookup, first slice* above): the app uses the server's own routes for TMDB, TVDB and the other
      suppliers (`/books/lookup`, `/movies/lookup`, the cast and people routes), so the provider keys live only on the server and are set
      up there. The app holds no supplier key. These need a paired server and are part of phase 3 (metadata and people).
- [ ] **All functions, phases 1 to 4 of feature 5, before any new feature** (owner's order, 6 November 2026): core, reading side,
      management, settings and admin. Phases 1 to 4 are built. What is left is the server features the app has no screen for (find and replace,
      stickers, fonts, the server's own exports, cast editing, re-reads), and which of those "all" still includes is the owner's to say.
- [ ] **New features, after the functions:** capture is built (camera, Tesseract OCR, straighten and crop, selection on the photo, correction screen,
      saving to the local library, the sync push when paired) except the page and chapter proposal; donation and bug report are not.
- [x] **Update:** the check and installer, the `app-v*` release lookup and the manifest pieces (done with the harness), and the release
      workflow that publishes what the check looks for (in use since `app-v0.2.0`, see [Releasing](Releasing.md); the owner is testing the in-app update).
- [x] **Everything available offline, and synced when connected** (owner, 13 November 2026, [ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md);
      to land in 0.8.2): every screen that reads the server keeps its last answer and shows it, dated, with no server; anthologies (their entries, headings,
      commentary, grouping, front matter, cover picture and fill) are made and edited offline and go up in order; a setting changed offline is kept and sent
      unless the web changed it meanwhile; the context of every synced quote is kept on the phone; the admin section shows with no server. **Not done:** a
      count of what a fill would find and an EPUB need the server; source files stay on the server (only the list and each quote's context are kept); a crash
      between sending a queued change and saving the queue is safe against a server on 3.9.0 or later (Idempotency-Key, built in 0.9.0); an older server may make a new anthology or heading twice.
      Built in 0.9.0: covers, cast and details kept after every sync ([#88](https://github.com/aaronified/tippani-app/issues/88)); a cover or poster picked
      offline shown at once ([#92](https://github.com/aaronified/tippani-app/issues/92), without the "waiting" mark ([#96](https://github.com/aaronified/tippani-app/issues/96)) and without a size ceiling on the cover folder ([#95](https://github.com/aaronified/tippani-app/issues/95)); tag rename, colour, style and delete, bin restore and context rules waiting
      offline ([#91](https://github.com/aaronified/tippani-app/issues/91)). Account, people and Checks decisions still need the server.
      Which questions each review deck asks is built, and the rest of the web's settings are web-only on purpose ([#89](https://github.com/aaronified/tippani-app/issues/89), [ADR-0023](ADR-0023-Which-Server-Settings-The-Phone-Offers.md)). Jobs for every reader is built ([#90](https://github.com/aaronified/tippani-app/issues/90)). Unpair every device is built ([#93](https://github.com/aaronified/tippani-app/issues/93)). **Reset all data is deliberately not on the phone**: it deletes every account's library on
      the server, needs a downloaded safety copy the phone cannot check the owner has kept, and is one tap from a wrong screen. It stays on the web.
- [x] **A Server tab that is all server management** (owner, 13 November 2026; to land in 0.8.2): metadata, Checks and the bin were already there; the account,
      language, text and quotes, colours, sections (with the bin's keep time), daily review and context rules moved in as **Your settings on the server**. Settings
      keeps the app's own: app colours, tags (library data), reading aloud, updates, backup, the log and the licences.
      **Not done, filed as issues:** the web's theme, language, font and size, review-tuning and dock-order settings ([#89](https://github.com/aaronified/tippani-app/issues/89)); Jobs for
      every reader, not only the administrator ([#90](https://github.com/aaronified/tippani-app/issues/90)); reset-all and revoke-every-device ([#93](https://github.com/aaronified/tippani-app/issues/93)).
- [ ] **Donation:** port the section, regenerate the QR, the disclaimer.
- [ ] **Bug report:** the form, `app-feedback-mail.yml`, `scripts/mail_to_issues.py` and its tests.
- [x] **Release workflow:** `release.yml` with signing and verification, and the decision pages (run for every release since `app-v0.2.0`).
- [x] **First signed APK:** `app-v0.2.0`, 6 November 2026.
- [x] Phases 2 to 4 of feature 5 (built across 0.2.0 to 0.8.1; see the changelog).
- [ ] Docs: user page for the app, Developing's file map and CI table, the Roadmap, the changelog.

## Out of scope

iOS; the Play Store; textures and material sets in the first version; server-side OCR.

See also: [Plans index](https://github.com/aaronified/tippani/blob/main/docs/wiki/Plans-Index.md) · [Roadmap](https://github.com/aaronified/tippani/blob/main/docs/wiki/Roadmap.md) · [Developing](https://github.com/aaronified/tippani/blob/main/docs/wiki/Developing.md) · [Home](https://github.com/aaronified/tippani/blob/main/docs/wiki/Home.md)
