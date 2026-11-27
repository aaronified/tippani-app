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
| Network and certificates | HTTPS over Twingate, "same as Tippani" |
| Android | 14 or newer |

## What is verified and what is not

**V** read in primary source this session; **I** inference from source; **U** not yet verified. Task T0 closes every U.

| Fact | Level | Evidence |
|---|---|---|
| ABS v2.38.0 is latest. Login `POST /login`; header `x-return-tokens: true` returns `user.accessToken` and `user.refreshToken` in the body | V | `advplyr/audiobookshelf` `package.json`, `server/Auth.js:325` |
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
| Tippani Markdown (`as=md`) needs `type:`, `title`, optional `author`, `language`, `isbn` for a book, and `> text` with `- location:`, `- note:`, `- tags:`, `- date:`; there is no `source` or tmdb key | V | `importer/markdown.go:93-`, `movie_markdown.go:166-` |

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

### Grimmory (V from `develop`; T0 pins the release tag)

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
| Libraries, items, series, authors, search | Dart: `GET /api/libraries`, `/api/libraries/:id/items` (`limit`, `page`, `sort`, `minified=1`), `/api/items/:id?expanded=1&include=progress`, `/api/libraries/:id/series`, `/api/libraries/:id/search?q=`, `/api/libraries/:id/personalized` |
| Covers | `GET /api/items/:id/cover?width&format=webp&ts`; no token needed |
| Start | Kotlin: `POST /api/items/:id/play` with `forceDirectPlay: true` and `supportedMimeTypes`; if the answer is a transcode (HLS), the app plays the `m3u8` as is |
| Stream a track | `GET {contentUrl}` (`/api/items/:id/file/:ino`) with the header; never `?token=` in a URL |
| Session | `POST /api/session/:id/sync {currentTime,timeListened,duration}` about every 15 s **while audio plays**; `POST …/close` on stop |
| Offline listening | A local session (UUID, `updatedAt` = last listened time) uploaded by `POST /api/session/local-all` when ABS is next reached |
| Bookmark | `POST /api/me/item/:id/bookmark {time, title}`; no title limit; a short excerpt is kept as the title |
| Download | `GET /api/items/:id/file/:ino` per audio file with `Range` from the `.part` length; the zip route is never used. **The Download button follows `user.permissions.download`** |

Behaviours fixed in this revision:

- **Tracks and chapters.** A multi-file book is a playlist with `startOffset`; position = `startOffset` + track position and is what is sent as `currentTime`. Chapters come from ABS `chapters`; with none, none are invented.
- **Podcast libraries are out of scope**; book libraries only.
- **Series order** follows ABS series sequence.
- **Audio focus** handled by Media3 (pause for a call, duck for navigation prompts); `setHandleAudioBecomingNoisy(true)` pauses on Bluetooth or headphone disconnect.
- **Headset and steering-wheel media buttons** keep their play, pause, next and previous meaning through Media3's defaults. Only a bookmark from a physical button is not offered.
- **Smart rewind:** after a pause longer than five minutes, resume 10 s earlier, growing to 30 s (settings).
- **Positions are seconds in the whole book** everywhere; converted to a track and offset only at the player.
- **Conflict rule, driver-safe.** ABS already applies the rule: an offline session's progress is applied only if its `updatedAt` is not older than stored progress. The app adds no blocking prompt. Android Auto and `onPlaybackResumption` resume the **local** position; on the phone, when ABS holds a newer position from another device, a banner offers "Jump to 55:00 from Pixel" ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md): chosen per item; [ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md): never stops for a conflict; a banner is not a stop; the new ADR records this).
- **The 15-second progress clock** exists only while audio plays; it is not an idle or retry timer, and the new ADR says so.

## Android Auto

