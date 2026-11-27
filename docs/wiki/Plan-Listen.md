# Plan: listen to Audiobookshelf, keep Grimmory books, bookmark by voice

**Status:** plan only, nothing built. Written 27 November 2026 against `90606c9` (branch `claude/relaxed-hopper-15k6h7`, tip at writing).
Mockups: `docs/design/listen-mockups.html` in the repository (the wiki is published flat, so it is named here and not linked). Decisions to record as ADRs when built are in [Decisions](#decisions).

## What the owner asked for

1. Listen to Audiobookshelf (ABS) books in the app, with a working Android Auto player and audio cached offline.
2. Bookmark easily while driving. A bookmark carries a transcript of the surrounding audio, made by Whisper on the phone.
3. Connect to a Grimmory instance, download books and sync bookmarks. Reading an EPUB comes later.
4. Everything signs in through Authelia (OIDC). The owner runs the latest ABS and Grimmory, reached over Twingate (no extra provisioning).
5. Whisper also transcribes dictated quotes ("when I am talking for a quote").
6. Every setting is per user. Fixed first, in `5a18e09` and `90606c9` ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md)).
7. Open question to the owner: a library with up to three aspects per work (audiobook, book file, quotes only). Options and a recommendation are under [Navigation](#navigation-and-the-library).

## Rulings already made

| Question | Answer (owner, 27 November 2026) | Recorded as |
|---|---|---|
| How does Authelia protect ABS and Grimmory | Both are OIDC clients of Authelia | [Auth](#sign-in) |
| Where does traffic go | Phone talks to ABS and Grimmory directly; Tippani server only receives quotes | [Architecture](#architecture) |
| What "transcribed context" means | Whisper transcribes the book audio around the bookmark | [Bookmark pipeline](#the-bookmark-pipeline) |
| Install route | Sideload the APK; Android Auto's "Unknown sources" developer setting is switched on once | [Distribution](#distribution) |
| Where a bookmark is saved | An ABS bookmark and a Tippani quote | [Bookmark pipeline](#the-bookmark-pipeline) |
| Whisper model | English base by default, with small and multilingual as options | [Whisper](#whisper-on-the-phone) |
| Offline policy | Download whole books on demand, plus a rolling buffer ahead of the playing book | [Offline](#offline-audio) |
| Grimmory transport | Native REST API | [Grimmory](#grimmory) |
| Bookmark triggers | On-screen Android Auto button, phone notification action and widget. No physical button | [Triggers](#triggers) |
| Network | Twingate; same as Tippani | [Network](#network-and-offline-behaviour) |
| Versions | Latest of both | [Unverified](#what-is-verified-and-what-is-not) |
| When Whisper runs | After a bookmark (an idle job) and while dictating a quote | [Whisper](#whisper-on-the-phone) |

## What is verified and what is not

Confidence: **V** read on a primary page or source this session; **U** unverified (memory or search snippet), to be checked by task T0; **I** inference.

| Fact | Level | Source |
|---|---|---|
| Android Auto needs the `automotive_app_desc` manifest entry (`uses name="media"`) and a `MediaLibraryService` or `MediaBrowserService` | V | developer.android.com/training/cars/media/configure-manifest |
| Root of the browse tree is shown as tabs, normally 4; Android Auto has no pagination | V | developer.android.com/training/cars/media/create-media-browser/content-hierarchy |
| Custom now-playing button: Media3 `CommandButton` + `onCustomCommand`; allowed for the Android Auto controller only if added for `isAutoCompanionController` | V | developer.android.com/media/media3/session/control-playback |
| How many custom buttons Android Auto draws | U | not documented on pages read; overflow when space runs out |
| Sideloaded media apps show in Android Auto after "Unknown sources" is on | V | developer.android.com/training/cars/testing |
| Play tracks: internal sharing and internal testing need no review (not used; sideload chosen) | V | developer.android.com/training/cars/distribute |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` + `foregroundServiceType="mediaPlayback"` required from API 34 | V | developer.android.com/develop/background-work/services/fgs/service-types |
| Media3 leaves the foreground after 10 minutes paused; `onPlaybackResumption` is the recovery path | V | developer.android.com/media/media3/session/background-playback |
| Volume-key presses cannot be used for the bookmark | U | not proven impossible; dropped by the owner's choice |
| whisper.cpp is MIT; ggml weights base 148 MB, base q5_1 60 MB, small 488 MB, small q5_1 190 MB; RAM about 388 MB (base) and 852 MB (small) | V | github.com/ggml-org/whisper.cpp, huggingface.co/ggerganov/whisper.cpp |
| `whisper_ggml` 2.10.0 is MIT, bundles whisper.cpp 1.9.5, Android API 24+, runs on a background isolate | V | pub.dev/packages/whisper_ggml |
| Whisper real-time factor on the owner's phone | U | no official figure; benchmark in spike S1 |
| Grimmory: `POST /api/v1/auth/login`, `/auth/refresh`; OIDC mobile: `GET /api/v1/auth/oidc/state` then `POST /api/v1/auth/oidc/mobile/callback` (`code`, `code_verifier`, `redirect_uri`, `nonce`, `state`) returning Grimmory's own JWTs | V | grimmory-tools/grimmory `develop`, `OidcAuthController.java` |
| Grimmory mobile redirect must be a non-http(s) scheme; default allow-list `grimmory://oauth2-callback`, admin can add more or set `*` (`oidcRedirectUris`) | V | `OidcAuthService.java` |
| Grimmory `GET /api/v1/books/page`, `/libraries`, `/shelves`, `GET /books/{id}/download` (streamed), `/api/v1/bookmarks` CRUD (`cfi`, `pageNumber`, `positionMs`+`trackIndex`, `title`, `notes`, `color`, `priority`), `/api/v1/annotations` CRUD, `POST /api/v1/books/progress` | V | grimmory-tools/grimmory `develop` controllers and DTOs |
| Grimmory `BookFileProgress` fields, GET for progress, range/resume on download, OpenAPI schema | U | send `/api/openapi.json` (`API_DOCS_ENABLED=true`) |
| ABS 2.26.0 introduced JWT access and refresh tokens; ABS has its own "Allowed Mobile Redirect URIs"; official app uses `audiobookshelf://oauth` | U | search snippets only; docs host blocked |
| ABS route names and payloads for login, library, play session, session sync, local progress, bookmarks, downloads | U | from memory, not read; T0 reads them |
| Authelia public clients, PKCE, custom-scheme redirects, refresh-token lifespans, device grant | U | docs host blocked; latest release seen v4.39.28 |
| Quote `source` accepts only `manual` and `ocr` on the server | V | `lib/library/models.dart:590` (`this.source = 'manual'`) and Plan.md, voice capture |

## What already exists in the app

Pinned at `90606c9`. Re-verify with task T0.

| Piece | Where | State |
|---|---|---|
| Work with `kind`, `creator`, `cover`, `details` (status, progress) | `lib/library/models.dart:16` `class Work`; `:3` `enum WorkKind { book, film, show, game, other }` | Built; no notion of an audiobook or a book file |
| Local SQLite library, schema 7 | `lib/library/library_store.dart:193` `static const schemaVersion = 7` | Built; the next migration adds the media tables (number allocated at build time) |
| List row for a work | `lib/screens/library_widgets.dart:339` `class WorkTile` | Built; will show edition glyphs |
| Per-account preferences | `lib/settings/preference_scope.dart` `class PreferenceScope`, `PrefKeys` | Built; every new setting joins `PrefKeys` |
| Pairing, token in secure storage | `lib/app_controller.dart:181` `Future<PairResult> pair(`; `lib/settings/settings_store.dart` `SecureTokenVault` | Built; one token for the Tippani server only |
| Offline answers kept for the server | `lib/api/offline_cache.dart` `class OfflineCache` | Built; media does not reuse it (see Architecture) |
| Sync that never stops for a conflict, once a day and on change | `lib/sync/auto_sync.dart:141` `Timer.periodic(checkEvery` ([ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md), [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md)) | Built |
| Dictating a quote with the phone's recogniser | `lib/capture/voice_listener.dart:1` `import 'package:speech_to_text/...'` | Built; gains a Whisper engine |
| `RECORD_AUDIO` and `INTERNET` permissions | `android/app/src/main/AndroidManifest.xml:4-6` | Built |
| Native Kotlin and the manifest | `android/app/src/main/kotlin`, `AndroidManifest.xml` | Built; will gain a media service |
| Audio playback, downloads, OIDC, Whisper, bookmarks | none | Missing |

**In flight at the pin:** not audited. The remote has many older feature branches; this plan was not checked against any of them. T0 lists open branches and pull requests that touch the paths it cites, and re-checks `CHANGELOG.md` and `ADR-Index.md` for numbers taken after `ADR-0034`.

## Architecture

```
 Phone
 ┌───────────────────────────── Flutter (Dart) ─────────────────────────────┐
 │ Library UI · Work page · Player UI · Bookmarks · Settings → Libraries      │
 │ MediaApi (channel client) · Sources & sign-in · Editions in library.db     │
 └───────────────▲───────────────────────────────────────▲───────────────────┘
        MethodChannel / EventChannel                  sqflite
 ┌───────────────┴────────────── Kotlin (native) ────────┴───────────────────┐
 │ ListenService : MediaLibraryService (ExoPlayer, browse tree, resumption)    │
 │ listen.db (items, tracks, progress, downloads, bookmarks, transcript jobs)  │
 │ DownloadWorker (WorkManager) · PcmTap (audio processor) · TranscribeWorker  │
 └───────────────▲──────────────────────────────▲────────────────────────────┘
                 │ HTTPS (Twingate)              │ HTTPS
        Audiobookshelf (OIDC via Authelia)   Grimmory (OIDC via Authelia)
                                  Tippani server: quotes only (existing sync)
```

**Native owns playback and media state.** Android Auto binds to the service while the phone is locked and the Flutter engine may not be running, and it asks for the browse tree and for resumption at boot with no network. Anything the service must answer without a UI therefore lives where the service can read it: a native SQLite file, `listen.db`. Dart reads and writes it through the channel. `library.db` keeps works, quotes and the links from a work to its editions.

Alternatives weighed:

| Option | For | Against | Verdict |
|---|---|---|---|
| Kotlin Media3 service, native `listen.db` | Fits Android Auto's lifecycle; Media3 is Apache-2.0; ExoPlayer decodes MP3, M4B, Opus | Two databases; native code to own | **Chosen** |
| `audio_service` 0.18.19 + `just_audio` | Less native code; Android Auto listed | Legacy browse service, browse depth and custom-action support unverified, UI-engine dependent | Fallback if spike S3 shows the native route too costly |
| Route through the Tippani Go server | One place for credentials | New backend, extra hop, breaks offline, puts ABS and Grimmory credentials on a server | Rejected by the owner |

**Credentials never leave the phone.** Tokens for ABS and Grimmory sit in secure storage under the account scope (`server|name`, as `PreferenceScope`), never in a backup, a log or a Tippani sync. Consequence: a second phone signs in to ABS and Grimmory itself and re-links editions by matching.

**Works alone** ([ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md)): with no source configured the app behaves exactly as today. Media screens say what is missing.

## Sign in

Both services are Authelia OIDC clients. The app does not talk to Authelia's token endpoint; each service does the code exchange and hands back its own token. The app needs a browser round trip and a registered return address.

| Step | Audiobookshelf | Grimmory |
|---|---|---|
| Start | Custom Tab to `{abs}/auth/openid` with PKCE challenge and the app's redirect (U) | `GET /api/v1/auth/oidc/state`, then Custom Tab to Authelia's authorize endpoint with PKCE and a nonce (V) |
| Return | `tippani://oauth/abs` (U) | `tippani://oauth/grimmory` (V: any non-http scheme the admin allows) |
| Finish | App completes with its verifier and receives an ABS user and token (U) | `POST /api/v1/auth/oidc/mobile/callback` returns access and refresh tokens (V) |
| Refresh | JWT access (about 1 h) and refresh (about 30 d) tokens from v2.26 (U) | `POST /api/v1/auth/refresh` (V) |

**Owner actions before first sign in** (listed so none is a surprise):

1. ABS: add `tippani://oauth/abs` to "Allowed Mobile Redirect URIs" (U, check wording).
2. Grimmory: add `tippani://oauth/grimmory` to `oidcRedirectUris`, or set `*`.
3. Authelia: add the same redirect URIs to each service's client, and confirm each client is `public` with PKCE `S256` (U until Authelia's docs are read).

The redirect arrives through an Android intent filter for the `tippani` scheme into `MainActivity`, then a channel to Dart. No AppAuth dependency: `url_launcher` (already in `pubspec.yaml`) opens the browser, and PKCE needs a SHA-256 of the verifier, which the Kotlin side computes with `MessageDigest` over the channel (`package:crypto` is not a dependency and is not added for one hash).

**Offline for days.** Access tokens expire in about an hour. A refresh that fails while there is no network is not a sign-out: playback, downloads and bookmarks keep working from `listen.db`. Only an explicit refusal of the refresh token while online marks the source "sign in again", with downloaded books still playable. If Authelia's refresh lifetime is shorter than the longest trip, the sign-in is repeated on return (T0 reads the real lifetimes).

**Legacy and API-key fallbacks.** ABS API keys are for scripts (U); Grimmory has none. Neither is used. A username and password login stays available per source for a server that has OIDC switched off.

## Audiobookshelf

All routes are **U** until T0 reads `api.audiobookshelf.org` or the repo. Candidate calls from memory, to verify, not to build from:

| Need | Candidate route |
|---|---|
| Libraries, items, series, search, covers | `GET /api/libraries`, `/api/libraries/{id}/items`, `/api/items/{id}`, cover under `/api/items/{id}/cover` |
| Start playback | `POST /api/items/{id}/play` returns a session with audio tracks and chapters |
| Keep the session | `POST /api/session/{id}/sync`, `/close` |
| Progress | `PATCH /api/me/progress/{id}`; offline sessions uploaded through `/api/session/local` or `/local-all` |
| Download audio | per-file download route under `/api/items/{id}/file/{ino}` |
| Bookmarks | `POST /api/me/item/{id}/bookmark` with `time` and `title`, update and delete by `time` |
| Long bookmark titles | unknown; the plan stores a short excerpt in the title and the full transcript in Tippani |

Streaming sends the token in an `Authorization` header through an OkHttp data source, never in the URL, so it cannot land in a proxy log.

## Playback engine and Android Auto

**Native `ListenService`** (Media3 `MediaLibraryService`, ExoPlayer):

- Manifest: `automotive_app_desc` (`uses name="media"`), the two Media3 intent filters, `foregroundServiceType="mediaPlayback"`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`.
- Player: chapters from the ABS item, speed 0.5x to 3x with pitch kept, sleep timer (end of chapter, N minutes), skip back 15 s and forward 30 s (settings), smart rewind after a long pause. Gapless across tracks of one book.
- **No autoplay on connect** (quality rule MA-1): the first playback state is paused.
- `onPlaybackResumption`: restores the last item and position from `listen.db`, using local data only when the phone just booted.

**Browse tree** (root tabs are limited to 4 and must be browsable):

| Root tab | Children | Why first |
|---|---|---|
| Continue | In-progress books, most recently played first | What a driver does most |
| Downloaded | Books fully cached, whole shelf | Works with no signal |
| Library | ABS libraries, then series, authors, items (depth kept to what Android Auto allows; limits U) | Browse |
| Bookmarks | Recent bookmarks; tap seeks to the moment | The feature that motivates this plan |

An item is browsable into its chapters (each playable). `onGetSearchResult` serves the on-screen search; voice search ("play X") arrives as a search query and is handled the same way. How Assistant routes "from Audiobookshelf" is U.

**Now playing:** a **Bookmark** custom button (Media3 `CommandButton`, session command `BOOKMARK`, added for the Android Auto controller). It swaps to a tick icon for two seconds after a press, since a car screen has no toast. Skip buttons are reserved so the bookmark button does not sit in an overflow menu (slot reservation; how many custom buttons Android Auto draws is U).

### Triggers

| Trigger | Surface | Notes |
|---|---|---|
| Bookmark button | Android Auto now-playing | Verified route |
| Notification action | Phone lock screen and shade | Media3 custom layout |
| Home-screen widget | Phone | Plain App Widget; bookmark and play/pause |
| In-app button | Player screen | Always |
| Physical buttons | none | The owner's ruling. Volume-key interception is not offered |

### Distribution

Sideloaded APK from GitHub releases ([Releasing](Releasing.md)). Android Auto shows it only after the owner enables Android Auto's developer mode (tap the version row ten times) and "Unknown sources". The trade-off against Play internal testing was explained and Plan.md keeps the Play Store out of scope, so no ADR reverses it.

## Offline audio

| Mode | Behaviour | Where it is stored |
|---|---|---|
| Download (manual) | A book's files are fetched in order, resumable, with progress on the Downloads screen; never evicted | `files/listen/{source}/{item}/` inside the app's own storage |
| Rolling buffer | While a book plays, the next N hours are fetched ahead (default 3 h) and tracks more than M hours behind are dropped (default 1 h) | Same folder, marked `buffer` |
| Stream | Anything not cached plays over the network | ExoPlayer `SimpleCache`, bounded (default 512 MB) |

Settings per account: Wi-Fi only (default on), storage ceiling (default 5 GB), buffer ahead and behind, delete after finishing. Eviction takes buffer files first, oldest played first; manual downloads are only removed by the reader.

Downloads run in a `WorkManager` worker (Apache-2.0) with a foreground notification, resuming with `Range` requests where the server honours them (ABS: U; Grimmory: U). A file is checked by size against the item's reported size before it is marked complete.

## Progress sync

- The position is written to `listen.db` every few seconds while playing, tagged with the device and a time.
- While online, the app keeps an ABS play session and sends the position about every 15 seconds **only during playback**. This is a timer that exists while audio is playing and stops when it stops; it is not an idle wake ([ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md) forbids retry timers, not a playback clock; record this in the new ADR).
- Offline listening is uploaded as a local session when the phone next reaches ABS (route U).
- **Conflict:** opening a book whose ABS position is newer than the phone's and differs by more than a minute asks once, per item: "Continue from 41:10 on this phone" or "Jump to 55:00 from Pixel" ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md): chosen per item, never by rule).
- The work's shelf status and percentage (`work.details.status`, `progress`) follow the audiobook's progress while it is the active edition.

## The bookmark pipeline

```
press ─▶ [1] bookmark row (instant) ─▶ [2] audio window captured ─▶ [3] transcription job (idle)
        ─▶ [4] ABS bookmark title + [5] Tippani quote with the transcript
```

1. **Instant.** The native service writes a bookmark (item, track, position, time, state `pending`) before doing anything else, then posts it to ABS when online. Pressing never waits on Whisper.
2. **Capture the audio.** Two designs; the plan picks one in spike S2.
   - **A. PCM tap (preferred).** An audio processor ahead of speed adjustment keeps the last 90 s of decoded audio, downmixed to 16 kHz mono, in a ring buffer (about 2.9 MB). On a press it is copied out and capture continues for the after-window. No file slicing, no MediaCodec, works for streamed and cached audio, any codec ExoPlayer plays. Weakness: right after a seek the ring holds only audio since the seek.
   - **B. Slice the cached file.** `MediaExtractor`/`MediaCodec` plus a resampler. Exact for downloaded books, fails for streamed ones without more work.
   - Default window: 45 s before and 15 s after (a press follows the line that mattered). Both settings per account.
3. **Transcribe when idle.** A job row is queued. It runs when playback has been paused for 30 s, when the phone is charging, or when the app opens, and battery is not low. It never runs while a book plays, because Whisper at full CPU in a warm car costs battery and stutter. A driver therefore gets a transcript by the time they park.
4. **ABS bookmark.** The pending bookmark's title is replaced with a short excerpt (length limit U); the transcript never depends on ABS accepting a long title.
5. **Tippani quote.** A quote on the linked work (created if none), text = the transcript, location = the time and chapter ("3:42:10 · Chapter 14"), source `manual` until the server accepts `voice`, a note "From a bookmark", tagged `bookmark`. The window's edge words are trimmed to whole words and marked `…`. It saves to the local library, so it works with no server and is pushed by the ordinary sync.
   **Decision D-Q for the owner:** this creates a quote for every bookmark. Recommended instead: the quote is created at once but opens in a **Trim** step on the Bookmarks screen (select the sentence, discard the rest, or keep it all). Cost: one extra tap per bookmark. Benefit: the library does not fill with 60-second transcripts.
6. Failure leaves the bookmark and a retry; the bookmark exists whether or not Whisper ever runs.

Bookmarks from other ABS clients appear in the app with no transcript and a "Transcribe" action that uses the cached file (design B, so B is built for cached books in the same phase).

## Whisper on the phone

| Setting | Default | Options |
|---|---|---|
| Model | English base (`base.en`, q5_1, about 60 MB) | base q8_0 (82 MB), base fp16 (148 MB), small q5_1 (190 MB), small fp16 (488 MB); multilingual variants |
| Language | English | Auto-detect, or pick (Bengali and Hindi follow the app's own locales) |
| Window | 45 s before, 15 s after | 10 s to 120 s |
| Run when | Idle | Also "right away when the app is open" |

- **Binding:** `whisper_ggml` (MIT, active, API 24+) is the working assumption. Spike S1 settles whether it can run from a `WorkManager` job with no UI (a headless Flutter engine) or whether the transcribe worker is whisper.cpp through JNI, as whisper.cpp's own Android example does. The JNI route removes the Dart dependency for idle jobs and costs native build maintenance.
- **Models are downloaded on demand** from Hugging Face (`ggerganov/whisper.cpp`), with a checksum, shown on a Models screen with size and delete. They are never in a backup and never bundled (the APK stays small).
- **Dictating a quote.** The Speak step on the quote form gets an engine choice: the phone's recogniser (today, may use Google online) or Whisper (offline). Whisper records through a small native 16 kHz mono recorder, transcribes when the reader stops, and lands in the same correction screen. Streaming partial text is not planned.
- **Privacy:** audio never leaves the phone; transcripts are text in the library like any quote. This is a feature the Tippani server cannot offer.
- **Licences:** whisper.cpp MIT, weights MIT/Apache-2.0 per the Hugging Face and OpenAI pages, Media3 and WorkManager Apache-2.0: compatible with GPL-3.0 ([ADR-0002](ADR-0002-Licence-Is-GPL-3.0-And-Nothing-Proprietary.md)). `ffmpeg-kit` is not used.

## Grimmory

- **Sign in** as above (V). Tokens refresh through `/auth/refresh`.
- **Library:** `GET /api/v1/libraries`, `/shelves`, `/books/page` with `sort`, `facet`, `query`, `cursor` (V). Covers from `/api/v1/media/book/{id}/cover` (auth form U).
- **Download:** `GET /api/v1/books/{id}/download`, streamed (V); multi-file books come as a ZIP from `download-all` (V). Same worker as audio. Range support U. Stored under `files/books/{source}/{id}/`.
- **Bookmarks:** `/api/v1/bookmarks` (V). The app reads and writes them, mapping a Grimmory bookmark to the book edition. EPUB bookmarks carry a `cfi`, PDF a `pageNumber`; without a reader (later) the app lists them read-only for those formats and **creates** them only for audiobooks (`positionMs` + `trackIndex`) if a Grimmory book has an audio edition. That is a limit of "EPUB reading later", stated here so nobody expects page bookmarks from a screen that cannot show a page.
- **Progress:** `POST /api/v1/books/progress` exists; the request body (`BookFileProgress`) is U. Not built until the schema is read.
- **Stability:** `/api/v1` is a path prefix and the project documents no stable contract, so each Grimmory release is checked by the contract tests below.
- **Other protocols** (OPDS, KOReader sync, Kobo sync) are not used. The owner chose the native API.

## Navigation and the library

The owner asked for deep thought on one library or several, and on three aspects of a work: audiobook, book file (epub/pdf/mobi), and quotes only, alone or mixed.

**Model (recommended in every option): the work is the unit, editions hang off it.** `Work` keeps `kind` (book, film, ...). A new `work_editions` table (next migration) links a work to zero or more editions: `{work_id, type: audio | file, source_id, remote_id, state}`. "Quotes only" is a work with no editions, exactly what a book is today. The three aspects are then facts about a work, not three libraries.

| Option | Description |
|---|---|
| **A. One Library, editions on the work** | The Library list shows works. Chips: All, Listening, Reading, Quotes only, Downloaded. A card shows glyphs for the editions it has. The Work page has an edition strip. A mini-player sits above the bottom bar on every screen |
| B. Separate libraries | Library gets three sections: Audiobooks, Books, Quotes. A book you own as audio and file appears twice |
| C. A new Listen tab | A fifth bottom tab holding audiobooks and the player; Library unchanged |

Scoring (1 poor to 5 best, unweighted sum; criteria stated first, as the scale of "what the reader does most"):

| Criterion | A | B | C |
|---|---|---|---|
| One place per book (no duplicates) | 5 | 2 | 2 |
| Taps from app open to resuming a book (mini-player plus a Continue shelf on Home) | 5 | 3 | 3 |
| Keeps the four tabs of [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md) uncrowded | 5 | 5 | 2 |
| Quotes still belong to the work wherever it is listened to or read | 5 | 3 | 3 |
| Clear what to do with a book that has no edition | 4 | 3 | 3 |
| Build cost (higher is cheaper) | 3 | 4 | 3 |
| **Total** | **27** | **20** | **16** |

**Recommendation: A.** Primary downside: the Library card carries more information and the edition matching can be wrong. Mitigations:

- **Matching** is by ISBN or ASIN first, then normalised title and creator. A match below a confidence threshold is offered as "Link this book?" with both covers side by side, never merged silently; every link has an Undo and an "Unlink".
- **Where things live:** Settings gains a **Libraries** section (Audiobookshelf, Grimmory, Whisper, Downloads), all per account. The Server tab stays the Tippani server.
- **Home** gets a **Continue listening** row when a source exists; the existing Library pager is unchanged.
- **Dupes after a merge** show once on the card; a work's quotes never split.
- **Open for the owner:** whether a book found only on ABS should create a Tippani work automatically on first play (recommended: yes, on first play or bookmark, not on browsing) or on an explicit "Add to library".

## Data model (additions)

`library.db` (Dart, next migration; schema 7 at the pin): `work_editions(work_id, type, source_id, remote_id, state, matched_by)`, and `works.details` unchanged.

`listen.db` (native, owned by the service): `sources(id, type, url, account_scope)`, `items(source_id, remote_id, title, author, duration_ms, cover_path, updated_at)`, `tracks(item, idx, url_path, duration_ms, size, cached_path, state)`, `chapters(item, idx, start_ms, title)`, `progress(item, position_ms, device, updated_at, synced)`, `bookmarks(id, item, position_ms, track_idx, created_at, title, remote_id, transcript, state)`, `jobs(kind, ref, state, attempts)`.

**Backup:** the harness's backup contributor carries `work_editions`, bookmarks and transcripts (text); never tokens, downloads, models or the stream cache. Restore is checked whole before any is written ([ADR-0009](ADR-0009-A-Backup-Is-Checked-Whole-Before-Any-Of-It-Is-Written.md)).

## Network and offline behaviour

| State | Browse | Play | Download | Bookmark | Transcribe | Sync |
|---|---|---|---|---|---|---|
| Online | live | stream or cache | runs | instant | idle job | progress every 15 s while playing |
| No Twingate / offline | last copy, dated | cached only | waits | instant | idle job | queued |
| Token refused | last copy | cached only | stops, says why | instant | idle job | queued, "sign in again" |

The broken-link mark and once-per-awake toast of [ADR-0033](ADR-0033-The-Broken-Link-Is-One-Mark-And-One-Toast.md) apply: one mark covers the Tippani server and the sources.

## Settings (all per account, [ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md))

Added to `PrefKeys`: skip back/forward seconds, default speed, sleep-timer choices, smart rewind, Wi-Fi only, storage ceiling, buffer ahead/behind, delete after finishing, bookmark window, Whisper model/language/run-when, speech engine. **Source credentials and the downloaded files are per account too**: another account on the same phone sees none of them.

## Quality and tests

The repo's rule: a test uses the app and does not read it.

| Layer | How |
|---|---|
| Dart screens | Widget tests against `test/support/memory_library.dart` and new fakes `fake_abs.dart`, `fake_grimmory.dart` that speak the routes verified in T0; each press a person makes |
| Contract | A test per route the app uses, pinned to the verified shapes, so a Grimmory release that changes one fails a test, not a phone |
| Kotlin | JVM unit tests for the tree builder, resumption, ring buffer and the eviction rules; instrumented test for the service where needed |
| Android Auto | Desktop Head Unit (DHU) run by hand on the owner's phone; the checklist is a task, since the cloud container has neither a phone nor a head unit |
| Mutation | Every journey is deleted-of-its-decisive-action and watched to fail, named in the commit, as elsewhere in this repo |
| Real device | Whisper speed, Android Auto tree, download resume, sign-in through Authelia: owner-run, listed in the release notes as "not verified until run" |

The cloud container can run Dart analyze and tests and, with the Android SDK added, a debug build. It cannot run Android Auto or a head unit.

## Tasks

Each phase is one release-sized slice. Re-verify first.

- [ ] **T0. Re-verify and read the sources.** At the build commit:
  ```bash
  git diff --stat 90606c9..HEAD -- lib/library/models.dart lib/library/library_store.dart lib/screens/library_widgets.dart lib/app_controller.dart lib/settings lib/capture/voice_listener.dart android/app/src/main
  git log --oneline 90606c9..HEAD -- docs/wiki/ADR-Index.md
  git grep -n "schemaVersion = " HEAD -- lib/library/library_store.dart
  git grep -n "class Work\b" HEAD -- lib/library/models.dart
  ```
  Then read, from primary sources (needs hosts allowed or pasted): ABS API docs or `advplyr/audiobookshelf` routes (login, OIDC, refresh, play, session sync, local sessions, bookmarks, downloads, limits); Authelia client docs (public, PKCE, redirects, lifetimes); Grimmory `/api/openapi.json` (progress, download ranges, public-settings). Correct every **U** above.
- [ ] **S1. Spike: Whisper.** Benchmark `base.en` q5_1 and q8_0 on the owner's phone for a 60 s slice; decide headless engine versus JNI for the idle job. Gate: transcript of a 60 s slice in under 90 s on battery, no UI.
- [ ] **S2. Spike: audio capture.** Prove the PCM tap (design A) in ExoPlayer, including ordering against speed change and behaviour after seeks. Gate: transcript quality equal to design B on the same passage.
- [ ] **S3. Spike: Android Auto.** Media3 service with a four-tab tree, a bookmark button, resumption; check on the DHU. Gate: the button stays visible, no autoplay. Failing that, decide the `audio_service` fallback.
- [ ] **P1. Sources and sign-in.** Settings > Libraries; OIDC redirect plumbing; tokens in secure storage under the account scope; sign-out; "sign in again". Acceptance: a fake source signs in, survives restart, vanishes for another account.
- [ ] **P2. ABS library and stream playback.** Browse, item page, play, chapters, speed, sleep timer, mini-player and Now Playing. Acceptance: fake ABS item plays through a stubbed player; position survives restart.
- [ ] **P3. Native service and Android Auto.** `ListenService`, tree, resumption, bookmark command. Acceptance: JVM tests for the tree; DHU checklist run by the owner.
- [ ] **P4. Offline.** Downloads screen, rolling buffer, eviction, ceiling, resume. Acceptance: airplane-mode playback of a downloaded book; buffer follows the playing chapter.
- [ ] **P5. Progress sync.** Session sync, local session upload, per-item conflict question, shelf status follows.
- [ ] **P6. Bookmarks and Whisper.** Instant bookmark, PCM window, idle transcribe, ABS title, Tippani quote (and D-Q), Bookmarks screen with Trim, models screen, dictated-quote Whisper engine, `voice` source filed as a Tippani server issue.
- [ ] **P7. Grimmory.** Sign in, library, download, bookmarks CRUD, contract tests; progress after the schema is read.
- [ ] **P8. Unified library.** `work_editions`, matching and linking UI, chips, card glyphs, Continue row on Home, per-account everything.
- [ ] **P9. Polish and release.** Glossary (`UI-Glossary`), changelog entries, ADRs, Developing's file map, Troubleshooting rows for each new error code, the real-device checklist, release notes.
- [ ] **Server issue on `aaronified/tippani`:** accept `voice` as a quote source. Until then spoken and bookmark quotes save as `manual`.
- [ ] **Not in this plan:** reading EPUBs, Play Store, iOS, volume-key triggers, OPDS/KOReader/Kobo sync.

## Decisions

New ADRs at build time (numbers taken then, after the last in `ADR-Index.md`; 0035 onward at the pin): media sources and their sign-in; native service owns playback and media state; the work holds editions; progress sync and its playback clock; Whisper on the phone and when it runs; bookmarks become quotes.

## Open questions for the owner

| # | Question | Recommended | Cost of the other |
|---|---|---|---|
| D-Q | Does every bookmark become a quote at once, or open in a Trim step first | Trim step | A library filling with raw transcripts |
| D-A | Does the first play of an ABS book add it to the library | Yes, on first play or bookmark | Extra tap to add every book |
| D-S | Is the 45 s / 15 s window right for the narrators you listen to | Yes, adjustable | Cut-off sentences |
| D-V | Hosts or repository access for T0 | Allow `api.audiobookshelf.org`, `www.audiobookshelf.org`, `docs.audiobookshelf.org`, `www.authelia.com`, or paste the pages | Plan sections stay marked unverified |
| D-G | Grimmory `/api/openapi.json` | Send it with `API_DOCS_ENABLED=true` | Progress sync stays unplanned |

See also: [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md) · [ADR index](ADR-Index.md)
