# Plan: listen, read and bookmark across Audiobookshelf, Grimmory and Jellyfin

**Status:** plan only, nothing built. First written 27 November 2026 at `9e986ca`; revised the same day after source-level checks of Audiobookshelf (ABS), Media3, Whisper, Authelia, Jellyfin and the Tippani server's import contract, an adversarial review, and the owner's answers. Code citations are verified at `90606c9`.
Mockups: `docs/design/listen-mockups.html` in the repository (the wiki is published flat, so it is named here and not linked).

## What the owner asked for

1. Listen to ABS audiobooks with a working Android Auto player and audio cached offline.
2. Bookmark easily while driving. The audio around the press is saved at once and transcribed by Whisper on the phone later. The transcript goes to the Tippani **pending-imports queue**.
3. Connect to Grimmory, download books and sync bookmarks (EPUB reading later; no Grimmory progress sync).
4. Connect to Jellyfin so movies and shows appear in the library with their quotes. Watching is handed off to the Jellyfin app. No in-app player or downloads.
5. Every item in the libraries the owner ticks, from ABS, Grimmory and Jellyfin, becomes a Tippani work automatically and reaches the Tippani server through the normal sync. A run can be undone.
6. ABS and Grimmory sign in through Authelia (OIDC); Jellyfin by Quick Connect or password. Everything is self-hosted, at the latest versions, reached over Twingate with the same HTTPS as Tippani, on Android 14 or newer.
7. Every setting is per user (done in `5a18e09` and `90606c9`, [ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md)).
8. One library, with up to three aspects per work: listen/watch, read, quotes only.
9. The audiobook player copies the official Audiobookshelf app, including its play screens, plus a bookmark button and a chapter-wise seek bar in Android Auto (full screen and the quarter-screen card).
10. Reading copies Readest and all of its reading and note-taking features.
11. Quote text editable in the imports queue.
12. **Order:** once this plan is final, the support work is built first (see Foundations).

## Rulings already made

| Question | Answer (owner, 27 November 2026) |
|---|---|
| Authelia and ABS, Grimmory | Both are OIDC clients of Authelia |
| Where traffic goes | Phone talks to every source directly; the Tippani server only receives works and quotes |
| "Transcribed context" | Whisper transcribes the book audio around the bookmark; context matters |
| Bookmark capture | "Save the clip at once, transcribe when the import queue is opened or the phone is charging. Do not transcribe at all below 15% battery." |
| Where a bookmark's quote goes | An ABS bookmark and a quote **in the imports queue**, not the library: "I cannot trim it while driving." |
| Install | Sideload; Android Auto "Unknown sources" switched on once |
| Whisper | English only: `base.en` by default |
| Offline | Whole-book downloads plus a rolling buffer ahead of the playing book |
| Grimmory | Native REST API; **no progress sync** |
| Jellyfin sign-in | Quick Connect and username/password (not the SSO plugin) |
| Jellyfin scope | Library and quotes; hand off to the Jellyfin app to watch |
| Mirroring | All items of chosen libraries, synced to the Tippani server |
| Bookmark triggers | Android Auto button, notification action, widget, in-app button; no physical button |
| Audiobookshelf player | "Copy what Audiobookshelf already does, including the play screens. Just add the bookmark button and chapter wise seeking bar in the android auto screen (both full screen and the small 1/4th screen)" |
| Book reading | "Copy readest and all of its reading / note taking features" |
| Imports queue | Quote text must be editable there; "Then add that feature as well" |
| Build order | "Once plan is finalised, build all the support stuff (like the import screen enhancement) first" |
| Network and certificates | HTTPS over Twingate, "same as Tippani" |
| Android | 14 or newer |

## What is verified and what is not

**V** read in primary source this session; **I** inference from source; **U** not yet verified. Task T0 closes every U.