- Manifest: `automotive_app_desc` (`uses name="media"`), Media3 intent filters, `foregroundServiceType="mediaPlayback"`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`.
- **No autoplay on connect.** `onPlaybackResumption` restores the last item and position from `listen.db` using local data only.
- **Browse tree** (4 root tabs, all browsable): **Continue**, **Downloaded**, **Library** (ABS libraries, series, authors, items; depth limits U, S3), **Bookmarks** (recent bookmarks; a tap seeks; a clip not yet transcribed says so). An item opens into its chapters. Search arrives through `onGetSearchResult` and `onPlayFromSearch`.
- **Bookmark button.** `MediaSession.Builder.setMediaButtonPreferences([bookmark])`, session command `BOOKMARK`, added for the Android Auto controller (`isAutoCompanionController`). Media3 places custom buttons in `SLOT_OVERFLOW` by default; skip slots are reserved so the button is as visible as the head unit allows. Where it lands is S3's gate; if it is in an overflow menu the owner decides.
- **Feedback with no toast.** A press swaps the icon to a tick for two seconds and plays a short tone. A failed press swaps to a cross and a different tone; the clip row exists before either.
- Nothing on the car screen needs reading; transcription happens later.

### Triggers

| Trigger | Surface |
|---|---|
| Bookmark button | Android Auto now-playing |
| Notification action | Phone lock screen and shade |
| Widget | Home screen (bookmark, play/pause) |
| In-app button | Player screen |
| Physical buttons | Not a bookmark source; they keep their playback meaning |

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
- **What the queue cannot do (V).** Its quote text, note and translation are not editable; tags, location, chapter, character and the target work are. To shorten a transcript the owner has two paths: approve it and edit the quote afterward in the library (the app's ordinary edit), or open the bookmark in the app's local Bookmarks list and trim it **before** it is queued (optional; with the default flow the row is queued as transcribed). Approving or discarding a whole batch is one press.
- **`voice` provenance.** A queued quote gets source `md`, because staged imports cannot carry `voice`. The tag and the note keep the provenance. Direct creation (`POST /quotes` with `source: voice` and an Idempotency-Key) would keep it but would skip the queue the owner asked for. Open question D-P.
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

## Tasks

The owner's primary ask, Android Auto, comes first among the spikes. Sizes: S under a day, M a few days, L about a week or more. A task is not done until its acceptance passes and its mutation check was run.

- [ ] **T0 · Re-verify and read the rest (S).**
  ```bash
  git diff --stat 90606c9..HEAD -- lib/library/models.dart lib/library/library_store.dart lib/screens/library_widgets.dart lib/screens/staging_screen.dart lib/imports lib/sync/push_sync.dart lib/app_controller.dart lib/settings lib/capture/voice_listener.dart android/app/src/main android/app/build.gradle.kts
  git log --oneline 90606c9..HEAD -- docs/wiki/ADR-Index.md CHANGELOG.md
  git grep -n "schemaVersion = " HEAD -- lib/library/library_store.dart
  git grep -n "class Work\b" HEAD -- lib/library/models.dart
  ```
  Then read: the owner's ABS `GET /status` against v2.38.0 (re-read changed routes); Jellyfin's real release against `master` (the header, Quick Connect and `/Items` calls); Grimmory's release tag, public settings and download ranges; the owner's Authelia `/.well-known/openid-configuration`; Hugging Face model digests; `lib/harness/backup.dart` size limits; Flutter's `minSdkVersion`; the release workflow's signing; open branches and pull requests on the cited paths. Confirm the test connection works for each source over the owner's Twingate HTTPS. Correct every U above.
- [ ] **S3 · Android Auto spike (M, owner-run on a head unit or the Desktop Head Unit).** Media3 service, four-tab tree, `BOOKMARK` in `setMediaButtonPreferences`, resumption. Gate: no autoplay; the button is visible and its placement recorded; the tree answers with the phone locked and the app dead. Otherwise decide the `audio_service` fallback.
- [ ] **S2 · PCM tap and clip spike (M).** Tap in ExoPlayer with the sink built float-off and offload-off; press-to-ring mapping; seek behaviour; ABS direct play of an m4b and an mp3; encode a clip to AAC in M4A with `MediaCodec`/`MediaMuxer`. Gate: a transcript from the tap equals one from the cached file for the same passage; the clip plays back.
- [ ] **S1 · Whisper spike (M, owner-run).** whisper.cpp JNI in `:whisper`, `base.en` q5_1 and q8_0, a 120 s clip on the owner's phone: time, peak memory, cancellation, thermal behaviour, the battery gate. Gate: a 120 s clip under 90 s on a charger with the player process unharmed; the measured real-time factor replaces the guesses in the cost table.
- [ ] **P1 · Sources and sign in (L).** Settings > Libraries, `TokenVault`, the ABS, Grimmory and Jellyfin flows, the intent filter with pending-flow and `state` checks, forward-auth detection, test connection, sign-out, "sign in again". Acceptance: fakes of the three servers sign in, survive a restart and a process killed mid-flow, expose nothing to another account; the mutex test passes; no token appears in `AppLog`.
- [ ] **P2 · Native service, ABS browse and stream playback (L).** `ListenService`, player, chapters, speed, sleep timer, mini-player, Now Playing, the Android Auto tree and button from S3. Acceptance: a fake ABS item plays; position survives a restart; the JVM tree test; an owner head-unit checklist.
- [ ] **P3 · Offline (L).** Downloads screen, user-initiated transfer jobs, resumable `.part` files, rolling buffer, eviction, ceiling, storage-full. Acceptance: airplane-mode playback of a downloaded book; the buffer follows the playing chapter; a killed download resumes.
- [ ] **P4 · Progress (M).** Session sync while playing, local session upload by event, the banner for a newer position elsewhere. Acceptance: offline listening uploads once; an older local session leaves newer server progress alone.
- [ ] **P5 · Bookmarks, clips and Whisper (L).** The state machine, the tap, clip encode, transcription gates (charging or queue opened, 15% battery), the one-quote Markdown upload and its filename check, the "waiting" row on Pending imports, the local Bookmarks list, the ABS bookmark, the Models screen, the Whisper dictation engine. Acceptance: kill the process after each step and get exactly one ABS bookmark and one batch; below 15% nothing transcribes; an approved bookmark joins its existing work.
- [ ] **P6 · Mirror engine and unified library (L).** `work_editions`, `mirror_batches`, matching with Undo and Unlink, per-library choice, the preview, throttled push, undo of a run, chips, card glyphs, the Continue row, per-account everything. Built on ABS first. Acceptance: a book on two sources is one card; a re-run creates nothing new; undo removes only untouched works; a 2,000-item fake library mirrors without exceeding two concurrent creates.
- [ ] **P7 · Grimmory (M).** Sign in, library, resumable download where ranges exist, bookmarks CRUD, contract tests pinned to the tag, its mirror. Acceptance: a fake Grimmory book downloads and its bookmarks round-trip.
- [ ] **P8 · Jellyfin (M).** Library read, incremental sync, id-diff for removals, Watch buttons, mirror of movies and shows. Acceptance: a fake Jellyfin mirrors as `film` and `show` works with no provider ids sent on create; Watch opens the browser URL with the right ids.
- [ ] **P9 · Hardening and release (M).** Battery prompt, notification denial, backup rules, TalkBack, Bengali strings, `UI-Glossary`, changelog, ADRs, `Developing` file map, `Troubleshooting` rows for each new code, the owner-run checklist, release notes. Behind a "Listening (preview)" switch until the owner-run items pass.
- [ ] **App fix, not part of the build (S):** replace the stale comment in `lib/sync/push_sync.dart` ("accepts only `manual` and `ocr`") and make dictated quotes send `source: voice` (the server accepts it; the capabilities list `voice-source`), with a test.
- [ ] **Not in this plan:** reading EPUBs, Play Store, iOS, podcasts, Jellyfin playback, downloads and watch progress, Grimmory progress sync, physical-button bookmarks, OPDS, KOReader and Kobo sync.

## Decisions

New ADRs at build time (numbers taken then, after the last in `ADR-Index.md`; 0035 onward at the pin): sources and their sign-in; native service owns playback, tokens and media state; the work holds editions and sources mirror into the library; progress, its playback clock and the banner-not-stop conflict rule; Whisper on the phone, its separate process and its gates; bookmarks reach the library through the imports queue by a uniquely named file; event-only retries.

## Open questions for the owner

| # | Question | Recommended | Cost of the other |
|---|---|---|---|
| D-J | Which Watch button is the default for a Jellyfin title: open in the browser, or open the Jellyfin app | Browser (lands on the item) with the app as the second button | The app opens on its home screen, one search away |
| D-E | Mirror only whole shows, or seasons and episodes too | Whole shows | Thousands more works; episode-level quotes need the show's own season and episode fields anyway |
| D-C | Upload mirrored covers to the Tippani server | No; keep them on the phone | Server cover storage grows and every creation does an image POST |
| D-I | Store Jellyfin's imdb, tmdb and tvdb ids on the server's movie rows after creation | Yes, as an optional second step | The server's duplicate detection by id and later source re-sync have nothing to match |
| D-P | A queued bookmark quote gets source `md` (provenance only in a tag and note); direct creation would keep `voice` but skip the queue | Queue (as asked) | Provenance is less precise |
| D-W | Is a 90 s + 30 s default window the context you meant | Yes | Too much text per bookmark, or too little |

See also: [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md) · [ADR index](ADR-Index.md)
