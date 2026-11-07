# Tippani for Android: the plan

Source of truth: this file. Moved here from the Tippani repository's wiki (`Plan-Android-App.md`, roadmap §20) when the app
got its own repository; the move is recorded in Tippani's ADR-0931.

Not built. Written against Tippani `558059cf` (main, 25 October 2026), and moved on 6 November 2026. The server half exists in
[Tippani](https://github.com/aaronified/tippani); the app does not. This plan is the app's feature list, what to reuse from
Lexodle and Fluenough, the release and signing set-up, and the open questions.

**Where things are now.** The app is in this repository, at its root, not in a `mobile/` directory of Tippani. Where the text below says
`mobile/`, read the repository root. Where it says a file is in Tippani (`internal/httpapi/...`), it still is. Server work the app needs
is filed as issues on Tippani; this repository's issues are the app's.

## What the app is

A native Flutter client for Android, in `mobile/`, for one reader's own Tippani server. It is not a wrapper around
the web app. Its first job is the one thing a web page does badly on a phone: photograph a page of a book and turn
a highlighted passage into a quote. It also does the rest of what Tippani does (see feature 5).

Android only. No `ios/` directory ships, because building and signing for iOS needs a Mac. The Dart stays
platform-neutral.

## What the server already gives it

All of this is built (the files are named below):

- **Pairing.** Settings shows a QR code (`POST /auth/devices/pair`, valid 5 minutes, single use). The app scans it and
  claims it (`POST /auth/devices/claim`, rate limited) for a **device token**. Tokens are listed and revoked in
  Settings (`GET/DELETE /auth/devices`). `internal/httpapi/pairing_handlers.go`.
- **Version handshake.** `GET /capabilities` needs no credential and returns an `apiRevision` integer, so the app can
  tell whether it and the server are compatible before it holds a token. `internal/httpapi/capabilities_handler.go`.
- **Offline-friendly writes.** `noted_at` on create keeps a queued capture's real date; a duplicate answers `409` with
  the existing row, so retrying a flush is safe.
- List paging, gzip, and the shared quote shape.

What the server lacks for this plan (small, listed under Tasks): a shared text-cleanup step for captured text, a
photo kept with a quote, and an app-release feed that does not mix with the server's releases.

## Decisions to confirm

1. **Package id.** Suggest `io.github.aaronified.tippani` (Lexodle uses `io.github.aaronified.lexodle`).
2. **A new keystore for this app.** Reusing Lexodle's would tie two apps' security together. The owner supplies it as
   repository secrets (below).
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
  duplicate still makes a retry safe. Who wins on a conflict, and whether a pull is automatic, are decided when sync is built and
  are the owner's call; until then it is push only.
- **Leaving no door shut.** An unpaired phone can export its library as Tippani's own Markdown format, which the server already
  imports, so a reader who starts alone and later installs a server loses nothing.
- **Backup and restore carry the local library** (the harness's `BackupContributor` is where it registers), so a phone that is
  the only copy of someone's quotes can be backed up and restored.
- **What needs a server stays labelled as needing one:** the server log, the device list, the server's metadata lookups, shared
  anthologies and boards. Home no longer opens on "not connected"; it opens on the library.
- **What works alone, decided by the owner (6 November 2026): the core.** The library, quotes, search, add/edit/tag, the daily quiz,
  boards and anthologies, and export/import run on the local database. **Management and admin screens need a paired server and say
  so:** metadata sources, Checks, jobs, library folders, source files and context, the server log, the device list. They are
  built (phases 3 and 4) but are only reachable when paired; an unpaired phone shows them as "needs your Tippani server".
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
- Automatic checking is **off by default** (each check is a request to GitHub), as in both apps. Manual check always
  works.
- **The app is released on its own tags.** Tippani's server releases use `vX.Y.Z` and `releases/latest` points at
  them. The app uses tags `app-vX.Y.Z`, and the update check lists releases and picks the newest `app-v*` one, not
  `/latest`.
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
- **Layout.** `mobile/` holds a committed `android/` (Lexodle's way; Fluenough generates it in CI). The wiki, the
  file map in Developing and the CI table are updated with it.

## Tasks

- [ ] Re-verify this plan against the code before starting; correct what moved.
- [ ] **Server:** shared text-cleanup step for captured text (roadmap §7); a nullable photo on a quote; confirm the
      `apiRevision` covers what the app needs and bump it.
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
      Left for later phases: sorting choices, bulk selection, the quote's colour board.
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
      saves it with `source: ocr`. **Not yet:** selecting lines on the photo, proposing page and chapter, straightening and cropping, other
      languages (Bengali `ben`), and an unverified run on a real phone.
- [x] **Metadata lookup, first slice** (done 7 November 2026): Look up details on the work form, through the server's `/books/lookup` and
      `/movies/lookup` (so no provider key is in the app). Books checked against a real server (Open Library); films, shows and games are
      built from the Go handler's shape but **not verified**, because the local server had no TMDB or TheTVDB key. Fills title, author,
      year. **Not yet:** covers, genres, description, ISBN lookup, choosing a source.
- [x] **Bin and statistics** (done 7 November 2026): from the paired server's `/trash` and `/stats`: list, restore, delete for good, empty;
      totals, busiest month, most quoted, top tags. Checked against a real server in `test/live`. **Not yet:** the bin's per-entry detail,
      statistics breakdowns (authors, actors), checks, metadata lookups, boards.
- [x] **Anthologies, first slice** (done 7 November 2026): kept on the server, not copied to the phone (management screens need a paired
      server, the owner's decision): list, make, rename (the server's own row is sent back with only the title and introduction changed, so
      its display switches survive), delete, read, share as text, take a passage out, and Add to anthology from a synced quote.
      Checked against a real server in `test/live`. **Not yet:** reordering, per-passage commentary, sections, grouping, the cover, boards.
- [x] **Scan: straighten and crop** (done 7 November 2026): before a photographed page is read, `AdjustScreen` shows it with the tilt and the text's
      area the app worked out (`lib/capture/page_geometry.dart`: `estimateSkewDegrees` by row projection, `textBounds` by the ink's 1st to 99th
      percentile) and lets the reader turn it (-15 to 15 degrees) and drag the frame's corners; `DevicePageAdjuster` renders the turned and cut picture
      with `dart:ui`, no extra package. **Not done:** selecting words on the picture before reading (next), and perspective correction.
- [x] **Capture on the Add screen** (done 7 November 2026): Scan a page and Speak are buttons on the quote form; `CaptureScreen` and `VoiceScreen`
      return a `CapturedText` to the form instead of opening a form of their own; the separate Library and work-page entries are removed. Scanned text
      marks the quote `ocr`; spoken text is `manual` (the server accepts only those two).
- [x] **Boards, on the phone** (done 7 November 2026): `boards` table and `quotes.board_id` (schema 6); make, rename, recolour, delete (quotes kept,
      unfiled); file a standalone quote on a board; filter by a board or by none; group by board; boards are in backups. A quote from a work is never on
      a board, as on the server. **Not done: syncing boards.** The server has `/boards` and a `board_id` on each standalone quote; pulling and pushing
      those needs the quote fingerprint to carry the board's server id and boards to get server ids of their own.
- [x] **Work details** (done 7 November 2026): a work's page shows the server's description, genres, publisher, pages, ISBN, series and cast (a
      film's cast, a book's characters). Fetched from `GET /books|movies/{id}` and `/{id}/cast` when the page opens if never fetched or over a day
      old (`lib/tools/work_details_source.dart`), kept on the work (`works.details`, schema 5) as read-only metadata outside the sync fingerprint.
      **Not done:** editing any of it on the phone, and details for a work not yet on the server.
- [x] **Covers** (done 7 November 2026): the server's cover and poster pictures show on a work's page and in the works list, fetched once from
      `GET /covers/{name}` into the app's own storage (`lib/library/cover_cache.dart`); Choose a cover sends a gallery picture to
      `POST /books|movies/{id}/cover`. The cover name is kept on the work (`works.cover`, schema 4) as read-only metadata, outside the fingerprint, so
      a cover change is never a conflict. **Not done:** setting a cover from a lookup result, covers for a work not yet on the server.
- [x] **Automatic sync, deletes, linked duplicates, a Conflicts menu** (done 7 November 2026, as separate pull requests): `AutoSync` runs a push then a
      pull on open, resume, after edits and on a timer with back-off ([ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md));
      deletes go both ways with a wipe guard ([ADR-0017](ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md)); a work or quote on both sides is
      linked, not copied; conflicts wait in Settings > Sync conflicts. Checked against a real local server. **Not verified on a device.** Not done:
      sync of boards, a background run with the app closed, reacting to the network returning.
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
      fingerprint of what both sides last agreed, not on timestamps. Not yet tried against a real server or a phone.
- [ ] **Metadata lookups through the server** (owner, 6 November 2026): the app uses the server's own routes for TMDB, TVDB and the other
      suppliers (`/books/lookup`, `/movies/lookup`, the cast and people routes), so the provider keys live only on the server and are set
      up there. The app holds no supplier key. These need a paired server and are part of phase 3 (metadata and people).
- [ ] **All functions, phases 1 to 4 of feature 5, before any new feature** (owner's order, 6 November 2026): core, reading side,
      management, settings and admin. The core works alone; the management and admin screens need a paired server.
- [ ] **New features, after the functions:** capture (camera, Tesseract OCR, selection on the photo, page and chapter proposal,
      correction screen, saving to the local library, and the sync push when paired), donation, bug report, signed release.
- [x] **Update:** the check and installer, the `app-v*` release lookup and the manifest pieces (done with the harness), and the release
      workflow that publishes what the check looks for (scaffolded; needs the owner's keys, see [Releasing](Releasing.md)).
- [ ] **Donation:** port the section, regenerate the QR, the disclaimer.
- [ ] **Bug report:** the form, `app-feedback-mail.yml`, `scripts/mail_to_issues.py` and its tests.
- [x] **Release workflow:** `release.yml` with signing and verification, and the decision pages (scaffolded, not yet run).
- [ ] **First signed APK:** needs the five secrets from the owner, then a run of the workflow as `0.1.0`.
- [ ] Phases 2 to 4 of feature 5.
- [ ] Docs: user page for the app, Developing's file map and CI table, the Roadmap, the changelog.

## Out of scope

iOS; the Play Store; textures and material sets in the first version; server-side OCR.

See also: [Plans index](https://github.com/aaronified/tippani/blob/main/docs/wiki/Plans-Index.md) · [Roadmap](https://github.com/aaronified/tippani/blob/main/docs/wiki/Roadmap.md) · [Developing](https://github.com/aaronified/tippani/blob/main/docs/wiki/Developing.md) · [Home](https://github.com/aaronified/tippani/blob/main/docs/wiki/Home.md)