| Fact | Level | Evidence |
|---|---|---|
| ABS 2.38.0 was the latest upstream (the owner runs 2.37.2, see below). Login `POST /login`; header `x-return-tokens: true` returns `user.accessToken` and `user.refreshToken` in the body | V | `advplyr/audiobookshelf` `package.json`, `server/Auth.js:325` |
| ABS `POST /auth/refresh` with header `x-refresh-token`; the refresh token **rotates** each call, the old one valid 10 minutes; access 1 h, refresh 30 d | V | `Auth.js:332-339`, `server/auth/TokenManager.js` |
| ABS OIDC for apps: `GET /auth/openid?response_type=code&redirect_uri&code_challenge[&state]` (S256, PKCE required) answers 302 to the IdP; the IdP returns to `{abs}/auth/openid/mobile-redirect`, which 302s to the app; the app then calls `GET /auth/openid/callback?code&state&code_verifier` **with the session cookie from the first call** and gets tokens in the body | V | `Auth.js:363-460`, `server/auth/OidcAuthStrategy.js` |
| ABS "Allowed Mobile Redirect URIs": exact match, or exactly `*`; each entry must match `^\w+://[\w\.-]+(/[\w\./-]*)*$` (no dots in the scheme); a bad update is silently ignored | V | `MiscController.js:683-692` |
| ABS bookmarks `POST /api/me/item/:id/bookmark` `{time (seconds), title}`: upsert by `time`, no title length limit; `PATCH`, `DELETE …/:time` | V | `ApiRouter.js:188-189`, `MeController.js:327-346` |
| ABS play session, direct play `GET /api/items/:id/file/:ino` (Bearer, Range honoured), `…/download` needs the user's download permission and the folder zip route has no Range; session sync `{currentTime,timeListened,duration}`; offline `POST /api/session/local-all` applied only if its `updatedAt` is not older than stored progress; covers need no token | V | `LibraryItemController.js`, `SessionController.js`, `PlaybackSessionManager.js`, `Auth.js` |
| ABS: 40 failed logins per 10 minutes in **one global bucket**; redirect origin built from `Host` and `x-forwarded-proto` | V | `rateLimiterFactory.js`, `requestUtils.js` |
| Media3: a custom `AudioProcessor` sits before speed adjustment and sees 1x 16-bit PCM at the codec's rate; float output, offload and tunneling bypass processors; a seek flushes them | V | `androidx/media` `DefaultAudioSink.java` |
| Media3 custom buttons: `setMediaButtonPreferences`; CENTRAL, BACK, FORWARD hold one each, BACK_SECONDARY and FORWARD_SECONDARY none by default, OVERFLOW unlimited; custom buttons default to OVERFLOW | V | `CommandButton.java`, `MediaSession.java` |
| How many custom actions an Android Auto head unit draws | U | not in the sources read; S3 |
| Android Auto needs `automotive_app_desc`, a media service, 4 root tabs, no autoplay, `mediaPlayback` foreground type; sideloaded media apps show after "Unknown sources" | V | developer.android.com pages |
| `whisper_ggml` needs `ffmpeg_kit`, accepts only 16 kHz 16-bit WAV paths, downloads models into memory, builds without fp16; whisper.cpp's Android example takes a `FloatArray` of 16 kHz mono PCM, hardcodes English, loads an fp16 build on arm64 when `/proc/cpuinfo` has `fphp` | V | pub.dev archive; `examples/whisper.android` |
| whisper.cpp MIT; base 148 MB (q5_1 60 MB), small 488 MB (q5_1 190 MB); RAM about 388 MB (base) | V | whisper.cpp README, Hugging Face listing |
| Whisper speed and memory on the owner's phone | U | S1 |
| Grimmory (`develop`, not a tag): login, refresh, OIDC mobile (`GET /api/v1/auth/oidc/state`, `POST /api/v1/auth/oidc/mobile/callback`), libraries, `/books/page`, streamed `GET /books/{id}/download`, bookmarks CRUD, annotations CRUD | V | `grimmory-tools/grimmory` controllers |
| Grimmory download Range support; public-settings payload; cover auth | U | T0 |
| Authelia (`master`, possibly newer than the owner's release): `public: true` clients have no secret and PKCE is enforced for them by default; redirect URIs match exactly and may be a custom scheme; refresh default **90 minutes** with rotation, zero grace; consent `auto`; session 1 h, 30 d with remember-me | V | `validator/identity_providers.go`, `config.template.yml`, `flow_refresh.go` |
| Authelia docs pages and the owner's release | U | docs host unreachable; T0 reads the owner's `/.well-known/openid-configuration` |
| Jellyfin (`master` is 13.0.0, a development line; verify the owner's 10.11.x): header `Authorization: MediaBrowser Client="Tippani", Device, DeviceId, Version[, Token]` (the `X-Emby-*` forms are legacy-gated, off by default); `POST /Users/AuthenticateByName` `{Username,Pw}`; Quick Connect `POST /QuickConnect/Initiate`, `GET /QuickConnect/Connect?secret=`, an already-signed-in client approves the 6-digit code, then `POST /Users/AuthenticateWithQuickConnect` `{Secret}`, 10-minute expiry; tokens are per-device with no expiry and re-login with the same `DeviceId` replaces the old token; `POST /Sessions/Logout` | V | `jellyfin/jellyfin` `AuthorizationContext.cs:78-268`, `UserController.cs:209-259`, `QuickConnectController.cs`, `QuickConnectManager.cs` |
| Jellyfin `GET /Items?userId&includeItemTypes=Movie,Series&recursive&fields=ProviderIds,Overview,Genres,DateLastSaved&startIndex&limit&minDateLastSaved`; no deleted-items feed (detect by id diff); `GET /Items/{id}/Images/Primary?tag=` carries no `[Authorize]`; user policy `EnableContentDownloading`, `EnabledFolders`; failed-login lockout is per user (default none) | V / I | `ItemsController.cs`, `ImageController.cs`, `UserPolicy.cs`, `UserManager.cs` |
| The official Jellyfin Android app has no item deep link (only MAIN/LAUNCHER and a voice-search intent); the web route `<server>/web/index.html#/details?id=<id>&serverId=<serverId>` opens an item in a browser | V | `jellyfin-android` `AndroidManifest.xml:49-64`; `jellyfin-web` `appRouter.js:483-500` |
| Tippani server **accepts `voice`** as a quote `source` on direct create (`POST /quotes`, `/annotations`, `/dialogues`), with `Idempotency-Key` (24 h); staged imports cannot carry `voice` or `ocr` (their source is the importer slug or `import`) | V | `internal/httpapi/capture_fields.go:53-71`, `idempotency.go`, `import_staging.go:1397` |
| `POST /import/auto`: multipart `file` (5 MiB max) and `as` (`md`); answers 202 `{job}`; the result gives `batch_id`, `staged`, `works[]`; the batch is named by the uploaded filename; no Idempotency-Key and no rate limit | V | `import_queue.go`, `import_handlers.go:22,220-248` |
| Staging queue: `GET /import/staged`, `POST /import/staged/bulk` (metadata only: tags, location, chapter, character, `retarget`, and so on), `POST /import/staged/approve`, `DELETE /import/staged` (batch or selection). **Quote text, note and translation are not editable in the queue.** A whole batch can be approved or discarded | V | `import_staging.go:1336-1460,1849-1890,1963`, `import_staged_bulk.go:44-107` |
| A staged book quote joins an existing work by ISBN, ASIN, or exact case-insensitive title and author; a movie or show by normalised title and media type, year preferred | V | `import_handlers.go:450-479`, `import_dupes.go` |
| `POST /books` and `POST /movies` are single-create only, 64 KiB body, no rate limit or quota; `POST /books` answers 409 on an ISBN or ASIN clash; a plain create does no outbound work, but a `source`, `source_id` or `tmdb_id` on a movie create triggers a provider fetch; a write pool of 4 connections | V | `book_handlers.go:308-398`, `movie_handlers.go:379-454`, `server.go:1200` |
| Audiobookshelf's own app (GPL-3.0): the full player layout, the Chapter Track and Total Track options, jump options 5 to 300 s (default 10), speed presets and 0.1 stepper from 0.5 to 10, sleep timer rules, auto-rewind steps, bookmark UI, 15 s sync (60 s on a metered network), media-button behaviour, settings and defaults; **it publishes whole-book duration with a per-file position to Android Auto, exposes no chapters there, and has no chapter tick marks or tap-to-seek** | V | `advplyr/audiobookshelf-app` `components/app/AudioPlayer.vue`, `modals/*`, `android/.../player/*.kt`, `strings/en-us.json` |
| Media3 `SimpleBasePlayer` can present chapters as items with chapter-relative position and duration; the legacy bridge sends `getCurrentPosition`, `getBufferedPosition` and the duration to the car; seek reaches `Player.seekTo`; custom actions up to 6 (8 without Next and Previous) | V | `SimpleBasePlayer.java`, `MediaSessionLegacyStub.java`; developer.android.com cars pages |
| What the Android Auto quarter-screen card draws, and whether the car sends one seek or many while dragging | U | not documented; S3 on the Desktop Head Unit and the owner's head unit |
| Readest 0.12.26: AGPL-3.0 with no exception; features as listed in the reader section; no reading statistics; premium voice, AI and some translators need Readest's own login | V | `readest/readest` `LICENSE`, `README.md`, `apps/readest-app/src/**` |
| foliate-js: MIT; EPUB, MOBI, KF8, FB2, CBZ, PDF (experimental); `open`, `goTo`, `addAnnotation` with `draw-annotation`, `relocate`, `search`, TTS SSML; the README says it is unstable and unreleased; `open(url)` loads the whole file into memory | V | `johnfactotum/foliate-js` `view.js`, `README.md` |
| `flutter_inappwebview` 6.1.5 (Apache-2.0) offers request interception, asset loading, context menu and JS handlers; `webview_flutter` 4.14.1 does not show them in its changelog | V / I | pub.dev; plugin source |
| Readium Kotlin toolkit 3.4.0 (BSD-3) has no MOBI or AZW3, and no PDF search or highlights | V | `readium/kotlin-toolkit` `README.md` |
| Tippani Markdown (`as=md`) needs `type:`, `title`, optional `author`, `language`, `isbn` for a book, and `> text` with `- location:`, `- note:`, `- tags:`, `- date:`; there is no `source` or tmdb key | V | `importer/markdown.go:93-`, `movie_markdown.go:166-` |

### Checked against the owner's own servers (28 November 2026)

Read-only calls from the owner's machine, as a normal ABS user named `test` for anything that writes. Where this table and the source-based rows above disagree, this table wins for the owner's install. It closes part of T0.

| Server | Fact on the owner's install | Effect on the plan |
|---|---|---|
| ABS | **2.37.2**, not 2.38.0. `GET /status` lists `local` and `openid`. The refresh-token migration is applied; `POST /auth/refresh` answers 401 to a bad token | Re-read changed routes against 2.37.2 in T0 |
| ABS | `authOpenIDMobileRedirectURIs` holds only `audiobookshelf://oauth`; Authelia's ABS client lists the two https callbacks plus `audiobookshelf://oauth` and requires PKCE S256, `two_factor`, a one-year pre-configured consent | The owner action stands: add `tippani://oauth/abs` to both |
| ABS | OIDC auto-register is on and an existing user is matched **by username** | The Authelia username must equal the ABS username, or a second user is created |
| ABS | Login limit is 10 per 600 s | Never loop a login |
| ABS | As a non-root user: `POST /login` with `x-return-tokens`, `GET /api/libraries`, items, `POST /api/items/{id}/play`, `POST /api/session/{id}/sync` and `/close`, `POST /api/session/local`, bookmark create and delete all answer 200. A track streams with `Authorization: Bearer` and a `Range` header (206, `Accept-Ranges: bytes`), with no token in the URL | The player can stream and cache with a header only |
| ABS | Bookmarks are keyed by `time`: `DELETE /api/me/item/{id}/bookmark/{time}` | Two bookmarks in the same second collide; round or offset the time |
| ABS | `librariesAccessible` is empty while `accessAllLibraries` is true | Do not read an empty list as "no access" |
| ABS | One library, 143 books, each with ASIN and embedded chapters; ISBN can be null. One checked item has a single chapter | Match audiobooks by ASIN first; the seek bar needs a whole-track fallback for a one-chapter book |
| Jellyfin | **12.4.0** (not 10.11.x). Quick Connect is enabled. `AuthenticateByName` with the `MediaBrowser` header and `POST /Sessions/Logout` work | Re-read the routes against 12.4.0 in T0 |
| Jellyfin | Libraries: Movies (737), Shows (79), YouTube Shows (2), Playlists (6), plus empty box-set views. Items carry `Imdb`, `Tmdb`, `Tvdb` | Mirror Movies and Shows only; skip Playlists and empty views by default |
| Grimmory | **v3.5.0** (v3.5.1 is out). Public settings: OIDC through Authelia, client id `grimmory`, local login still allowed. 522 books in 3 libraries | Pin contract tests to v3.5.0; the plan's "tag" is v3.5.0 |
| Grimmory | `POST /api/v1/auth/login` returns `accessToken` and `refreshToken`; a bad refresh answers 401 | Local sign-in works as a fallback |
| Grimmory | `GET /api/v1/books/{id}/download` ignores `Range`: it answers 200 with the whole file and no `Accept-Ranges` | Downloads cannot resume; the plan's "restarts from zero" case is the real one |
| Grimmory | `GET /api/v1/bookmarks/book/{id}` and `/api/v1/book-notes/book/{id}` answer 200 (empty); `/api/v1/annotations/book/{id}` answers 200 (empty). `GET /api/v1/annotations` and `/book-notes?bookId=` answer 405. Covers load from `/api/v1/media/book/{id}/cover` with a bearer token | The list-by-book routes are the ones to use; the shapes of a populated bookmark and note are still unread |
| Not tested | Sign-in through Authelia in the app, downloads, long books with many chapters, Grimmory annotation shapes with data | Stay in T0, S3 and P1 |

## What already exists in the app

Verified at `90606c9`. Re-verify with T0.

| Piece | Where | State |
|---|---|---|
| `Work` with `kind`, `creator`, `cover`, `details` | `lib/library/models.dart:16` `class Work`; `:3` `enum WorkKind { book, film, show, game, other }` | Built; no edition notion |
| Local SQLite library, schema 7 | `lib/library/library_store.dart:193` `static const schemaVersion = 7` | Built; the next migration adds editions |
| A work's list row | `lib/screens/library_widgets.dart:339` `class WorkTile` | Built |
| Per-account preferences | `lib/settings/preference_scope.dart` `class PreferenceScope`, `PrefKeys` | Built |
| Pairing; token in a Dart secure-storage plugin | `lib/app_controller.dart:181` `Future<PairResult> pair(`; `lib/settings/settings_store.dart:1` | Built; Tippani server only |
| Pending imports screen (approve, discard, bulk edit, retarget), grouped by batch | `lib/screens/staging_screen.dart` (1349 lines); `lib/imports/import_service.dart:552` `importFile`, `:634` approve | Built; needs a paired server |
| Push sync of works and quotes; maps film to `movie`; sends `source` as `ocr` or `manual` only | `lib/sync/push_sync.dart:98,236-271` | Built; **its comment that the server accepts only `manual` and `ocr` is stale** (the server accepts `voice`) |
| Sync once a day and on change | `lib/sync/auto_sync.dart:141` `Timer.periodic(checkEvery` | Built |
| Dictating a quote | `lib/capture/voice_listener.dart:1` `import 'package:speech_to_text/...'` | Built |
| Manifest: `RECORD_AUDIO`, `INTERNET`, `usesCleartextTraffic="true"`, exported `singleTop` activity with empty `taskAffinity`; no `allowBackup` or data-extraction rules; no `network_security_config` | `android/app/src/main/AndroidManifest.xml:4-6,15,21-23` | Built |
| Release signing | `android/app/build.gradle.kts:34-38` (debug config) | Built; T0 confirms the release workflow's injected signing |
| CI: format, analyze, test, debug APK | `.github/workflows/ci.yml` | Built; no NDK or Kotlin tests |
| Locales `en`, `bn`; every string a token | `lib/l10n/l10n.dart:53`; `test/l10n/tokens_test.dart` | Built |
| Playback, downloads, source sign-in, mirroring, Whisper, bookmarks, Jellyfin | none | Missing |

**In flight at the pin:** not audited. The remote has many older feature branches, and none was compared with this plan. T0 lists open branches and pull requests touching the cited paths and re-checks `CHANGELOG.md` and `ADR-Index.md` for numbers taken after `ADR-0034`.

## Architecture

```
 Phone
 ┌──────────────────────────────── Flutter (Dart) ───────────────────────────────┐
 │ Library · Work page · Player UI · Pending imports · Settings → Libraries       │
 │ Browse clients (ABS, Grimmory, Jellyfin) · Mirror engine · Editions            │
 │ The only writer of library.db and the only talker to the Tippani server        │
 └───────────────▲──────────────────────────────────────────▲────────────────────┘
      MethodChannel / EventChannel                        sqflite
 ┌───────────────┴────────────────── Kotlin (native) ───────┴────────────────────┐
 │ ListenService : MediaLibraryService (ExoPlayer, tree, resumption, buffer)      │
 │ TokenVault (Keystore) · AbsClient (auth, play session, progress, bookmarks,     │
 │ downloads) · listen.db · PcmTap · ClipStore · DownloadJob · WhisperJob (:whisper)│
 └──────────────────▲──────────────────────────────▲──────────────────▲──────────┘
        Audiobookshelf                          Grimmory           Jellyfin
        (Authelia OIDC)                       (Authelia OIDC)   (Quick Connect / password)
                          Tippani server: works by push sync; bookmark quotes through /import/auto
```

**Division of labour.** Native Kotlin owns what must work with no UI: the player and browse tree, tokens and their refresh, the ABS play session, progress, bookmarks, downloads, the PCM tap, clips and Whisper. Dart owns what a person looks at and searches: library lists, items, series, search, covers, editions, the mirror engine, Jellyfin, and every write to `library.db` or the Tippani server. Dart borrows an access token from native for its own browse calls.

**Why native owns playback.** Android Auto binds to the service while the phone is locked and no Flutter engine runs, and asks for the browse tree and for resumption at boot with no network. Whatever that needs sits in native `listen.db`. Alternatives:

| Option | For | Against | Verdict |
|---|---|---|---|
| Kotlin Media3 service, native `listen.db` | Fits the Android Auto lifecycle; Media3, OkHttp and WorkManager are Apache-2.0 | Two databases; native code to own | **Chosen** |
| `audio_service` 0.18.19 + `just_audio` | Less native code | Legacy browse service; browse depth and custom actions unverified; needs the Dart engine | Fallback if S3 shows the native route too costly |
| Route through the Tippani Go server | One place for credentials | New backend, extra hop, breaks offline | Rejected by the owner |

### Token custody

| Rule | Why |
|---|---|
| ABS and Grimmory tokens live only in native `TokenVault`: an Android Keystore AES-GCM key wraps them in `listen.db` (`sources.secret`) | `flutter_secure_storage` is a Dart plugin; the service has no Dart when Android Auto binds |
| One refresh mutex per source in Kotlin. Dart asks `getAccessToken(source)` and never refreshes | Rotating refresh tokens (ABS rotates every call) race otherwise and sign the driver out |
| A rotated refresh token is written to the vault **before** it is used for anything else; a 401 on refresh retries once with the stored previous token inside ABS's 10-minute grace, then marks the source "sign in again" | A crash between receiving and saving a rotated token must not lose the session |
| Dart pushes `setActiveAccount(scope)` when the paired account changes ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md) scope `server|name`); native persists it and serves that account's sources when Dart is dead | The service must know whose library it is serving |
| Jellyfin's token is a per-device token with no expiry. It lives in the same vault and is used by Dart only through `getAccessToken` | One place for every credential |
| Tokens, authorization codes, the PKCE verifier and `Authorization` headers are redacted from `AppLog` and logcat | Existing rule |
| JVM test: two concurrent 401s cause exactly one refresh | Acceptance for the mutex |

**Credentials never leave the phone.** Nothing about a source is sent to the Tippani server except the works and quotes the owner chose to mirror. A second phone signs in itself and re-links editions by matching.

**Works alone** ([ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md)): with no Tippani pairing, sources can still be added and used and the unpaired preference set applies. Bookmark transcripts then wait in a local Bookmarks list instead of the imports queue (see the pipeline).

### Background execution

| Job | Mechanism | Foreground type | Cancel / resume |
|---|---|---|---|
| Playback, browse, resumption | `ListenService` | `mediaPlayback` | Resume through `onPlaybackResumption` |
| Rolling buffer | A coroutine inside `ListenService` while it plays | Already foreground | Files are `.part` until complete; stops with playback |
| Manual download | **User-initiated data transfer job** (`JobScheduler`, Android 14+, the owner's floor) with its notification | Not a foreground service | The system may stop it; it resumes from the `.part` length with `Range` |
| Clip capture at a press | In `ListenService` | Already foreground | One short write; idempotent by bookmark UUID |
| Transcription | `WorkManager` one-time job with `requiresCharging` and `requiresBatteryNotLow`, running in a separate process `:whisper`; also started on demand from the foreground when the Pending imports screen is opened | None (windows are two minutes; job under 10 minutes) | Checks **battery at least 15% before each clip and refuses below it**, even on a charger; thermal gate; idempotent per clip; cancelled when playback starts |
| Mirror runs | Dart, on events (see Mirroring) | None | Resumable by a cursor in the database |
| Progress upload (ABS) | In the service while playing; local-session upload on events | Already foreground / event | Idempotent by session id |

The `:whisper` process caps Whisper's memory (about 388 MB for base) so an out-of-memory kill cannot take the player down. Whisper never runs while a book plays.

**Retry rules** ([ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md) forbids retry timers). Every retry is triggered by an event: the app opening, the network returning, playback starting, charging starting, the Pending imports screen opening, or the reader's own press. No backoff ladder; each job is one attempt per trigger. The ABS progress clock runs only while audio plays.

**OEM battery managers.** First run offers the system battery-exemption prompt with a sentence saying why; S1 and S3 run on the owner's phone; a killed service says so in one line on the next open. **Notifications:** `POST_NOTIFICATIONS` is requested on first play; if denied, playback and Android Auto still work and Settings says what is hidden.

## Sign in

### Audiobookshelf (V)

The app learns the methods from `GET /status` (`authMethods`, `serverVersion`). With `openid`:

1. Generate a PKCE verifier and S256 challenge and a `state`; persist all three in the vault keyed by `state`.
2. The app itself calls `GET {abs}/auth/openid?response_type=code&redirect_uri=tippani%3A%2F%2Foauth%2Fabs&code_challenge=…&code_challenge_method=S256&state=…` **without following redirects**, keeps the `Set-Cookie` session and reads the `Location` header (the IdP URL).
3. Open that `Location` in the system browser. The owner signs in to Authelia.
4. Authelia returns to `{abs}/auth/openid/mobile-redirect`, which 302s to `tippani://oauth/abs?code&state`.
5. An intent filter for the `tippani` scheme hands the URL to the app, which **accepts it only while a flow it started is pending and only if `state` matches**.
6. Call `GET {abs}/auth/openid/callback?code&state&code_verifier` with the saved cookie; the body carries `user.accessToken` and `user.refreshToken`.
7. A username and password login (`POST /login` with `x-return-tokens: true`) stays available where OIDC is off, and is never looped: ABS's failed-login limiter is one bucket for all clients.

**Owner actions.**
1. ABS Settings > Authentication > "Allowed Mobile Redirect URIs": add `tippani://oauth/abs`. The scheme must be letters, digits or underscore only.
2. Authelia, ABS's client: its redirect URIs include `https://{abs}/auth/openid/callback` and `https://{abs}/auth/openid/mobile-redirect`. No scheme of ours is registered in Authelia for ABS.
3. The reverse proxy passes `Host` and `X-Forwarded-Proto: https` to ABS.

### Grimmory (V from `develop`; the owner runs v3.5.0, see "Checked against the owner's own servers")

1. `GET /api/v1/auth/oidc/state`; persist the state, a PKCE verifier and a nonce.
2. Open Authelia's authorize URL (issuer and client id from Grimmory's public settings, U) with `redirect_uri=tippani://oauth/grimmory`.
3. The intent filter receives the code (same pending-flow and `state` checks); `POST /api/v1/auth/oidc/mobile/callback` with `code`, `code_verifier`, `redirect_uri`, `nonce`, `state` returns Grimmory's own tokens.

**Owner actions.** Add `tippani://oauth/grimmory` to Grimmory's `oidcRedirectUris`, and to `redirect_uris` of Grimmory's Authelia client (exact match; `public: true`, `require_pkce: true`, `pkce_challenge_method: S256`). Authelia accepts a custom scheme and only warns that a reverse-domain scheme is preferred; the scheme stays `tippani` because ABS accepts none with dots.

### Jellyfin (V from `master`; verify the owner's release)

| Step | Detail |
|---|---|
| Identify | `Authorization: MediaBrowser Client="Tippani", Device="<model>", DeviceId="<stable per install>", Version="<app>"`. Never `X-Emby-Authorization` (legacy-gated, off by default) |
| Quick Connect (preferred) | `GET /QuickConnect/Enabled`; `POST /QuickConnect/Initiate` returns a 6-digit `Code` and a `Secret`; the owner types the code into an already-signed-in Jellyfin client; the app polls `GET /QuickConnect/Connect?secret=` every 3 s for at most 10 minutes (the server's expiry), then `POST /Users/AuthenticateWithQuickConnect {Secret}` |
| Password fallback | `POST /Users/AuthenticateByName {Username, Pw}`. Failed logins count per user; a lockout is off by default, so the app still stops after three refused attempts |
| Token | Per-device, no expiry. Kept in the vault. Signing in again with the same `DeviceId` replaces it. Sign-out calls `POST /Sessions/Logout` |
| Not used | The SSO plugin (the owner's choice), API keys |

**Forward-auth caveat.** Jellyfin uses its own sign-in and is not an Authelia OIDC client here. If a reverse proxy puts Authelia forward-auth in front of Jellyfin's API, a native app receives a login page instead of JSON, so the same check as for the other sources applies.

### Shared rules

- **Return address safety.** Another app can claim the scheme, so a flow carries PKCE, `state` and (Grimmory) `nonce`, a callback is accepted only while a flow it started is pending, the verifier lives in the vault through process death, and a pending flow expires after 10 minutes.
- **Refresh and offline.** The app never holds Authelia tokens; each service exchanges the code itself and issues its own. Authelia's 90-minute refresh lifetime and zero-grace rotation therefore reach only the services' own sign-in. ABS refresh tokens last 30 days and renew on every use; a phone that goes online at least monthly never signs in again. A refresh that fails with no network is not a sign-out; only a refused refresh token while online marks the source "sign in again". Downloaded books stay playable.
- **What a re-sign-in costs.** The browser step shows Authelia's login unless an Authelia session cookie is valid (1 h by default, 30 days with remember-me), and a consent screen unless consent is remembered (7 days by default). The owner can lengthen either on the Authelia side.
- **Forward-auth must not guard the services' API.** On adding a source the app calls its unauthenticated status endpoint (`GET /status`, Jellyfin `GET /System/Info/Public`, Grimmory's public settings); if it receives HTML or a redirect to Authelia it says "this address is behind a login page; allow the API paths through" and names them.
- **TLS.** The owner's answer is "HTTPS, the same as Tippani". The plan **assumes** the certificate setup that already works for Tippani on the phone also works for the three sources; the Add source screen proves it with a test connection, and T0 adds a `network_security_config` only if that fails. Sources reuse `isRiskyCleartext` (`lib/settings/server_url.dart:38`) and refuse to send a token, code or password over `http://`.

## Audiobookshelf playback and sync (V)

| Need | Route (all with `Authorization: Bearer`) |
|---|---|
| Libraries, items, series, authors, search | Dart: `GET /api/libraries`, `/api/libraries/:id/items` (`limit`, `page`, `sort`, `minified=1`), `/api/items/:id?expanded=1&include=progress`, `/api/libraries/:id/series`, `/api/libraries/:id/search?q=`, `/api/libraries/:id/personalized`, `GET /api/me/items-in-progress` |
| Covers | `GET /api/items/:id/cover?width&format=webp&ts`; no token needed |
| Start | Kotlin: `POST /api/items/:id/play` with `forceDirectPlay: true` and `supportedMimeTypes`; a transcode answer plays the `m3u8` as is |
| Stream a track | `GET {contentUrl}` (`/api/items/:id/file/:ino`) with the header; never `?token=` in a URL |
| Session | `POST /api/session/:id/sync {currentTime,timeListened,duration}`; `POST …/close` on stop |
| Offline listening | A local session (UUID, `updatedAt` = last listened time) uploaded by `POST /api/session/local-all` when ABS is next reached |
| Bookmark | `POST /api/me/item/:id/bookmark {time, title}`; `PATCH` same body; `DELETE …/bookmark/:time` |
| Download | `GET /api/items/:id/file/:ino` per audio file with `Range` from the `.part` length; the zip route is never used. **The Download button follows `user.permissions.download`** |

### The player copies the Audiobookshelf app (V, `advplyr/audiobookshelf-app`, GPL-3.0)

The owner's ruling: "copy what Audiobookshelf already does, including the play screens", plus a bookmark button and a chapter-wise seek bar in Android Auto. The structure, labels and rules below are read from the official app's source. Styling follows this app's Material You and Tabler rules ([ADR-0005](ADR-0005-Material-You-Only.md)), so it is the same screens in this app's own look. Where the official app has no feature, none is invented.

**Full-screen player, top to bottom** (`components/app/AudioPlayer.vue`):

| Element | Behaviour |
|---|---|
| Collapse chevron (top left) | Closes to the mini player. A swipe down of more than 100 px does the same; a swipe up from the mini bar opens it |
| Play-method label (top centre) | Small text: Direct, Local or Transcode |
| Top right | A cast button only where casting is available (not in this plan), and a more menu |
| Cover | Large, background tinted from the cover; a red error icon on the cover when progress sync has failed twice, which opens "Progress Sync Failed" |
| Title and author | Title line shows the **current chapter title** (the book title when there are no chapters); author below; tapping opens the item |
| Total bar | A thin bar above the main track with elapsed and remaining for the **whole book**, shown only when both Chapter Track and Total Track are on |
| Main track | Elapsed on the left, "-remaining" on the right, a 6 px bar with buffered, ready and played segments and a draggable cursor; **no chapter tick marks and no tap-to-seek** in the official app. Seeks on release |
| Controls | Previous chapter, jump back (labelled "10s"), play or pause (a spinner while loading or seeking), jump forward, next chapter. Chapter buttons only in full screen and unlocked |
| Bottom bar | Bookmark (hidden for podcasts), speed ("1.2x"), sleep timer (a moon, or the remaining minutes in green once running), chapters list |
| Mini player | Cover, "Title | Chapter", author, play or pause, jump back and forward, a thin track; tap opens the full player |
| More menu | History, Total Track, Chapter Track, Scale Elapsed Time by Speed, Lock Player, Close player |

**Rules copied exactly:**

- **Chapter Track** (a player setting, off by default): when on, the main bar spans the current chapter and elapsed and remaining are chapter-relative; dragging is clamped to the chapter; the whole-book bar remains above it if Total Track is on. At least one of the two stays on. **Scale Elapsed Time by Speed** (on by default) divides elapsed and remaining by the playback rate.
- **Previous chapter:** within 4 s of a chapter's start go to the previous chapter, otherwise restart the current one. **Next chapter** is the first chapter that starts after the current time. With no chapters the chapter buttons are dimmed and do nothing.
- **Jump:** default 10 s back and 10 s forward; options 5, 10, 15, 30, 60, 120, 300 s. Labels read "30s" below two minutes and "5m" above.
- **Speed:** presets 0.5, 1, 1.2, 1.5, 1.7, 2, 3, a minus and plus stepper in 0.1 steps, from 0.5 to 10. The title is "Playback Speed".
- **Sleep timer:** options 5, 10, 15, 30, 45, 60, 90 minutes, "End of Chapter" (when chapters exist), and a custom time. While running there are minus and plus five minutes and Cancel Timer. The last 60 s fade the volume from 1.0 to 0.1 unless fading is disabled; an optional chime at 30 s; end of chapter uses the next chapter when under 10 s remain. **Shake to reset** works while the timer runs or within two minutes after it ends, resets it to the same length, vibrates, and plays; sensitivity Very Low to Very High, default Medium. **Auto sleep timer** defaults to 22:00 to 06:00 and 15 minutes, wraps midnight, can be cancelled for the rest of the window, and can rewind (default 5 minutes) when it starts or re-arms.
- **Auto rewind on resume:** a pause under 10 s rewinds 0; 10 s to 1 min, 3 s; 1 to 5 min, 10 s; 5 to 30 min, 20 s; 30 min or more, 29.5 s. Never before the current chapter's start. Off by "Disable auto rewind".
- **Bookmarks** (bottom bar): "Your Bookmarks" lists rows with a bookmark icon (filled when it is at the current time), title, timestamp (divided by speed), edit and delete. Tap a row to seek and close. "Create Bookmark" sits in a sticky footer with the current time and is hidden when a bookmark already exists at that exact time. New Bookmark has a "Note" field whose default is the date and time ("MMM dd, yyyy HH:mm"). Delete asks "Remove Bookmark". Stored as `{title, time: floor(currentTime)}`. Online only in the official app; **here a press while offline is kept in `listen.db` and sent later**.
- **Chapters list:** a panel with "{n} Chapters", columns Chapters, Start and Duration (both divided by speed), the current chapter highlighted with a bar on its left edge, auto-scrolled to centre, tap to seek and close.
- **Progress sync:** every 15 s while playing on an unmetered network, at most every 60 s on a metered one; also on pause, stop, finish and close. Two failed syncs in a row show the red error icon. When the server's progress is newer while a local item is open, the player moves to it (when paused) and updates local progress; there is **no conflict dialog and no Sync-now button** in the official app. Starting a downloaded item at a position asks "Start playback for "{title}" at {time}?". If under 5 s remain, start at 0.
- **Media buttons:** a single press of a headset or steering-wheel button toggles play; double press jumps back and plays; three or more jump forward and play; Next and Previous keys jump forward and back; fast-forward and rewind keys jump.
- **Notification and lock screen:** play or pause, rewind and fast-forward (compact), the jump amounts from settings; the seek bar only if "Allow position seeking on media notification controls" is on.
- **Settings** (copied with their defaults): Lock orientation; Haptic feedback (off, light, medium, heavy; default light); Jump backwards and forwards time (10 s); Disable auto rewind (off); Enable mp3 index seeking (off); Allow position seeking on media notification controls (off); Disable shake to reset (off); Shake sensitivity (medium); Disable audio fade out (off); Disable vibrate on reset (off); Play a chime when almost finished (off); Auto sleep timer (off), start time, end time, length, auto rewind and rewind time; Download using cellular and Streaming using cellular (Ask confirmation, Always, Never; default Always); Android Auto "Alphabetical drawdown limit" (100) and "Series books order" (sequence ascending). All are per account ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md)).
- **Downloads page:** "Downloads (N)", rows with a cover, title, track count and size, a total size footer; per item a download button with "Downloading... (N%)" and "Download complete. Processing...", a confirmation naming the track count and the folder, and "Delete local item". Downloads include every audio file and the cover (and the ebook file when there is one). A downloaded item plays locally with no server session. ABS stores to the app's internal storage by default; this app does the same (a folder choice is not planned).
- **Labels** are taken from the official app's string file and kept in English and Bengali tokens.

**Not in the official app, so not built:** chapter tick marks on the bar, tap-to-seek on the bar, a playback queue screen, a sync-now button, an "open in browser" button, a conflict dialog.

**This app's two additions** are in Android Auto (below). Everything else is the official behaviour.

### Where this app departs from the official app, deliberately

| Point | Official app | This plan | Why |
|---|---|---|---|
| Android Auto position and duration | Whole-book duration with a per-file position, which can disagree on multi-file books | One consistent chapter-relative position and duration (below) | The owner asked for a chapter-wise bar |
| Android Auto bookmark button | None | A Bookmark custom action | The owner asked for it |
| Bookmark while offline | Online only | Kept and sent later | Driving with no signal |
| Player library | Exoplayer 2 `MediaSessionConnector` | Media3 | Media3 is the current library; Android Auto still gets the same session |
| Look | Its own dark theme | Material You, Tabler icons | [ADR-0005](ADR-0005-Material-You-Only.md) |

Behaviours kept from the first draft: tracks and chapters (multi-file playlist with `startOffset`; position is seconds in the whole book everywhere), podcasts out of scope, series order, audio focus and becoming-noisy handling, and the driver-safe conflict rule (ABS applies its timestamp rule; the app resumes the local position and offers "Jump to 55:00 from Pixel" as a banner, which [ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md) allows because it never stops sync).

## Android Auto

- Manifest: `automotive_app_desc` (`uses name="media"`), Media3 intent filters, `foregroundServiceType="mediaPlayback"`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`.
- **No autoplay on connect.** `onPlaybackResumption` restores the last item and position from `listen.db` using local data only.
- **Browse tree: the official app's four tabs** (the root hint allows four): **Continue** (items in progress), **Recent**, **Libraries** (Authors, Series, Collections, Discovery; grouped by letter above the drawdown limit; series books in sequence order, "N. Title"), **Downloads**. There is **no Bookmarks tab**: the owner asked for the bookmark button, not a tab. Items show the author as subtitle, the cover, and a played-percentage. Search arrives through `onGetSearchResult` and `onPlayFromSearch` (the first title containing the query).
- **Custom actions** (up to 6 are allowed, or 8 without Next and Previous): **Jump Backward**, **Jump Forward**, **Change Playback Speed** (cycles 0.5, 1, 1.2, 1.5, 2, 3), the official app's three, and **Bookmark** (this plan's addition, with a stateful icon). The first three use the jump seconds from settings. Next and Previous are chapter skips, with their slots reserved so custom actions do not displace them. Placement by the head unit: the actions go in the transport row "if space permits", otherwise the overflow menu (V from the documentation), and S3 records where each lands.

### The chapter-wise seek bar (new; V in Media3 source, behaviour on a head unit U)

Android Auto draws the seek bar from the session's position and duration. Whatever the player reports is what the car shows. The plan therefore reports **one chapter at a time**:

- A `ChapterPlayer` built on Media3 `SimpleBasePlayer` wraps the real ExoPlayer, which plays the whole book. Its `getState()` presents the **current chapter** as the current item with `durationUs` = the chapter's length, a chapter-relative `contentPosition` that advances (`PositionSupplier.getExtrapolating`), and a buffered position that is chapter-relative.
- The playlist it reports is the chapter list (unique UID per chapter), so the car's queue is the chapters and Next and Previous are chapter skips. `maxSeekToPreviousPositionMs` is 4000, which reproduces the official "within 4 s go to the previous chapter" rule.
- `handleSeek` maps a chapter-relative seek to `chapterStart + position` on the real player. `COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM`, the seek-to-next and previous commands and `handleSetPlayWhenReady`, `handlePrepare`, `handleStop` and `handleRelease` are implemented; `invalidateState()` is called on real-player events and at each chapter boundary, and a media-item transition is emitted when playback crosses a boundary so the car re-reads the title and duration.
- **The car may send one seek on release or many while dragging; the source and documentation do not say.** `handleSeek` is therefore cheap and idempotent.
- The title shows the chapter; the subtitle shows the book and whole-book progress ("Dust of Dreams · 41% · 5 h 20 m left"), so the whole-book position is still readable.
- **Books with no chapters** report the track, or the whole book, as one item. No chapters are invented.
- **Alternative if the wrapper proves fragile (S3):** one `MediaItem` per chapter with a clipping configuration on the same files. It is simpler and every layer sees the right numbers, but gapless playback and seek cost across clipped items are unverified.
- **Phone side:** the same `ChapterPlayer` feeds the in-app player, whose Chapter Track option then only chooses what the phone bar shows. The car always shows the chapter bar.

**The quarter-screen card.** The documentation says Google and the car maker draw the playback view, the minimised control bar and the queue, and says nothing about the dashboard's small media card. The Media3 and legacy session mapping means the same position, duration and custom actions reach it, but **whether the card shows the seek bar or any custom action is not documented**, and the app cannot change how the card is drawn. The plan promises the data is right on both; spike S3 shows what each screen draws on the owner's head unit and on the Desktop Head Unit (setup steps are in the Android developer pages and are an owner-run item).

### Triggers

| Trigger | Surface |
|---|---|
| Bookmark action | Android Auto now-playing |
| Notification action | Phone lock screen and shade |
| Widget | Home screen (bookmark, play/pause) |
| In-app button | Player screen (the bookmark icon in the bottom bar) |
| Physical buttons | Keep the official app's meaning (above); a bookmark from a physical button is not offered |

### Distribution

Sideloaded APK from GitHub releases. Android Auto lists it only after the owner enables developer mode (tap the version row ten times) and "Unknown sources". Plan.md keeps the Play Store out of scope. The release APK's signing is checked in T0.

## Offline audio

| Mode | Behaviour | Stored |
|---|---|---|
| Download | A book's files in order, resumable, never evicted | `files/listen/{source}/{item}/` |
| Rolling buffer | Ahead 3 h, behind 1 h by default; `.part` until complete | Same folder, marked `buffer` |
| Stream | Anything not cached | ExoPlayer `SimpleCache`, 512 MB default |

Settings per account: Wi-Fi only (default on), storage ceiling (default 5 GB), buffer ahead and behind, delete after finishing. Eviction takes buffer files first, oldest played first. A full disk stops a download with the reason and leaves nothing partial marked complete. A file is complete only if its length matches the item's reported size.

## The bookmark pipeline

The clip is saved at once; everything after is deferred and idempotent. Every bookmark has a UUID in `listen.db`.

```
pending → clipped → transcribed → queued (imports) → titled (ABS)
```

| Step | Owner | Rule |
|---|---|---|
| 1 pending | Kotlin | On press, write the row (item, position as float seconds, time, UUID) **before anything else**; swap the button icon. ABS upserts by `time`, so two presses in one second share a bookmark; positions keep millisecond precision |
| 2 clipped | Kotlin | Copy the window out of the PCM tap and keep capturing for the after-window, then encode the clip to **AAC in M4A** with `MediaCodec` and `MediaMuxer` (platform, no ffmpeg; about 30 to 60 KB per 10 s at 32 kbps; verified in S2) and store it. The clip is the record of the moment and survives until deleted |
| 3 transcribed | `:whisper` | Decode the clip to 16 kHz mono, run Whisper, store the text on the row. Runs **only** when charging, or when the Pending imports screen is opened, and **never below 15% battery**; each gate is checked before every clip |
| 4 queued | Dart | Build a one-quote Tippani Markdown file and upload it to `/import/auto` with `as=md`; see below. Paired and online only; otherwise the row stays and shows in the local Bookmarks list |
| 5 titled | Kotlin | Create the ABS bookmark at step 1 with a placeholder title; update the title here with a short excerpt of the transcript |

- **Window default: 90 s before and 30 s after** the press. The owner said "I need context as well", and because transcription is deferred and mostly happens on a charger, the cost is small (table below). Adjustable from 10 to 180 s per account. This is the plan's reading of the owner's answer; change it if wrong.
- **Cost per bookmark** (estimate; formula: Whisper time = window × real-time factor; battery % = time × 4 W ÷ 3600 ÷ 19 Wh × 100, assuming a 19 Wh battery and a 4 W CPU draw; the real-time factors are guesses for `base.en` on a recent arm64 phone and S1 measures them):

| Window | Whisper time at 0.1 / 0.2 / 0.4× real time | Battery per bookmark |
|---|---|---|
| 60 s | 6 / 12 / 24 s | 0.03 / 0.07 / 0.14% |
| 120 s (default) | 12 / 24 / 48 s | 0.07 / 0.14 / 0.28% |
| 180 s | 18 / 36 / 72 s | 0.10 / 0.21 / 0.42% |

  At 20 bookmarks a day with the default window the whole feature is about 1.4 to 5.6% of one battery spread over the charging that runs it. Storage is a clip of roughly 0.5 MB plus about 1 KB of text per minute.
- **The imports queue, as the server defines it.** The app writes one Markdown file per bookmark and uploads it as a unique filename `bookmark-<uuid>.md`, so the **batch is named by that file** and shows in Pending imports as one batch. The file has `type: book`, the work's own `title`, `author`, `language` and, when the item has them, `isbn`, so the quote **joins the existing work** (the server matches by ISBN, ASIN, or exact case-insensitive title and author; the mirror engine stores the same strings, so the match is exact). The quote is `> transcript` with `- location: 3:42:10 · Chapter 14`, `- date: <press time>`, `- note: From an audiobook bookmark`, `- tags: bookmark`.
- **Idempotency.** `/import/auto` has no Idempotency-Key. Before a re-upload the app asks `GET /import/staged` whether a batch with that filename exists; if it does, the row is marked queued and nothing is sent. After an approval the quote is in the library under the server's own dedupe (`(book_id, dedupe_hash)`), so a lost-response retry cannot create a second one.
- **Editing text in the queue (the support work, built first).** Today the server's queue edits tags, location, chapter, character and the target work but **not the quote text, note or translation** (V). The owner asked for that feature, so the first thing built is a server change that lets one staged quote's text and note be edited, and an app control on the Pending imports screen to trim it (see Foundations). A server that does not advertise the feature leaves the text read-only, and the owner then trims after approving, with the app's ordinary quote edit. Approving or discarding a whole batch is one press.
- **`voice` provenance.** A queued quote gets source `md`, because staged imports cannot carry `voice`. The tag and the note keep the provenance. Direct creation (`POST /quotes` with `source: voice` and an Idempotency-Key) would keep it but would skip the queue the owner asked for. Not asked again; the owner chose the queue.
- **Opening the Pending imports screen** shows a row "3 bookmarks waiting for transcription" at the top and, if the battery is 15% or more, transcribes them in the foreground; each finished one is uploaded and appears as its own batch. Below 15% it says "Battery below 15%: transcription paused" and does nothing else.
- **Failure leaves the earlier steps intact.** A failed upload leaves "Not queued. Retry." on the bookmark; the clip and the ABS bookmark are never lost. Acceptance: kill the process after each step and assert exactly one ABS bookmark and one batch.
- **Transcripts are text of a copyrighted book.** They sit in the owner's own library and sync to the owner's own server like any quote. Each bookmark has "Delete clip and transcript". Nothing is shared elsewhere.
- Bookmarks made in other ABS clients appear with no clip and a "Transcribe" action that works on downloaded books by slicing the cached file (`MediaExtractor`/`MediaCodec`).

### Capturing the audio: the PCM tap (V in source, proven in S2)

A custom `AudioProcessor` is installed by overriding `DefaultRenderersFactory.buildAudioSink` with `DefaultAudioSink.Builder.setAudioProcessors`. In `DefaultAudioSink.java` the order is trimming, channel mapping, to-16-bit, **custom processors**, silence skipping, Sonic. So the tap sees audio at 1x.

- `configure()` accepts only `ENCODING_PCM_16BIT`, otherwise throws `UnhandledAudioFormatException`.
- The tap downmixes to mono and resamples to 16 kHz into an int16 ring buffer sized to the longest allowed window (180 s: about 5.8 MB). `flush()` (a seek) clears it.
- **Float output stays off, and offload and tunneling are never enabled**, or the chain is bypassed. A JVM test asserts the sink is built that way.
- The tap sees audio slightly ahead of what is heard (the AudioTrack buffer). A press maps to a ring position from the media time carried with each buffer (`StreamMetadata.positionOffsetUs` plus samples counted), not the wall clock.
- A pause within the after-window ends the clip early; right after a seek the ring holds only audio since the seek. For downloaded books the cached file is the fallback (design B).

## Whisper on the phone

| Setting | Default | Options |
|---|---|---|
| Model | `base.en` q5_1 (60 MB) | `base.en` q8_0 (82 MB) or fp16 (148 MB); `small.en` q5_1 (190 MB) or fp16 (488 MB) |
| Language | English | none (English only, the owner's answer) |
| Window | 90 s before, 30 s after | 10 to 180 s |
| Runs | When charging, or when Pending imports is opened | never below 15% battery (a setting that cannot be set lower than 10%) |

- **Binding: whisper.cpp through a small JNI of our own**, not `whisper_ggml`. `whisper_ggml` needs the `ffmpeg_kit` plugin, accepts only WAV paths, downloads models into memory with no resume, builds without fp16 and needs Flutter plugins for a background job. The whisper.cpp Android example takes a `FloatArray` of 16 kHz mono PCM, which the clip decoder and the recorder produce.
- **What we write:** extend the example's JNI with a language argument, an abort callback and a progress callback; select the fp16 library on arm64 when `/proc/cpuinfo` has `fphp`; build arm64-v8a (and x86_64 for the emulator); link with 16 KB page alignment (`-Wl,-z,max-page-size=16384`); vendor whisper.cpp at a pinned tag (MIT).
- **Models** download through our own Kotlin downloader: `Range` resume, SHA-256 verified against the Hugging Face file digest (T0 records them), a Models screen with size and delete. Never in a backup and never bundled.
- **Dictating a quote.** Speak gets an engine choice per account: the phone's recogniser (today, may use Google online) or Whisper. Whisper records 16 kHz mono through `AudioRecord`, transcribes when you stop and lands in the same correction screen. It must also pass the battery gate: below 15% it falls back to the phone's recogniser with a note. No streaming partials.
- **Privacy.** Audio never leaves the phone. **Licences.** whisper.cpp MIT; weights Apache-2.0 (OpenAI) and MIT (the ggml repository), confirmed from the LICENSE files in T0.

## Grimmory

- **Sign in** as above; the vault's mutex serves Grimmory too.
- **Library:** `GET /api/v1/libraries`, `/shelves`, `/books/page` with `sort`, `facet`, `query`, `cursor` (V). Covers via `/api/v1/media/book/{id}/cover` (auth form U).
- **Download:** `GET /api/v1/books/{id}/download`, streamed (V); multi-file books through `download-all`. Range support U; without it a download restarts from zero. Stored under `files/books/{source}/{id}/`.
- **Bookmarks:** `/api/v1/bookmarks` CRUD (V): `cfi` (EPUB), `pageNumber` (PDF), `positionMs` with `trackIndex` (audio), `title`, `notes`, `color`, `priority`. The app lists all and creates only audio ones until a reader exists; creating an EPUB bookmark needs a CFI, which needs a reader. The screen says so.
- **Progress is not synced** (the owner's decision).
- **Stability:** `/api/v1` is a path prefix with no documented stability contract; the facts above are from `develop`. T0 pins the owner's release tag; contract tests fail on a version mismatch until a person re-verifies.
- Other protocols (OPDS, KOReader, Kobo, Komga) are not used.

## Jellyfin

- **Library:** `GET /Items?userId&includeItemTypes=Movie,Series&recursive=true&fields=ProviderIds,Overview,Genres,DateLastSaved&startIndex&limit` (V). A series is **one work** (`show`); seasons and episodes are not mirrored (open question D-E). Libraries visible follow the user's `EnabledFolders`; the server filters.
- **Incremental sync:** `minDateLastSaved` with `Fields=DateLastSaved`. **Deletions** have no feed (V): the run compares the id list and marks vanished items `missing` (the work stays).
- **Covers:** `GET /Items/{id}/Images/Primary?tag=…&maxWidth` (no `[Authorize]` in source; anonymous access unconfirmed, so the app sends the token anyway).
- **Identifiers:** `ProviderIds` (`Tmdb`, `Imdb`, `Tvdb`) are kept on the edition for matching. **They are not sent to the Tippani server on create**, because `POST /movies` with a `tmdb_id`, `source` or `source_id` triggers a provider fetch on the server (V). The mirror creates a plain row with title, year and kind; an optional `PUT /movies/{id}` with a title may then set `imdb_id`, `tmdb_id` and `tvdb_id` as plain columns (open question D-I).
- **Watch:** a **Watch** button on the work. The official Jellyfin app has no item deep link (V), so the plan offers both: **Open in browser** (`<server>/web/index.html#/details?id=<id>&serverId=<serverId>`, `serverId` from the sign-in result) and **Open Jellyfin app** (starts the app on its last server). Open question D-J picks the default.
- **Not planned:** an in-app player, downloads, watch-progress sync, transcoding.
- **Rate care:** never loop the password login; after three refused attempts stop and say so.

## Reading books: Readest parity

The owner's ruling: copy Readest and all of its reading and note-taking features. Readest is `readest/readest` (app 0.12.26), a Tauri and React app built on foliate-js. This section reproduces its features in this app. It does **not** copy its code (see the licence question below).

### Licence first

| Item | Finding (V) | Consequence |
|---|---|---|
| Readest | The unmodified GNU AGPL v3, "or any later version"; no exception text | Copying Readest **code** into this GPL-3.0 app attaches AGPL section 13 (network use) to the copied parts. That is a legal question for the owner or counsel, not decided here. The plan copies **features and behaviour**, written fresh |
| Readest's foliate-js | A fork, `readest/foliate-js` (AGPL territory) | Not used |
| foliate-js (stock) | MIT; vendored zip.js (BSD-3), fflate (MIT), PDF.js (Apache-2.0) | Used, pinned by commit |
| Grimmory's web reader | Vendors a modified foliate-js; Grimmory is AGPL-3.0 | Used only through its REST API, never its code |

### Engine decision

| Criterion (1 poor to 5 best, equal weight, scores are the research agent's judgement) | A. foliate-js in `flutter_inappwebview` | B. Readium Kotlin toolkit in a platform view | C. `flutter_readium` package |
|---|---|---|---|
| Format coverage versus Readest | 5 | 2 | 2 |
| CFI annotation fidelity | 5 | 2 | 2 |
| Search | 3 | 4 | 4 |
| TTS sentence highlight | 3 | 4 | 4 |
| Selection UX | 3 | 4 | 4 |
| Performance | 3 | 4 | 3 |
| APK size | 5 | 3 | 3 |
| Licence fit (GPL-3.0) | 5 | 5 | 5 |
| Maintenance burden | 2 | 3 | 2 |
| Testability | 3 | 2 | 2 |
| **Total** | **37** | **33** | **31** |

**Recommendation: A.** It is the only option that covers MOBI, AZW3, FB2 and CBZ as Readest does, and the only one that gives the standard CFI that Grimmory's reader also uses. Primary downside: foliate-js is explicitly unstable and unreleased (its README says expect API breaks), so the plan pins one commit, wraps it in a small adapter, and owns the whole bridge and the selection menu. Readium's EPUB navigator would win only if MOBI, AZW3 and FB2 were dropped; Readium has no PDF search or highlights and no MOBI, and `flutter_readium` demands a very new toolchain.

**How it runs.**

- `flutter_inappwebview` 6.1.5 (Apache-2.0; the stable line is old and a beta is active, maintained largely by one person, so it is pinned and wrapped). `webview_flutter` has no confirmed custom selection menu or request interception.
- The book is **never sent as base64** and never opened by URL (foliate-js's `open(url)` pulls the whole file into memory). A Dart loopback server serves the file with HTTP Range, and a custom foliate loader (`{loadText, loadBlob, getSize}`) reads ranges. Whether the package's own localhost server supports Range is not confirmed, so the plan uses a small Dart server of its own.
- The vendored JS is about 3.2 MB (PDF.js is 3 MB of it). foliate-js needs a recent System WebView (about version 89 or newer: `Intl.Segmenter`, private fields, top-level await). On Android 14 that is normally met; the app checks the WebView version on first open and says what to update. ES modules must load from `https://appassets.androidplatform.net` or a loopback origin, not `file://`.
- **Bridge messages** (the research agent's design; foliate-js has none of its own). Host to JS: open, goTo (cfi, fraction, href), next, prev, setAttributes, setStyles, add and delete annotation, search and clear, tts next, previous and setMark. JS to host: ready, metadata and toc, relocate (with the DOM range stripped), load, selection `{cfi, text, rect}`, show-annotation `{value, rect}`, create-overlay, link, search-result, tts-ssml, error. Annotations are re-added on each `create-overlay`.
- **Selection** is the main cost. The native Android selection handles work inside the iframes; the app suppresses the system menu and shows its own Flutter toolbar from the `selection` message.
- A book's scripts are not run, and the page loads under a content security policy, as foliate-js requires.

### Formats

| Format | Engine | Note |
|---|---|---|
| EPUB 2 and 3 | foliate-js | Reflowable and fixed layout |
| MOBI, AZW, AZW3 (KF8) | foliate-js | |
| FB2, FBZ | foliate-js | |
| CBZ | foliate-js | Fixed layout; wide-page spreads |
| PDF | foliate-js with PDF.js | Marked experimental by its author; larger PDFs are slow in a WebView. Highlights are stored as page and normalised rectangles; `pdfrx` (PDFium) is the fallback if PDF.js is too slow |
| TXT, Markdown, HTML | Converted to EPUB in Dart before opening | Readest does the same; TXT detects its encoding and chapter headings |
| DOCX, RTF | Converted to EPUB | As Readest |
| DRM | Not handled (Readest has none either) | |

### What is copied (Readest feature to this app)

| Area | Readest behaviour (V) | In this app |
|---|---|---|
| Reader chrome | Header bar, footer progress bar with optional page buttons, sidebar with tabs Contents, Annotations, Bookmarks and a search bar, a resizable notebook | Same, laid out for a phone: header and footer toggle on a centre tap; the sidebar and notebook are bottom sheets |
| Navigation | The page splits in halves and the middle quarter toggles the chrome; swap sides; swipe; pull down to bookmark; volume keys to turn pages (off by default); image tap or long press opens a viewer; pinch to zoom | Same, each switchable |
| Reading modes | Paginated or scrolled; scroll overlap and hidden scrollbar; auto-scroll (25 to 500 px/s); page-turn styles push, slide, curl; up to 2 columns; gap, margins (44 top and bottom, 16 sides), max width and height | Same |
| Aids | Reading ruler (band or line), paragraph mode, RSVP speed reading, zoom 50 to 500%, e-ink mode, a dual-book "Parallel Read" | Same except Parallel Read and the multi-window features, which have no phone equivalent |
| Header and footer info | Remaining time and pages, progress as fraction, percent or reference pages, clock, battery, stable page numbers (1500 characters per location) | Same |
| Fonts | Serif, sans, mono and CJK defaults; size 8 to 120, default 16; weight; ignore publisher fonts; override book font; custom fonts | Same, with the font files the app already bundles plus custom imports |
| Themes | default, gray, sepia, grass, cherry, sky, solarized, gruvbox, nord, contrast, sunset, each light and dark; three custom themes; background texture | Same palettes inside the reader; the app chrome stays Material You |
| Typography | Paragraph spacing 0.6, line height 1.4, word and letter spacing, text indent, justify, hyphenate; writing mode auto, horizontal, vertical, RTL; override book layout and colour; replace quotation marks; custom CSS for content and for the reader UI; dialogue highlighting; image contrast and invert in dark mode | Same |
| Settings scope | Global by default, per-book overrides | Same, per account ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md)) |
| Annotations | Highlight, underline, squiggly; colours red, yellow, green, blue, violet and custom; notes; bookmarks; "global" (every occurrence in the section); soft delete; range editor | Same data model (below) |
| Selection tools | 16 tools. Default: copy, highlight, annotate, search, dictionary, translate, speak, proofread; configurable | copy, copy link, highlight, annotate, search, dictionary, system dictionary, translate, speak, share, quote card. **Not copied:** AI context dictionary, X-Ray, vocabulary, proofread (all tied to Readest's AI or paid services) |
| Notebook | Notes grouped by chapter with search; a note editor | Same |
| Search | In book or in section; modes contains, whole words, regex, nearby words (10); match case and diacritics; history; results grouped by chapter with excerpts | Same. foliate-js search is slow on large books, so results stream in |
| Dictionary | Wiktionary, Wikipedia, the system dictionary, imported StarDict, MDict, DICT, slob and BGL dictionaries, web templates (Google, Urban Dictionary, Merriam-Webster, Goodreads) | Wiktionary, Wikipedia, the Android system dictionary through `ACTION_PROCESS_TEXT`, imported StarDict and MDict, and web templates; BGL, slob and DICT follow only if the importer is small |
| Translation | DeepL, Azure, Google (unofficial endpoint), Yandex (via Readest's proxy), custom translators and LLM prompts; whole-book bilingual translation; Word Lens | **DeepL and Azure with the owner's own key**, plus a custom OpenAI-compatible endpoint with the owner's key. The unofficial Google and Yandex routes and anything that needs a Readest login are not used. Whole-book bilingual translation is copied (translate on demand, cached) |
| Text to speech | Web Speech, Edge TTS, the native engine, Readest Voice (paid), a custom OpenAI-compatible service, EPUB Media Overlays; sentence or word highlight; gaps; sleep timer; stop at chapter end; offline voice cache | The Android system engine (the app already uses `flutter_tts`) driven by foliate-js's SSML, with sentence and word highlight, a sleep timer and EPUB3 Media Overlays; a custom OpenAI-compatible voice with the owner's key. Edge TTS (an unofficial endpoint) and Readest Voice are not used |
| Progress | Per-book progress (page of total) and CFI; KOReader sync (checksum by binary or filename) | Progress and CFI per book on the phone; KOReader sync is offered only if the owner asks (D-K). Grimmory progress sync is **not** built (the owner's decision) |
| Export | Markdown, plain text and a re-importable JSON, with a configurable template (title, author, date, cover, chapters, quotes, context sentence, notes, page, link type, excluded colours and styles) | Same, plus the app's own Tippani Markdown, which is what the Tippani server imports |
| Import | ReadEra annotations, `.mrexpt`, CrossPoint clippings | Same, plus Tippani Markdown and the Readest JSON |
| Share | Text, QR, quote card image | The app's existing Share screen and picture, extended to a book quote |
| Library | Import from file, folder, pasted text, web page, feed URL and OPDS catalogues; grid or list; group by series, author, tag, subject, status; sort by title, author, updated, created, series, size, format, published, progress, pages, time remaining; reading status unread, reading, finished, abandoned; metadata editing | The Tippani library already groups and sorts works and keeps status. Local files become works with a `file` edition whose source is the device. OPDS catalogues and the other import routes are added to the same Add flow |
| Accessibility | Aria labels; keyboard navigation | TalkBack over the WebView (Android exposes WebView content to it) and labelled controls; hardware keys for page turns |

**Not reproduced because Readest needs its own accounts, servers or paid plans:** Readest cloud sync of books, configs, notes and stats; Readest Voice; the AI Assistant, X-Ray and context dictionary; quota-gated translators; share links and "send to device" by email. **Readest has no reading statistics** (its own README lists them as planned), so there is nothing to copy. Its Readwise, Hardcover, Notion and Obsidian pushes are not built: this app's own export and the Tippani server are the destinations, unless the owner asks (D-K).

### Notes become Tippani quotes

The owner's product is quotes. A highlight is a quote on the work, with the book's text, the note, the chapter and the location.

| Readest `BookNote` field | This app |
|---|---|
| `type`: bookmark, annotation, excerpt, notebook | Bookmark: a reading bookmark; annotation and excerpt: a quote; notebook: a note on the work |
| `cfi` (and PDF `page`, normalised rectangles) | Kept in `library.db` on the quote's local row; sent to the server as the quote's `location` text (a readable chapter and page) because the server has no CFI field |
| `text`, `note` | The quote text and note |
| `style` (highlight, underline, squiggly), `color` | Kept locally; the quote's colour (the server has a quote colour) takes the nearest of its own colours |
| `global` | Kept locally |
| `createdAt`, `updatedAt`, `deletedAt` | The quote's dates; a deleted highlight goes to the bin like any quote |

Quotes made while reading are created directly (`POST /annotations` with `source: manual` and the work's server id, with an Idempotency-Key), not through the imports queue. A highlight you make on the phone and a bookmark on Grimmory are linked by the Grimmory annotation endpoints below. **No CFI field was found among the quote fields the server exposes** (T0 reads the annotation schema to confirm). If there is none, a server change is proposed so a quote can carry one; until then a quote's CFI exists only on the phone that made it. A highlight made on another phone is placed by matching its text in the section (the same text-matching approach Readest's fallback uses).

### Grimmory sync of highlights and bookmarks

`/api/v1/bookmarks` (EPUB `cfi`, PDF `pageNumber`) and `/api/v1/annotations` (`cfi`, `text`, `color`, `style` highlight, underline, strikethrough or squiggly, `note`, `chapterTitle`) are read and written both ways for books mirrored from Grimmory (V from `develop`). Grimmory's reader vendors a modified foliate-js, so CFIs from stock foliate-js are expected to read there; this is verified by a test against a real Grimmory export before any sync is turned on. Conflicts are chosen per item as elsewhere, and a highlight deleted on either side is deleted on the other after a confirmation the first time. Progress sync stays off.

## Mirroring: every item becomes a work

The owner's rule: all items of the chosen libraries become Tippani works automatically, and reach the server.

- **Choose first.** Adding a source lists its libraries with counts; the owner ticks which to mirror (nothing mirrors by default). A preview says "Mirror 1,240 items from 3 libraries" and what will be skipped as already in the library.
- **Match before creating.** An item joins an existing work by ISBN or ASIN, then normalised title and creator (the server's own rule), and becomes an **edition** of it; otherwise a work is created. A weak match asks "Link this book?" with both covers. A strong match links silently and is listed in the run's report with Undo.
- **Kinds:** ABS and Grimmory become `book` works; Jellyfin movies `film`; series `show`. (The app's `other` kind pushes to `/books`; mirrored items never use it.)
- **Fields sent to the server are only** title, author or director, language, year and ISBN or ASIN: no `source`, `source_id`, `tmdb_id` or `cover_url` (any of them can make the server call a provider or fetch an image). Covers stay on the phone, cached from the source; uploading them to the server is not planned (open question D-C).
- **Volume.** Works are created locally in one transaction per page and pushed by the ordinary push sync, **at most two at a time** (the server's write pool is four connections and has no batch route and no rate limit), as a resumable cursor, with progress on the Server screen. Thousands of plain creates cost the server only SQLite writes (V).
- **Triggers (events only):** adding or editing a source, the app opening, the daily sync, and a "Refresh libraries" press. No timer.
- **Removal:** an item gone from its source marks the edition `missing`; the work stays, and so do its quotes.
- **Undo a run.** Every run has a `mirror_batch` id on the works it created. **Undo this run** deletes the works of that run that have no quotes and no edits, locally and (paired) on the server, where deletes go to the bin and can be restored. A work the owner has since touched is left and listed.
- **Duplicates on the server** (a book already pushed from another phone) are linked by the existing pull sync rules, not duplicated ("a work on both sides is linked, not copied").

## Navigation and the library

**Model: the work is the unit, editions hang off it.** `Work` keeps `kind`. A `work_editions` table holds zero or more editions per work: `{work_id, type: audio | file | video, source_id, remote_id, state, matched_by, mirror_batch}`. "Quotes only" is a work with no edition, as a book is today. A movie's `video` edition is a link to Jellyfin.

| Option | Description |
|---|---|
| **A. One Library, editions on the work** | Chips: All, Listening, Reading, Watching, Quotes only, Downloaded. Cards show edition glyphs. The work page holds the edition strip. A mini-player above the bottom bar on every screen |
| B. Separate libraries | Sections Audiobooks, Books, Films and shows, Quotes. A book in two forms appears twice |
| C. A new Listen tab | A fifth bottom tab; Library unchanged |

Scores, 1 (poor) to 5 (best), unweighted:

| Criterion | A | B | C |
|---|---|---|---|
| One place per work | 5 | 2 | 2 |
| Taps from opening the app to resuming | 5 | 3 | 3 |
| Keeps the four tabs of [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md) uncrowded | 5 | 5 | 2 |
| Quotes stay with the work in every form | 5 | 3 | 3 |
| Clear what a work with no edition is | 4 | 3 | 3 |
| Build cost (higher is cheaper) | 3 | 4 | 3 |
| **Total** | **27** | **20** | **16** |

**Recommendation: A.** Primary downside: matching can be wrong, and with automatic mirroring a wrong match is now silent in the strong cases. Mitigations: only exact ISBN, ASIN or title-and-creator matches link silently; every link has Undo and Unlink; the run report lists them; unlinking never deletes a file or a bookmark.

- **Settings > Libraries** holds ABS, Grimmory, Jellyfin, Whisper and Downloads (per account). The Server tab stays the Tippani server.
- **Home** gets a Continue listening row when a source exists.

## Data, backup and lifecycle

**`library.db`** (Dart, next migration; schema 7 at the pin): `work_editions(work_id, type, source_id, remote_id, state, matched_by, mirror_batch)`; `mirror_batches(id, source_id, started, finished, created, linked)`.

**`listen.db`** (native): `meta(active_scope)`, `sources(id, type, url, account_scope, secret)`, `items`, `tracks`, `chapters`, `progress`, `bookmarks(uuid, item, position_s, state, clip_path, transcript, abs_synced, batch_filename)`, `jobs`.

**Android's own backup.** The manifest has no `allowBackup` or data-extraction rules, so the platform copies app data to a new phone by default. The plan adds `dataExtractionRules` and `fullBackupContent` that **exclude** `listen.db`, clips, `files/listen`, `files/books`, Whisper models and the Keystore-wrapped secrets, and leave everything else as it is.

**The app's own backup** ([ADR-0009](ADR-0009-A-Backup-Is-Checked-Whole-Before-Any-Of-It-Is-Written.md)) carries `work_editions`, `mirror_batches` and, as text, bookmarks and transcripts; never tokens, downloads, clips, models or the stream cache. After a restore the editions point at sources that may not exist: they show "Source not signed in" with a Sign in action, and nothing is deleted. T0 checks `lib/harness/backup.dart` for size limits before transcripts are added.

| Event | Tokens | Downloads, clips, models | Bookmarks and transcripts | In-flight jobs |
|---|---|---|---|---|
| Unpair the Tippani server | Kept; sources are the phone's, as with the unpaired preference set | Kept | Kept; queued uploads wait | Continue |
| Sign out of a source | Deleted | Kept, still playable | Kept | Cancelled |
| Remove a source | Deleted | Deleted after a confirmation naming the size | Kept as text | Cancelled |
| Switch Tippani account | Hidden (a different scope) | Hidden, kept on disk | Hidden | Paused |
| Delete a work | Edition links deleted, files asked about | Asked | Kept until the work's quotes are | Cancelled |

## Network and offline behaviour

| State | Browse | Play | Download | Bookmark | Transcribe | Mirror |
|---|---|---|---|---|---|---|
| Online | live | stream or cache | runs | instant | charging or queue opened, battery 15%+ | runs |
| No Twingate | last copy, dated | cached only | waits | instant | same | waits |
| Source refused the refresh | last copy | cached only | stops, says why | instant | same | stops, says why |

The broken-link mark and once-per-awake toast of [ADR-0033](ADR-0033-The-Broken-Link-Is-One-Mark-And-One-Toast.md) cover the Tippani server and every source together.

## Settings (per account, [ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md))

Added to `PrefKeys`: skip back and forward seconds, default speed, sleep timer choices, smart rewind, Wi-Fi only, storage ceiling, buffer ahead and behind, delete after finishing, bookmark window, Whisper model, minimum battery, speech engine, mirrored libraries per source, Jellyfin watch default. Source credentials, downloaded files and clips are per account too.

## Quality, strings and the gate

- **Every string is a token** with English and Bengali (`test/l10n/tokens_test.dart`, `dart run tool/gen_l10n.dart`). Android Auto tab names, notification, widget and custom-button labels are native strings and need `res/values-bn`.
- **Icons.** New headphones, book, film and bookmark glyphs are added to the generated Tabler set. The notification, widget and Android Auto icons must be Android vector drawables, outside Tabler; the ADR records that exception to [ADR-0005](ADR-0005-Material-You-Only.md).
- **Accessibility.** TalkBack labels for the player, the bookmark button and edition glyphs; the Android Auto tick has a spoken confirmation.
- **Tests use the app.** Widget tests against `test/support/memory_library.dart` and new fakes `fake_abs.dart`, `fake_grimmory.dart`, `fake_jellyfin.dart` that answer the routes marked V; the existing `fake_server.dart` gains `/import/auto` and `/import/staged`. Contract tests pin each route's shape. Kotlin JVM tests that must read internals (ring buffer, eviction, tree builder) name that as a declared exception in the file header, as the repo's rule requires.
- **Mutation:** each journey is run with its decisive action deleted and must fail, named in the commit.
- **CI:** add a Kotlin unit-test step and an NDK build to `ci.yml`; measure the added time and APK size (arm64).
- **Dependencies to licence-check (ADR-0002):** OkHttp, WorkManager, Media3, whisper.cpp, any PKCE hash helper.
- **The cloud container** can run Dart analyze and tests and, with the Android SDK added, a debug build. It cannot run Android Auto, a head unit, Whisper on the owner's phone, or a sign-in through the owner's Authelia or Jellyfin. Those are owner-run items.

## Foundations: built first

The owner's order: once the plan is final, the support work comes first. These are the pieces that stand on their own, have a caller today, and are testable against the existing fakes. Each is one commit with its tests and docs, and none of them needs a new subsystem.

| # | Foundation | Repository | What it is | Acceptance |
|---|---|---|---|---|
| F1 | **Edit a staged quote's text** (built) | Tippani server | A new door, `PATCH /import/staged/quotes/{id}`, takes `quote`, `note` and `translation` (any of them) for one row. The bulk endpoint is unchanged and still refuses words, as its ADR and tests state. The row's `dedupe_hash` moves with the text; words equal to another waiting quote's in the same work answer 409; no words left answers 400; another reader's row answers 404. `/capabilities` lists `staged-text-edit` and `apiRevision` is 13. Recorded as the server's ADR-0937 rather than a queue plan, because it was built in the same change | Go tests through the HTTP API (`import_staged_text_test.go`): edit then list returns the new text; approval writes it; a clash gives 409; a bad edit gives 400; a foreign row gives 404; the bulk door still refuses words; the capability appears; the app's own bookmark file queues, joins its book and lands trimmed |
| F2 | **Edit and trim a quote on Pending imports** (built) | App | The existing quote edit sheet on `lib/screens/staging_screen.dart` gains Text and Note fields when the server lists `staged-text-edit`, and a **Trim** control: the text is shown as sentences and the owner keeps a contiguous run of them. Without the capability the fields are read-only and the sheet says why | A widget test drives the real screen against the fake server: open Pending, press edit, change the text, save, and see the new text listed; with an older server the fields are read-only; the fake server's `/import/staged/bulk` honours `text` |
| F3 | **Dictated quotes send `voice`** (built) | App | Quotes whose text came from dictation are created with `source: voice`, as the server accepts (`capabilities` lists `voice-source`); the stale comment in `lib/sync/push_sync.dart` is replaced. Older servers keep receiving `manual` | A sync test: a dictated quote reaches the fake server with `voice` when the capability is listed and `manual` when it is not; the other sources are unchanged |
| F4 | **One-quote file for the imports queue** (built) | App | A pure builder writes the Tippani Markdown for one quote on one work (the work's own `title`, `author`, `language`, `isbn`; the quote with `location`, `date`, `note`, `tags`); an `ImportService` method uploads it with a unique name `bookmark-<uuid>.md` and first asks `GET /import/staged` whether a batch with that name exists, so a retry never queues it twice | The builder's file round-trips through the app's own Markdown reader to the same work and quote; an upload sends one multipart file with that name; a second call with the batch already listed sends nothing |

Deferred foundations, with the reason: the `work_editions` table (no caller until the mirror engine), the new Tabler glyphs (the icon fonts are a generated subset and the generator is not in this repository), the backup exclusion rules (they name directories that do not exist yet), the Kotlin and NDK steps in `ci.yml` (no native code yet), and fakes for Audiobookshelf, Grimmory and Jellyfin (written with the clients that call them, from the routes marked V above).

## Tasks

The owner's order is Foundations first. The owner's primary ask, Android Auto, is first among the spikes. Sizes: S under a day, M a few days, L about a week or more. A task is not done until its acceptance passes and its mutation check was run.

- [x] **F1 · Server: edit a staged quote's text (S).** Built, with the server's ADR-0937.
- [x] **F2 · App: edit and trim on Pending imports (S).** Built, with ADR-0035.
- [x] **F3 · App: `voice` for dictated quotes (S).** Built. It also fixed a latent bug: scanned quotes were being sent as `manual`.
- [x] **F4 · App: the one-quote file and its upload (S).** Built.
- [ ] **T0 · Re-verify and read the rest (S).**
  ```bash
  git diff --stat 90606c9..HEAD -- lib/library/models.dart lib/library/library_store.dart lib/screens/library_widgets.dart lib/screens/staging_screen.dart lib/imports lib/sync/push_sync.dart lib/app_controller.dart lib/settings lib/capture/voice_listener.dart android/app/src/main android/app/build.gradle.kts
  git log --oneline 90606c9..HEAD -- docs/wiki/ADR-Index.md CHANGELOG.md
  git grep -n "schemaVersion = " HEAD -- lib/library/library_store.dart
  git grep -n "class Work\b" HEAD -- lib/library/models.dart
  ```
  Then read: the owner's ABS `GET /status` against v2.38.0 (re-read changed routes); Jellyfin's real release against `master`; Grimmory's release tag, public settings, download ranges and its annotation and bookmark schema; the owner's Authelia `/.well-known/openid-configuration`; Hugging Face model digests; `lib/harness/backup.dart` size limits; Flutter's `minSdkVersion`; the release workflow's signing; the Tippani server's annotation schema (is there a field a CFI could use); open branches and pull requests on the cited paths. Confirm the test connection works for each source over the owner's Twingate HTTPS. Correct every U above.
- [ ] **S3 · Android Auto spike (M, owner-run on a head unit and the Desktop Head Unit).** Media3 service with the official four-tab tree; the `ChapterPlayer` on `SimpleBasePlayer`; the Jump, Speed and Bookmark custom actions; resumption. Gate: no autoplay; the seek bar spans the chapter on **both the full screen and the quarter-screen card**, or the card is recorded as not drawing one; each custom action's placement is recorded for both screens; a seek drag does not stutter; the tree answers with the phone locked and the app dead. If the wrapper is fragile, try one clipped `MediaItem` per chapter; failing both, decide the `audio_service` fallback.
- [ ] **S2 · PCM tap and clip spike (M).** Tap in ExoPlayer with the sink built float-off and offload-off; press-to-ring mapping; seek behaviour; ABS direct play of an m4b and an mp3; encode a clip to AAC in M4A with `MediaCodec` and `MediaMuxer`. Gate: a transcript from the tap equals one from the cached file for the same passage; the clip plays back.
- [ ] **S1 · Whisper spike (M, owner-run).** whisper.cpp JNI in `:whisper`, `base.en` q5_1 and q8_0, a 120 s clip on the owner's phone: time, peak memory, cancellation, thermal behaviour, the battery gate. Gate: a 120 s clip under 90 s on a charger with the player process unharmed; the measured real-time factor replaces the guesses in the cost table.
- [ ] **S4 · Reader spike (M, owner-run).** `flutter_inappwebview` with pinned foliate-js and a Range-capable Dart loopback server: open an EPUB, a MOBI, a CBZ and a PDF; one 100 MB EPUB for memory and speed; selection to a Flutter toolbar; a highlight drawn and re-drawn on `create-overlay`; its CFI read back; a CFI from stock foliate-js located by a real Grimmory export. Gate: the 100 MB book opens without the app being killed; selection to toolbar under 200 ms; a Grimmory CFI resolves. Otherwise the plan falls back to Readium (dropping MOBI, AZW3 and FB2) or pdfrx for PDF.
- [ ] **P1 · Sources and sign in (L).** Settings > Libraries, `TokenVault`, the ABS, Grimmory and Jellyfin flows, the intent filter with pending-flow and `state` checks, forward-auth detection, test connection, sign-out, "sign in again". Acceptance: fakes of the three servers sign in, survive a restart and a process killed mid-flow, expose nothing to another account; the mutex test passes; no token appears in `AppLog`.
- [ ] **P2 · Native service, ABS browse and the Audiobookshelf player (L).** `ListenService`, the `ChapterPlayer`, the full player, mini player, chapters list, speed, sleep timer (fade, chime, shake, auto timer), auto rewind, jump actions, Chapter Track and Total Track, the playback settings, the media-button rules, the Android Auto tree and actions from S3. Acceptance: a fake ABS item plays; every rule in "The player copies the Audiobookshelf app" has a test or is listed as owner-run; position survives a restart; the JVM tree test; an owner head-unit checklist.
- [ ] **P3 · Offline (L).** Downloads page, the cellular policies, user-initiated transfer jobs, resumable `.part` files, rolling buffer, eviction, ceiling, storage-full. Acceptance: airplane-mode playback of a downloaded book; the buffer follows the playing chapter; a killed download resumes.
- [ ] **P4 · Progress (M).** Session sync while playing (15 s, 60 s metered), local session upload by event, the banner for a newer position elsewhere, the sync-failed icon. Acceptance: offline listening uploads once; an older local session leaves newer server progress alone.
- [ ] **P5 · Bookmarks, clips and Whisper (L).** The ABS-style bookmark UI, the state machine, the tap, clip encode, transcription gates (charging or queue opened, 15% battery), the one-quote file through F4, the "waiting" row on Pending imports, the ABS bookmark, the Models screen, the Whisper dictation engine. Acceptance: kill the process after each step and get exactly one ABS bookmark and one batch; below 15% nothing transcribes; an approved bookmark joins its existing work.
- [ ] **P6 · Mirror engine and unified library (L).** `work_editions`, `mirror_batches`, matching with Undo and Unlink, per-library choice, the preview, throttled push, undo of a run, chips, card glyphs, the Continue row, per-account everything. Built on ABS first. Acceptance: a book on two sources is one card; a re-run creates nothing new; undo removes only untouched works; a 2,000-item fake library mirrors without exceeding two concurrent creates.
- [ ] **P7 · Grimmory (M).** Sign in, library, resumable download where ranges exist, bookmarks CRUD, contract tests pinned to the tag, its mirror. Acceptance: a fake Grimmory book downloads and its bookmarks round-trip.
- [ ] **P8 · Jellyfin (M).** Library read, incremental sync, id-diff for removals, Watch buttons, mirror of movies and shows. Acceptance: a fake Jellyfin mirrors as `film` and `show` works with no provider ids sent on create; Watch opens the browser URL with the right ids.
- [ ] **R1 · Reader core (L).** The WebView adapter, the Range server, the bridge, TXT, Markdown, HTML and DOCX conversion, the reader chrome, contents, tap zones and gestures, reading modes and aids, progress. Acceptance: the JS bridge is tested in headless Chromium against pinned foliate-js; widget tests drive the chrome against a fake bridge.
- [ ] **R2 · Reader settings (M).** Fonts, themes, custom themes, typography, writing modes, custom CSS, per-book overrides, PDF options. Acceptance: each setting changes the attribute or style the bridge is told about.
- [ ] **R3 · Annotations and notes (L).** Highlight, underline, squiggly and colours; the selection toolbar; notes; the notebook; bookmarks; quotes through direct create with an Idempotency-Key; export and import; share and quote card. Acceptance: a highlight survives a restart, appears as a quote on the work, and exports to Markdown in the template's shape; deleting it moves the quote to the bin.
- [ ] **R4 · Search and lookup (M).** In-book search modes, dictionaries (Wiktionary, Wikipedia, system, StarDict and MDict import), web templates, translation with the owner's keys, whole-book bilingual translation.
- [ ] **R5 · Reading aloud (M).** foliate-js SSML to the system engine, sentence and word highlight, sleep timer, chapter-end stop, Media Overlays.
- [ ] **R6 · Library import (M).** Local files and folders, pasted text, OPDS catalogues, covers, metadata editing, the `file` edition.
- [ ] **R7 · Grimmory highlights and bookmarks (M).** Two-way sync through its annotation and bookmark endpoints, after the CFI check from S4; no progress sync.
- [ ] **P9 · Hardening and release (M).** Battery prompt, notification denial, backup rules, TalkBack, Bengali strings, `UI-Glossary`, changelog, ADRs, `Developing` file map, `Troubleshooting` rows for each new code, the owner-run checklist, release notes. Behind a "Listening (preview)" and a "Reading (preview)" switch until the owner-run items pass.
- [ ] **Not in this plan:** Play Store, iOS, podcasts, Jellyfin playback, downloads and watch progress, Grimmory progress sync, physical-button bookmarks, KOReader and Kobo sync (KOReader on request), Readest's cloud, voice, AI and paid features, reading statistics, a cast button.

## Decisions

New ADRs at build time (numbers taken then, after the last in `ADR-Index.md`; 0035 onward at the pin): sources and their sign-in; native service owns playback, tokens and media state; the player copies the Audiobookshelf app and reports a chapter to the car; the work holds editions and sources mirror into the library; progress, its playback clock and the banner-not-stop conflict rule; Whisper on the phone, its separate process and its gates; bookmarks reach the library through the imports queue by a uniquely named file; the staged-quote text edit; the reader engine, its pinned foliate-js and the licence stance; quotes made while reading are direct creates; event-only retries.

## Open questions for the owner

| # | Question | Recommended | Cost of the other |
|---|---|---|---|
| L-1 | **Legal:** Readest is AGPL-3.0. The plan copies features and writes the code fresh. If you want Readest's actual code or its foliate-js fork, that needs a legal decision | Copy features only, use stock foliate-js | Reusing code attaches AGPL section 13 to those parts |
| D-K | Readest's KOReader sync, Readwise, Hardcover, Notion and Obsidian pushes: build any? | None now; add on request | Each is a separate integration with its own keys |
| D-R | Translation: DeepL and Azure with your own keys, plus a custom OpenAI-compatible endpoint; the unofficial Google and Yandex routes are not used | As written | The unofficial routes can stop working or breach terms |
| D-V | Text to speech: system engine only, or also a custom OpenAI-compatible voice with your key | System engine, custom optional | Edge TTS (unofficial) is not used |
| D-J | Which Watch button is the default for a Jellyfin title: browser or the Jellyfin app | Browser, with the app as the second button | The app opens on its home screen |
| D-E | Mirror only whole shows, or seasons and episodes too | Whole shows | Thousands more works |
| D-C | Upload mirrored covers to the Tippani server | No | Server cover storage grows |
| D-I | Store Jellyfin's imdb, tmdb and tvdb ids on the server's movie rows after creation | Yes, as an optional second step | No id matching later |
| D-W | Is a 90 s + 30 s default window the context you meant | Yes | Too much or too little text per bookmark |

See also: [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md) · [ADR index](ADR-Index.md)
