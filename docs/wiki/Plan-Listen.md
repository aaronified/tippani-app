# Plan: listen to Audiobookshelf, keep Grimmory books, bookmark by voice

**Status:** plan only, nothing built. First written 27 November 2026 at `9e986ca`; revised the same day after a source-level check of Audiobookshelf, Media3 and Whisper and an adversarial review. Code citations are verified at `90606c9`.
Mockups: `docs/design/listen-mockups.html` in the repository (the wiki is published flat, so it is named here and not linked).

## What the owner asked for

1. Listen to Audiobookshelf (ABS) books, with a working Android Auto player and audio cached offline.
2. Bookmark easily while driving. A bookmark carries a transcript of the surrounding audio, made by Whisper on the phone.
3. Connect to a Grimmory instance, download books and sync bookmarks. Reading an EPUB comes later.
4. Everything signs in through Authelia (OIDC). Authelia, ABS and Grimmory are all self-hosted by the owner, at their latest versions, reached over Twingate.
5. Whisper also transcribes dictated quotes.
6. Every setting is per user. Done first, in `5a18e09` and `90606c9` ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md)).
7. One library, or several, with up to three aspects per work. See [Navigation](#navigation-and-the-library).

## Rulings already made

| Question | Answer (owner, 27 November 2026) |
|---|---|
| How Authelia protects ABS and Grimmory | Both are OIDC clients of Authelia |
| Where traffic goes | Phone talks to ABS and Grimmory directly; the Tippani server only receives quotes |
| "Transcribed context" | Whisper transcribes the book audio around the bookmark |
| Install route | Sideload; Android Auto "Unknown sources" switched on once |
| Where a bookmark is saved | An ABS bookmark and a Tippani quote |
| Whisper model | English base by default; small and multilingual as options |
| Offline policy | Download whole books on demand, plus a rolling buffer ahead of the playing book |
| Grimmory transport | Native REST API |
| Bookmark triggers | Android Auto button, phone notification action, widget, in-app button. No physical button |
| Network | Twingate, as for Tippani |
| Versions | Latest of both |
| When Whisper runs | After a bookmark (an idle job) and while dictating a quote |

## What is verified and what is not

**V** read in primary source this session (the URL is the evidence); **I** inference from source; **U** not yet verified. Task T0 closes every U.

| Fact | Level | Evidence |
|---|---|---|
| ABS latest is v2.38.0 | V | `raw.githubusercontent.com/advplyr/audiobookshelf/master/package.json` |
| ABS login: `POST /login` `{username,password}`; header `x-return-tokens: true` returns `user.accessToken` and `user.refreshToken` in the body (no cookie) | V | `server/Auth.js` |
| ABS refresh: `POST /auth/refresh` with header `x-refresh-token`; the refresh token **rotates** on every call, the old one stays valid for 10 minutes (`REFRESH_TOKEN_GRACE_PERIOD`) | V | `server/Auth.js`, `server/auth/TokenManager.js` |
| ABS lifetimes: access 1 h, refresh 30 d (env overridable) | V | `TokenManager.js` |
| ABS `GET /status` returns `serverVersion` and `authMethods` (`local`, `openid`) | V | `server/Server.js` |
| ABS OIDC for apps: `GET /auth/openid?response_type=code&redirect_uri=…&code_challenge=…[&state=…]` (S256 only, PKCE required) answers 302 to the IdP; the IdP returns to `{abs}/auth/openid/mobile-redirect`, which 302s to the app's `redirect_uri?code&state`; the app then calls `GET /auth/openid/callback?code&state&code_verifier` **with the session cookie from the first call** and receives the login payload with tokens in the body | V | `Auth.js`, `server/auth/OidcAuthStrategy.js` |
| ABS "Allowed Mobile Redirect URIs": exact string match, or the single entry `*`; each entry must match `^\w+://[\w\.-]+(/[\w\./-]*)*$`; a non-matching update is silently ignored; default `audiobookshelf://oauth` | V | `OidcAuthStrategy.js`, `MiscController.js` |
| ABS bookmarks: `POST /api/me/item/:id/bookmark` `{time (seconds), title}`; upsert by `time`; no title length limit; `PATCH` same body; `DELETE …/bookmark/:time`; bookmarks are also inside the user object and `GET /api/me/bookmarks` | V | `server/controllers/MeController.js` |
| ABS play: `POST /api/items/:id/play` with `deviceInfo`, `supportedMimeTypes`, `forceDirectPlay`; response has `id`, `audioTracks[]` (`contentUrl`, `startOffset`, `duration`, `mimeType`), `chapters[]`, `startTime` | V | `LibraryItemController.js`, `PlaybackSession.js` |
| ABS audio: direct play `GET /api/items/:id/file/:ino`, Bearer or `?token=`, Range honoured (`res.sendFile`); `…/download` routes need the user's download permission; the folder zip route is streamed with no Range | V | `LibraryItemController.js` |
| ABS covers `GET /api/items/:id/cover` need no token | V | `Auth.js` ignore patterns |
| ABS progress: `POST /api/session/:id/sync` `{currentTime,timeListened,duration}`; `…/close`; offline: `POST /api/session/local-all` `{sessions:[…]}`, applied only if the session's `updatedAt` is not older than the stored progress (`progressSynced:false` otherwise); `PATCH /api/me/progress/:libraryItemId` | V | `SessionController.js`, `PlaybackSessionManager.js`, `MeController.js` |
| ABS rate limit: 40 failed `/login` attempts per 10 minutes in **one global bucket**; refresh and OIDC routes unlimited | V | `server/utils/rateLimiterFactory.js` |
| ABS builds OIDC redirects from the `Host` header and `x-forwarded-proto`; no `trust proxy` | V | `server/utils/requestUtils.js` |
| Media3: a custom `AudioProcessor` runs before speed adjustment and sees 1x PCM; on the normal path it receives 16-bit PCM at the codec's native rate and channel count; float output, offload and tunneling bypass processors; a seek flushes processors | V | `androidx/media` `DefaultAudioSink.java` (`release` branch), lines cited in S2 |
| Media3 custom buttons: `setMediaButtonPreferences`; slots CENTRAL, BACK, FORWARD hold one each, BACK_SECONDARY and FORWARD_SECONDARY hold none by default, OVERFLOW is unlimited; custom buttons default to OVERFLOW | V | `CommandButton.java`, `MediaSession.java` |
| How many custom actions an Android Auto head unit draws | U | Not in Media3 source or the pages read; spike S3 |
| Android Auto needs `automotive_app_desc`, a media service, 4 root tabs, no autoplay, `mediaPlayback` foreground type; sideloaded media apps show after "Unknown sources" | V | developer.android.com pages cited in the earlier research |
| `whisper_ggml` 2.10.0 needs the `ffmpeg_kit` plugin to convert audio, accepts only 16 kHz 16-bit WAV paths, downloads models into memory with no resume, builds baseline armv8-a only (no fp16) | V | pub.dev archive, `lib/src/whisper.dart`, `android/build.gradle` |
| whisper.cpp's Android example wraps 11 JNI calls and takes a `FloatArray` of 16 kHz mono PCM; it hardcodes `language="en"` and has no abort or progress hook; it loads an fp16 build on arm64 when `/proc/cpuinfo` has `fphp` | V | `examples/whisper.android` |
| whisper.cpp is MIT; ggml weights: base 148 MB, base q5_1 60 MB, small 488 MB, small q5_1 190 MB | V | whisper.cpp README, Hugging Face listing |
| Whisper speed on the owner's phone; peak memory | U | spike S1 |
| Grimmory REST: login, refresh, OIDC mobile (`GET /api/v1/auth/oidc/state`, `POST /api/v1/auth/oidc/mobile/callback`), libraries, books page, streamed download, bookmarks CRUD, annotations CRUD, progress POST | V | `grimmory-tools/grimmory` `develop` controllers, **not a release tag** |
| Grimmory progress body, GET for progress, download ranges, OpenAPI schema | U | `/api/openapi.json` with `API_DOCS_ENABLED=true` |
| Authelia (read from `authelia/authelia` **master**, which may be newer than the owner's release): `public: true` clients have no secret and PKCE is enforced for them by default; redirect URIs match **exactly** and may use a custom scheme (`tippani://oauth/abs` validates; a non-reverse-domain scheme only draws a warning); no wildcard redirects | V | `internal/configuration/validator/identity_providers.go`, `internal/configuration/config.template.yml`, `oauth2-provider/uri.go` |
| Authelia default token lifetimes: access 1 h, ID 1 h, **refresh 90 minutes**, authorize code 1 minute; refresh tokens rotate on every use with a **zero** grace period and a reused token revokes the whole grant; a refresh needs `offline_access` and `grant_types: [authorization_code, refresh_token]` | V | `schema/identity_providers.go`, `flow_refresh.go`, `internal/oidc/config.go` |
| Authelia consent defaults to `auto`: remembered for 7 days when a duration is set, otherwise asked each sign-in; session cookie defaults 5 min inactivity, 1 h expiry, 30 d with "remember me" | V | `config.template.yml`, `schema/session.go` |
| Authelia supports the device authorization grant (RFC 8628) on master; the release it arrived in is not found | V / U | `server/handlers.go`; not used by this plan |
| Authelia documentation pages (client guides for ABS and Grimmory) | U | docs host unreachable; the plan relies on the services' own source instead |
| The owner's Authelia release and its discovery document | U | T0 reads `/.well-known/openid-configuration` from the owner's instance |
| Tippani server accepts only `manual` and `ocr` as a quote source | V | `docs/wiki/Plan.md` ("The server only accepts `manual` and `ocr`") |

## What already exists in the app

Verified at `90606c9`. Re-verify with T0.

| Piece | Where | State |
|---|---|---|
| `Work` with `kind`, `creator`, `cover`, `details` (status, progress) | `lib/library/models.dart:16` `class Work`; `:3` `enum WorkKind { book, film, show, game, other }` | Built; no audiobook or book-file notion |
| Local SQLite library, schema 7 | `lib/library/library_store.dart:193` `static const schemaVersion = 7` | Built; the next migration adds editions (number taken at build time) |
| A work's list row | `lib/screens/library_widgets.dart:339` `class WorkTile` | Built |
| Per-account preferences | `lib/settings/preference_scope.dart` `class PreferenceScope`, `PrefKeys` | Built; every new setting joins `PrefKeys` |
| Pairing; token in secure storage (a Dart plugin) | `lib/app_controller.dart:181` `Future<PairResult> pair(`; `lib/settings/settings_store.dart:1` `flutter_secure_storage` | Built; Tippani server only |
| Sync, once a day and on change | `lib/sync/auto_sync.dart:141` `Timer.periodic(checkEvery` | Built |
| Dictating a quote | `lib/capture/voice_listener.dart:1` `import 'package:speech_to_text/...'` | Built |
| `RECORD_AUDIO`, `INTERNET`; `usesCleartextTraffic="true"`; `singleTop`, `taskAffinity=""`, exported activity; no `allowBackup` or data-extraction rules; no `network_security_config` | `android/app/src/main/AndroidManifest.xml:4-6,15,21-23`; `res/xml` holds only `clip_paths.xml`, `ota_update_paths.xml` | Built; each matters below |
| Release signing | `android/app/build.gradle.kts:34-38` `signingConfig = signingConfigs.getByName("debug")` | Built; the release workflow's injected signing must be confirmed in T0 (the in-app updater and Android Auto rely on key continuity) |
| CI: format, analyze, test, debug APK | `.github/workflows/ci.yml` (`flutter build apk --debug`) | Built; no NDK build or Kotlin test step yet |
| Locales `en` and `bn`; every string a token with a test | `lib/l10n/l10n.dart:53` `LocaleChoice('bn', …)`; `test/l10n/tokens_test.dart` | Built; no Hindi locale |
| Media playback, downloads, OIDC for apps, Whisper, bookmarks | none | Missing |

**In flight at the pin:** not audited; the remote has many older feature branches and none was compared with this plan. T0 lists open branches and pull requests touching the cited paths and re-checks `CHANGELOG.md` and `ADR-Index.md` for numbers taken after `ADR-0034`.

## Architecture

```
 Phone
 ┌──────────────────────────────── Flutter (Dart) ───────────────────────────────┐
 │ Library · Work page · Player UI · Bookmarks · Settings → Libraries             │
 │ Browse clients (ABS libraries/items/series/search, Grimmory) · Editions        │
 │ Quote writer (the only writer of library.db)                                   │
 └───────────────▲──────────────────────────────────────────▲────────────────────┘
      MethodChannel / EventChannel                        sqflite
 ┌───────────────┴────────────────── Kotlin (native) ───────┴────────────────────┐
 │ ListenService : MediaLibraryService (ExoPlayer, tree, resumption, buffer)      │
 │ TokenVault (Keystore) · AbsClient (auth, play session, progress, bookmarks,     │
 │ downloads) · listen.db · PcmTap · DownloadWorker · WhisperJob (process :whisper)│
 └──────────────────▲──────────────────────────────▲─────────────────────────────┘
                    │ HTTPS via Twingate           │ HTTPS via Twingate
              Audiobookshelf                    Grimmory        (both sign in through Authelia)
                              Tippani server: quotes only, by the existing sync
```

**Division of labour.** Native Kotlin owns everything that must work with no UI: the player and browse tree, tokens and their refresh, the play session, progress, bookmarks, downloads, the PCM tap and Whisper. Dart owns everything a person looks at and searches: library lists, items, series, search, covers, editions and the single writer of `library.db`. Dart borrows an access token from native for its own browse calls.

**Why native owns playback.** Android Auto binds to the service while the phone is locked and no Flutter engine is running, and asks for the browse tree and for resumption at boot with no network. Whatever that needs sits in a native SQLite file, `listen.db`. Alternatives:

| Option | For | Against | Verdict |
|---|---|---|---|
| Kotlin Media3 service, native `listen.db` | Fits the Android Auto lifecycle; Media3, OkHttp and WorkManager are Apache-2.0 | Two databases; native code to own | **Chosen** |
| `audio_service` 0.18.19 + `just_audio` | Less native code | Legacy browse service; browse depth and custom actions unverified; needs the Dart engine | Fallback if S3 shows the native route too costly |
| Route through the Tippani Go server | One place for credentials | New backend, extra hop, breaks offline | Rejected by the owner |

### Token custody

| Rule | Why |
|---|---|
| ABS and Grimmory tokens live only in native `TokenVault`: an Android Keystore AES-GCM key wraps them in `listen.db` (`sources.secret`) | `flutter_secure_storage` is a Dart plugin; the service has no Dart when Android Auto binds |
| One refresh mutex per source in Kotlin. Dart asks `getAccessToken(source)` over the channel and never refreshes | Rotating refresh tokens (ABS rotates every call) race otherwise and sign the driver out |
| A rotated refresh token is written to the vault **before** it is used for anything else; a 401 on refresh retries once with the stored previous token inside ABS's 10-minute grace, then marks the source "sign in again" | A crash between receiving and saving a rotated token must not lose the session |
| Dart pushes `setActiveAccount(scope)` whenever the paired account changes ([ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md) scope `server|name`); native persists it and serves that account's sources when Dart is dead | The service must know whose library it is serving |
| Tokens, authorization codes, the PKCE verifier and the `Authorization` header are redacted from every log (`AppLog` and logcat) | Existing rule: the device token is never in a log |
| JVM test: two concurrent 401s cause exactly one refresh | Acceptance for the mutex |

**Credentials never leave the phone.** Nothing about ABS or Grimmory is sent to the Tippani server. A second phone signs in itself and re-links editions by matching.

**Works alone** ([ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md)): with no Tippani pairing, sources can still be added and used; the settings of the unpaired phone are the bare-key set. With no source the app behaves exactly as today.

### Background execution

| Job | Mechanism | Foreground type | Cancel / resume |
|---|---|---|---|
| Playback, browse, resumption | `ListenService` | `mediaPlayback` | Resume through `onPlaybackResumption`; Media3 leaves the foreground after 10 min paused |
| Rolling buffer | A coroutine inside `ListenService` while it plays | Already foreground | Stops with playback; files are written to `.part` and renamed on completion |
| Manual download | A foreground service started from the Download button | `dataSync` | User-started, so allowed on Android 12+; the Android 15 six-hour cap is met by resuming (`Range` from the `.part` length); one retry trigger per event (below) |
| Whisper after a bookmark | `WorkManager` one-time job with an initial delay of 30 s from the moment playback pauses or stops, `requiresBatteryNotLow`, run in a separate process `:whisper` | None (job under 10 minutes; windows are under 60 s) | Idempotent: the job re-runs from the saved audio window; cancelled when playback resumes |
| Dictating a quote | Foreground activity recording through `AudioRecord`, then the same Whisper code in `:whisper` | None | Cancel discards |
| Progress upload | In the service while playing; the local-session upload on events | Already foreground / event | Idempotent by session id |

The separate `:whisper` process caps Whisper's memory (about 388 MB for base, 852 MB for small) so an out-of-memory kill cannot take the player down. Whisper never runs while a book is playing. A job is refused above a thermal-status threshold. S1 measures peak memory and the cost of cancelling mid-run.

**Retry rules** ([ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md) forbids retry timers). Every retry is triggered by an event: the app opening, the network returning, playback starting, the next bookmark, or the reader's own press. No backoff ladder; WorkManager's default backoff is disabled by making each job a single attempt per trigger. The playback progress clock (below) runs only while audio plays.

**OEM battery managers.** First run offers the system battery-exemption prompt with a sentence saying why; S1 and S3 are run on the owner's actual phone; if the service is killed the next open says so in one line.

**Notifications.** `POST_NOTIFICATIONS` is requested on first play (Android 13+). If denied, playback and Android Auto still work (the foreground service runs; Android may hide its notification) and Settings says what is hidden.

## Sign in

### Audiobookshelf (V)

The app learns the methods from `GET /status` (`authMethods`, `serverVersion`). With `openid` present:

1. The app generates a PKCE verifier and S256 challenge, a `state` and persists all three (native vault, keyed by `state`).
2. The app itself calls `GET {abs}/auth/openid?response_type=code&redirect_uri=tippani%3A%2F%2Foauth%2Fabs&code_challenge=…&code_challenge_method=S256&state=…` **without following redirects**, keeps the `Set-Cookie` session and reads the `Location` header (the IdP URL).
3. It opens that `Location` in the system browser. The owner signs in to Authelia (password and second factor, or an existing Authelia session).
4. Authelia returns to `{abs}/auth/openid/mobile-redirect`, which 302s to `tippani://oauth/abs?code=…&state=…`.
5. An Android intent filter for the `tippani` scheme hands the URL to the app. The app **accepts it only while a flow is pending and only if `state` matches**; anything else is dropped.
6. The app calls `GET {abs}/auth/openid/callback?code=…&state=…&code_verifier=…` with the saved session cookie and receives the login payload: `user.accessToken` and `user.refreshToken` in the body. Both go to the vault.
7. A username and password login stays available (`POST /login` with `x-return-tokens: true`), used only where OIDC is off. It is never retried in a loop: the global login limiter is 40 failures per 10 minutes for **all** clients.

**Owner actions before first sign in.**
1. ABS Settings > Authentication > "Allowed Mobile Redirect URIs": add `tippani://oauth/abs` (matches the server's pattern; exact match, no wildcard unless the single entry `*`).
2. Authelia: the ABS client's redirect URIs include `https://{abs}/auth/openid/callback` and `https://{abs}/auth/openid/mobile-redirect` (the second is the one the app flow uses). No scheme of ours is registered in Authelia for ABS.
3. ABS must be reached with a correct `Host` and `X-Forwarded-Proto: https` at the proxy, or the redirect it builds is wrong.

### Grimmory (V from `develop`; pin the release tag in T0)

1. The app calls `GET /api/v1/auth/oidc/state` and persists the returned state, a PKCE verifier and a nonce.
2. It opens Authelia's authorize URL (issuer and client id from the server's public settings, **U** payload) in the browser with `redirect_uri=tippani://oauth/grimmory`.
3. It receives the code at the intent filter (same pending-flow and `state` checks) and calls `POST /api/v1/auth/oidc/mobile/callback` with `code`, `code_verifier`, `redirect_uri`, `nonce`, `state`. Grimmory exchanges the code itself and returns its own access and refresh tokens.

**Owner actions.**
1. Grimmory: add `tippani://oauth/grimmory` to `oidcRedirectUris` (non-http scheme, no fragment).
2. Authelia, Grimmory's client: add `tippani://oauth/grimmory` to `redirect_uris` (exact match; this client's authorize request names it). The client is `public: true` with no secret, `require_pkce: true`, `pkce_challenge_method: S256`, and scopes that include what Grimmory requests. Authelia accepts a custom scheme and only warns that a reverse-domain scheme is preferred; the scheme stays `tippani` because ABS's validator accepts only `\w+` schemes (letters, digits, underscore) and silently ignores an entry with dots.

### Shared rules

- **Return address safety.** Another app can claim the same scheme. The flow therefore carries PKCE, `state` and (Grimmory) `nonce`, accepts a callback only while a flow it started is pending, and stores the verifier in the vault so process death during the browser step does not lose it. A pending flow expires after 10 minutes.
- **Refresh and offline.** The app never holds Authelia tokens: each service exchanges the code with Authelia itself and issues its own. Authelia's 90-minute refresh lifetime and its zero-grace rotation therefore do not reach the phone; they matter only to the services' own sign-in. ABS access tokens last 1 h and a rotating 30-day refresh token is renewed on every use, so a phone that goes online at least monthly never signs in again. A refresh that fails with no network is not a sign-out. Only a refused refresh token while online marks the source "sign in again" (the browser flow, which asks Authelia again); downloaded books stay playable. Grimmory lifetimes are U (T0).
- **What a re-sign-in costs.** The browser step shows the Authelia login unless an Authelia session cookie is still valid (1 h by default, 30 days with "remember me"), and a consent screen unless the client's consent is remembered (7 days by default). The owner can lengthen either on the Authelia side; the app asks for neither.
- **Forward-auth must not guard the apps' API.** The plan assumes ABS and Grimmory do OIDC themselves, as the owner said. If the reverse proxy also applies Authelia forward-auth to their API paths, a native app gets Authelia's login page instead of JSON. On adding a source the app calls `GET {abs}/status` (or Grimmory's public settings) with no credentials and, if it receives HTML or a redirect to Authelia, says "this address is behind a login page; allow `/api`, `/auth`, `/login`, `/status`, `/hls` and `/socket.io` (ABS) or `/api` (Grimmory) through" instead of failing later.
- **TLS.** `usesCleartextTraffic="true"` is set app-wide (for the Tippani server's LAN use). Sources reuse `isRiskyCleartext` (`lib/settings/server_url.dart:38`) and **refuse to send a bearer token, an OIDC code or a password over `http://`**. A private certificate authority is not trusted by apps on Android 7+ unless a `network_security_config` allows the user store; whether the owner needs this is open question D-T.

## Audiobookshelf playback and sync (V)

| Need | Route (all under the server base; `Authorization: Bearer`) |
|---|---|
| Libraries, items, series, authors, search | Dart: `GET /api/libraries`, `/api/libraries/:id/items` (`limit`, `page`, `sort`, `minified=1`), `/api/items/:id?expanded=1&include=progress`, `/api/libraries/:id/series`, `/api/libraries/:id/search?q=`, `/api/libraries/:id/personalized` (continue listening) |
| Covers | `GET /api/items/:id/cover?width=…&format=webp&ts=…`; no token needed |
| Start | Kotlin: `POST /api/items/:id/play` with `forceDirectPlay: true` and `supportedMimeTypes`; if the answer says transcode (HLS), the app plays the `m3u8` as is |
| Stream a track | `GET {contentUrl}` = `/api/items/:id/file/:ino` with the header (Range works); never `?token=` in a URL, so no proxy log holds it |
| Keep the session | `POST /api/session/:id/sync` `{currentTime,timeListened,duration}` about every 15 s **while audio plays**; `POST …/close` on stop |
| Offline listening | Kotlin records a local session (UUID, `updatedAt` = last listened time) and uploads it with `POST /api/session/local-all` when ABS is next reached |
| Bookmark | `POST /api/me/item/:id/bookmark` `{time, title}`; the title has no length limit, so the transcript may go there in full, but a short excerpt is kept for readability |
| Download | `GET /api/items/:id/file/:ino` per audio file with `Range` from the `.part` length (the zip route is not resumable and is not used) |

**Behaviours the plan now fixes** (none was in the first draft):

- **Tracks and chapters.** A multi-file book is a playlist of tracks with `startOffset`; position = `startOffset` + track position, and it is what is sent as `currentTime`. Chapters come from ABS `chapters`; with none, the tree lists tracks, and a single-file book with no chapters gets none (no invented ones).
- **Podcast libraries are out of scope** for this plan; the app lists book libraries only.
- **Series order** follows ABS series sequence; authors and series are children in the Android Auto Library tab.
- **The Download button follows `user.permissions.download`** from the login payload; if the server withholds it the button is absent. Playback never needs it.
- **Audio focus** is handled by Media3 (`handleAudioFocus = true`): pause for a call, duck for navigation prompts, resume after. `setHandleAudioBecomingNoisy(true)` pauses when Bluetooth or headphones disconnect.
- **Headset and steering-wheel media buttons** keep their standard meaning (play, pause, next, previous) through Media3's defaults. Only a *bookmark* press from a physical button is not offered.
- **Smart rewind:** after a pause longer than five minutes, resume 10 s earlier; longer pauses rewind more, capped at 30 s (settings).
- **Positions are seconds in the whole book** everywhere (ABS `time`, `currentTime`), converted to a track and offset only at the player.
- **Conflict rule, deterministic and driver-safe.** ABS already applies the rule: an offline session's progress is applied only if its `updatedAt` is not older than the stored progress. The app adds no prompt that blocks resumption. Android Auto and `onPlaybackResumption` resume the **local** position. On the phone, when ABS holds a newer position from another device, a banner offers "Jump to 55:00 from Pixel" ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md): chosen per item; [ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md): never stops for a conflict. This is a banner, not a stop. Record that in the new ADR).
- **Playback progress clock.** The 15-second sync exists only while audio plays and stops with it. It is not a retry or idle timer and is recorded as such in the new ADR.

## Android Auto

- Manifest: `automotive_app_desc` (`uses name="media"`), Media3 intent filters, `foregroundServiceType="mediaPlayback"`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`.
- **No autoplay on connect** (the first state is paused). `onPlaybackResumption` restores the last item and position from `listen.db` using local data only.
- **Browse tree** (root tabs limited to 4, all browsable): **Continue** (in progress, most recent first), **Downloaded**, **Library** (ABS libraries, series, authors, items; depth limits U, S3), **Bookmarks** (recent bookmarks; a tap seeks). An item opens into its chapters. Search arrives as a query through `onGetSearchResult` and `onPlayFromSearch`.
- **Bookmark button.** `MediaSession.Builder.setMediaButtonPreferences([bookmark])` with the session command `BOOKMARK`, added for the Android Auto controller (`isAutoCompanionController`). By default Media3 places custom buttons in `SLOT_OVERFLOW`. The plan reserves skip slots so the button is as visible as the head unit allows; whether Android Auto shows it on the main row or one tap deeper is S3's gate. If it lands in an overflow menu the owner decides whether that is acceptable.
- **Feedback with no toast.** A press swaps the icon to a tick for two seconds and plays a short tone. A failed press (service not ready, nothing playing) swaps to a cross and a different tone; the bookmark exists in `listen.db` before either.
- **Driving safety.** Nothing on the car screen needs reading; transcription happens after the drive.

### Triggers

| Trigger | Surface |
|---|---|
| Bookmark button | Android Auto now-playing |
| Notification action | Phone lock screen and shade |
| Widget | Home screen (bookmark, play/pause) |
| In-app button | Player screen |
| Physical buttons | Not a bookmark source. They keep their playback meaning |

### Distribution

Sideloaded APK from GitHub releases. Android Auto lists it only after the owner enables developer mode (tap the version row ten times) and "Unknown sources". Play internal testing would need no setting; Plan.md keeps the Play Store out of scope, so no ADR reverses it. The release APK's signing must be checked in T0 (see "What already exists").

## Offline audio

| Mode | Behaviour | Stored |
|---|---|---|
| Download | A book's files in order, resumable, never evicted | `files/listen/{source}/{item}/` |
| Rolling buffer | Ahead N hours (default 3), behind M hours (default 1); written as `.part`, renamed when complete | Same folder, marked `buffer` |
| Stream | Anything not cached | ExoPlayer `SimpleCache`, 512 MB default |

Settings per account: Wi-Fi only (default on), storage ceiling (default 5 GB), buffer ahead and behind, delete after finishing. Eviction takes buffer files first, oldest played first. When storage is full a download stops with the reason and nothing partial is left as complete. A file is marked complete only if its length matches the item's reported size (`media.audioFiles[].metadata.size`).

## The bookmark pipeline

Idempotent state machine. Every bookmark has a UUID in `listen.db`.

```
pending → captured → transcribed → titled (ABS) → quoted
```

| Step | Owner | Rule |
|---|---|---|
| 1 pending | Kotlin | On press, write the row (item, position as float seconds, time, UUID) **before anything else**; swap the button icon. ABS accepts `time` as a number and upserts by `time`, so two presses in the same second share one bookmark; position keeps millisecond precision to avoid collisions |
| 2 captured | Kotlin | Copy the PCM window out of the tap (below) to `listen.db`'s job store as a 16 kHz mono float file; keep capturing for the after-window |
| 3 transcribed | `:whisper` | Whisper over the saved window; result text stored on the row; the audio file is deleted |
| 4 titled | Kotlin | `POST /api/me/item/:id/bookmark` (create at step 1 with a placeholder title, update here with the excerpt); retried on events only |
| 5 quoted | Dart | Native writes a "quote request" row (UUID, text, position, chapter, item) to an outbox in `listen.db`. Dart drains it when the app is alive and inserts the quote into `library.db` using the UUID as an idempotency key (a nullable `origin_ref` column in the next migration); a second drain inserts nothing |

- A failed step leaves the earlier ones intact. A failed quote write leaves "Quote not saved. Retry." on the bookmark; the bookmark never disappears.
- Acceptance: kill the process after each step and assert exactly one ABS bookmark and exactly one quote.
- **Decision D-Q:** this creates a quote for every bookmark. Recommended instead: the quote opens in a **Trim** step (select the sentence, discard, or keep all) before it is saved. The cost is one tap per bookmark.
- The quote's text is the transcript with whole-word edges (partial words at the window edges removed, marked `…`); its location is the time and chapter ("3:42:10 · Chapter 14"); its source is `manual` until the Tippani server accepts `voice` (server issue); a note "From a bookmark"; tag `bookmark`. It saves to the local library, so it works with no server and syncs by the ordinary push.
- **Transcripts are text of a copyrighted book.** They sit in the owner's own library and sync to the owner's own Tippani server like any quote. Each bookmark has "Delete transcript". Nothing is shared elsewhere.
- Bookmarks made in other ABS clients appear with no transcript and a "Transcribe" action that works on cached books.

### Capturing the audio: the PCM tap (V in source, proven in S2)

A custom `AudioProcessor` is installed by overriding `DefaultRenderersFactory.buildAudioSink` with `DefaultAudioSink.Builder.setAudioProcessors`. Verified in `DefaultAudioSink.java`: the order is trimming, channel mapping, to-16-bit, **custom processors**, silence skipping, Sonic (speed). So the tap sees audio at 1x speed.

Constraints written into the design:

- `configure()` accepts only `ENCODING_PCM_16BIT` and throws `UnhandledAudioFormatException` otherwise.
- The tap downmixes to mono and resamples to 16 kHz (a polyphase or linear resampler written for this), into a 90 s ring buffer (about 2.9 MB). `flush()` (a seek) clears it.
- **Float output must stay off, and offload and tunneling must not be enabled**, or the processor chain is bypassed. A JVM test asserts the sink is built that way.
- The tap sees audio slightly ahead of what is heard (the AudioTrack buffer). Mapping a press to a ring position uses the media time carried with each buffer (`StreamMetadata.positionOffsetUs` plus samples counted), not the wall clock.
- A press within 15 s of a pause truncates the after-window; the transcript simply ends there. Right after a seek the ring holds only audio since the seek.
- For downloaded books where the ring is short, a slice of the cached file (`MediaExtractor`/`MediaCodec`) is the fallback (design B) and is what "Transcribe" uses for bookmarks from other clients.

## Whisper on the phone

| Setting | Default | Options |
|---|---|---|
| Model | English base (`base.en`, q5_1, 60 MB) | base q8_0 (82 MB), base fp16 (148 MB), small q5_1 (190 MB), small fp16 (488 MB); multilingual variants |
| Language | English | Auto-detect or a chosen language |
| Window | 45 s before, 15 s after | 10 to 120 s |
| Run when | Idle (30 s after playback stops, or on charging, or when the app opens), battery not low | Also immediately when the app is open |

- **Binding: whisper.cpp built into the app through a small JNI of our own**, not `whisper_ggml`. Reasons from source: `whisper_ggml` needs the `ffmpeg_kit` plugin for audio conversion (an LGPL/GPL binary against [ADR-0002](ADR-0002-Licence-Is-GPL-3.0-And-Nothing-Proprietary.md)'s spirit and APK size), accepts only WAV paths, downloads models into memory with no resume, builds without fp16, and needs Flutter plugins to run from a background job. The whisper.cpp Android example takes a `FloatArray` of 16 kHz mono PCM, which is what the tap and the recorder produce, so no file or format code exists at all.
- **What we write:** extend the example's JNI with a language argument, an abort callback and a progress callback; select the fp16 library on arm64 when `/proc/cpuinfo` has `fphp`; build arm64-v8a (and x86_64 for the emulator) only; link with 16 KB page alignment (`-Wl,-z,max-page-size=16384`). whisper.cpp is vendored at a pinned tag (MIT).
- **Model downloads** use our own Kotlin downloader: `Range` resume, SHA-256 verified against the digest from the Hugging Face file listing (T0 records the digests), a Models screen with size and delete. Models are never in a backup and never bundled.
- **Dictating a quote.** Speak gets an engine choice per account: the phone's recogniser (today; may use Google online) or Whisper. Whisper records 16 kHz mono through `AudioRecord`, transcribes when you stop, and lands in the same correction screen. No streaming partials in this plan.
- **Languages.** The app has `en` and `bn` only. `base.en` cannot transcribe Bengali and small multilingual models transcribe it less well than English (inference, S1 measures it). Open question D-L: are the audiobooks English only?
- **Privacy.** Audio never leaves the phone.
- **Licences.** whisper.cpp MIT; weights Apache-2.0 (OpenAI) and MIT (the ggml repository), to be confirmed from the LICENSE files in T0.

## Grimmory

- **Sign in** as above. Tokens refresh through `POST /api/v1/auth/refresh`; the vault's mutex serves Grimmory too.
- **Library:** `GET /api/v1/libraries`, `/shelves`, `/books/page` with `sort`, `facet`, `query`, `cursor` (V). Covers via `/api/v1/media/book/{id}/cover` (auth form U).
- **Download:** `GET /api/v1/books/{id}/download`, streamed (V); multi-file books through `download-all`. Range support U; without it a download restarts from zero. Stored under `files/books/{source}/{id}/`.
- **Bookmarks:** `/api/v1/bookmarks` CRUD (V): `cfi` (EPUB), `pageNumber` (PDF), `positionMs` and `trackIndex` (audio), `title`, `notes`, `color`, `priority`. The app lists all of them and creates only audio ones until the reader exists; creating an EPUB bookmark needs a CFI, which needs a reader. State this on the screen.
- **Progress:** `POST /api/v1/books/progress` exists; the `BookFileProgress` body is U. Not built until the OpenAPI schema is read.
- **Stability:** `/api/v1` is a path prefix with no documented stability contract; the facts above are from `develop`. T0 pins the owner's release tag; the contract tests fail when the server's version differs from the pinned one until a person re-verifies.
- Other protocols (OPDS, KOReader sync, Kobo sync, Komga API) are not used.

## Navigation and the library

**Model (every option): the work is the unit, editions hang off it.** `Work` keeps `kind`. A `work_editions` table (next migration) holds zero or more editions per work: `{work_id, type: audio | file, source_id, remote_id, state, matched_by}`. "Quotes only" is a work with no edition, as a book is today.

| Option | Description |
|---|---|
| **A. One Library, editions on the work** | Chips: All, Listening, Reading, Quotes only, Downloaded. Cards show edition glyphs. A work page holds the edition strip. A mini-player sits above the bottom bar on every screen |
| B. Separate libraries | Three sections: Audiobooks, Books, Quotes. A book in two forms appears twice |
| C. A new Listen tab | A fifth bottom tab; Library unchanged |

Scores, 1 (poor) to 5 (best), unweighted:

| Criterion | A | B | C |
|---|---|---|---|
| One place per book | 5 | 2 | 2 |
| Taps from opening the app to resuming | 5 | 3 | 3 |
| Keeps the four tabs of [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md) uncrowded | 5 | 5 | 2 |
| Quotes stay with the work in every form | 5 | 3 | 3 |
| Clear what a book with no edition is | 4 | 3 | 3 |
| Build cost (higher is cheaper) | 3 | 4 | 3 |
| **Total** | **27** | **20** | **16** |

**Recommendation: A.** Primary downside: edition matching can be wrong.

- **Matching:** by ISBN or ASIN first, then normalised title and creator. Below a confidence threshold the app asks "Link this book?" with both covers side by side. Every link has Undo and Unlink. Nothing merges silently.
- **Settings > Libraries** holds ABS, Grimmory, Whisper and Downloads (all per account). The Server tab stays the Tippani server.
- **Home** gets a Continue listening row when a source exists.
- **Open question D-A:** whether the first play or bookmark of an ABS-only book creates a Tippani work (recommended: yes) or needs an explicit "Add to library".

## Data, backup and lifecycle

**`library.db`** (Dart, next migration; schema 7 at the pin): `work_editions(work_id, type, source_id, remote_id, state, matched_by)`; a nullable `origin_ref` on quotes.

**`listen.db`** (native): `meta(active_scope)`, `sources(id, type, url, account_scope, secret)`, `items`, `tracks`, `chapters`, `progress(item, position_ms, device, updated_at, synced)`, `bookmarks(uuid, item, position_s, state, transcript, abs_synced)`, `quote_outbox(uuid, …)`, `jobs`.

**Android's own backup.** The manifest has no `allowBackup` or data-extraction rules, so the platform copies app data to a new phone by default. The plan adds `dataExtractionRules` and `fullBackupContent` that **exclude** `listen.db`, `files/listen`, `files/books`, Whisper models and the Keystore-wrapped secrets, and leave everything else as it is.

**The app's own backup** (the harness backup, [ADR-0009](ADR-0009-A-Backup-Is-Checked-Whole-Before-Any-Of-It-Is-Written.md)) carries `work_editions` and, as text, bookmarks and transcripts; never tokens, downloads, models or the stream cache. After a restore the editions point at sources that may not exist: they show "Source not signed in" with a Sign in action, and nothing is deleted. Restore of `listen.db` is done by the service while stopped. T0 checks `lib/harness/backup.dart` for size limits before transcripts are added to the file.

| Event | Tokens | Downloads and models | Bookmarks and transcripts | In-flight jobs |
|---|---|---|---|---|
| Unpair the Tippani server | Kept; sources are the phone's, as with the unpaired preference set | Kept | Kept | Continue |
| Sign out of a source | Deleted | Kept, still playable | Kept | Cancelled |
| Remove a source | Deleted | Deleted after a confirmation naming the size | Kept as text | Cancelled |
| Switch to another Tippani account | Hidden (a different scope) | Hidden, kept on disk | Hidden | Paused |
| Delete a work | Edition links deleted, files asked about | Asked | Kept until the work's quotes are | Cancelled |

**Unlinking an edition** never deletes files or bookmarks; it only detaches them from the work.

## Network and offline behaviour

| State | Browse | Play | Download | Bookmark | Transcribe |
|---|---|---|---|---|---|
| Online | live | stream or cache | runs | instant | idle job |
| No Twingate | last copy, dated | cached only | waits | instant | idle job |
| Source refused the refresh | last copy | cached only | stops, says why | instant | idle job |

The broken-link mark and once-per-awake toast of [ADR-0033](ADR-0033-The-Broken-Link-Is-One-Mark-And-One-Toast.md) cover the Tippani server and the sources together.

## Settings (per account, [ADR-0034](ADR-0034-The-Apps-Own-Preferences-Belong-To-The-Account-It-Is-Paired-As.md))

Added to `PrefKeys`: skip back and forward seconds, default speed, sleep timer choices, smart rewind, Wi-Fi only, storage ceiling, buffer ahead and behind, delete after finishing, bookmark window, Whisper model, language and run-when, speech engine. Source credentials and downloaded files are per account too.

## Quality, strings and the gate

- **Every string is a token** with English and Bengali (`test/l10n/tokens_test.dart`, `dart run tool/gen_l10n.dart`). Android Auto tab names, notification, widget and custom-button labels are native strings and need `res/values-bn`.
- **Icons.** New headphones, book and bookmark glyphs are added to the generated Tabler set. The notification, widget and Android Auto icons must be Android vector drawables, outside Tabler; record that exception in the ADR on [ADR-0005](ADR-0005-Material-You-Only.md).
- **Accessibility.** TalkBack labels for the player, the bookmark button and edition glyphs; the Android Auto tick has a spoken confirmation.
- **Tests use the app.** Dart: widget tests against `test/support/memory_library.dart` and new fakes `fake_abs.dart` and `fake_grimmory.dart` that answer the routes marked V above. Contract tests pin each route's shape. Kotlin JVM tests that must read internals (the ring buffer, eviction, the tree builder) name that as a declared exception in the file header, as the repo's rule requires; whatever can be driven through the service's observable surface is.
- **Mutation:** each journey is run with its decisive action deleted and must fail, named in the commit.
- **CI:** add a Kotlin unit-test step and an NDK build to `ci.yml`; measure the added build time and APK size (arm64 only).
- **Dependencies to licence-check (ADR-0002):** OkHttp, WorkManager, Media3 (Apache-2.0), whisper.cpp (MIT), any PKCE hash helper.
- **The cloud container** can run Dart analyze and tests and, with the Android SDK added, a debug build. It cannot run Android Auto, a head unit, Whisper on your phone, or a sign-in through your Authelia. Those are listed as owner-run items.

## Tasks

Order puts the owner's primary ask, Android Auto, first among the spikes. Sizes: S under a day, M a few days, L about a week or more. A task is not done until its acceptance passes and its mutation check was run.

- [ ] **T0 · Re-verify and read the rest (S).**
  ```bash
  git diff --stat 90606c9..HEAD -- lib/library/models.dart lib/library/library_store.dart lib/screens/library_widgets.dart lib/app_controller.dart lib/settings lib/capture/voice_listener.dart android/app/src/main android/app/build.gradle.kts
  git log --oneline 90606c9..HEAD -- docs/wiki/ADR-Index.md CHANGELOG.md
  git grep -n "schemaVersion = " HEAD -- lib/library/library_store.dart
  git grep -n "class Work\b" HEAD -- lib/library/models.dart
  ```
  Then: ABS version from the owner's `GET /status` against v2.38.0 (re-read changed routes); Grimmory release tag and `/api/openapi.json` (progress body, download ranges, public settings); the owner's Authelia release and `/.well-known/openid-configuration` (issuer, supported grants, scopes, whether `offline_access` and public clients are configured the way the two services need); Hugging Face model digests; `lib/harness/backup.dart` size limits; Flutter's `minSdkVersion`; the release workflow's signing; open branches and pull requests on the cited paths. Correct every U above.
- [ ] **S3 · Android Auto spike (M, owner-run on a head unit or the Desktop Head Unit).** Media3 service, four-tab tree, `BOOKMARK` command in `setMediaButtonPreferences`, resumption. Gate: no autoplay; the button is visible and where it lands is recorded; the tree answers with the phone locked and the app dead. Failing that, decide the `audio_service` fallback.
- [ ] **S2 · PCM tap spike (M).** Tap in ExoPlayer; sink built with float output, offload and tunneling off; mapping from press to ring position; behaviour after seek; ABS direct play of an m4b and an mp3. Gate: a transcript from the tap equals one from the cached file for the same passage.
- [ ] **S1 · Whisper spike (M, owner-run).** whisper.cpp JNI in `:whisper`, base.en q5_1 and q8_0, a 60 s window on the owner's phone: time, peak memory, cancellation, thermal behaviour, an English and a Bengali sample. Gate: under 90 s on battery with the player process unharmed.
- [ ] **P1 · Sources and sign in (L).** Settings > Libraries, `TokenVault`, the ABS and Grimmory flows above, the intent filter with pending-flow and `state` checks, sign-out, "sign in again". Acceptance: a fake ABS and fake Grimmory sign in, survive a restart and a killed process mid-flow, expose nothing to another account; the mutex test passes; no token appears in `AppLog`.
- [ ] **P2 · Native service, ABS browse and stream playback (L).** `ListenService`, player, chapters, speed, sleep timer, mini-player, Now Playing, the Android Auto tree and button from S3. Acceptance: a fake ABS item plays; position survives a restart; the JVM tree test; an owner DHU checklist.
- [ ] **P3 · Offline (L).** Downloads screen, resumable `.part` files, rolling buffer in the service, eviction, ceiling, storage-full. Acceptance: airplane-mode playback of a downloaded book; the buffer follows the playing chapter; a killed download resumes.
- [ ] **P4 · Progress (M).** Session sync while playing, local session upload by event, the banner for a newer position elsewhere. Acceptance: offline listening uploads once; an older local session leaves newer server progress alone (`progressSynced:false`).
- [ ] **P5 · Bookmarks and Whisper (L).** The state machine, the tap, `:whisper` job, ABS bookmark, the quote outbox and its Dart drain, the Trim step if D-Q says so, the Models screen, the dictated-quote engine, the `voice` server issue. Acceptance: killing the process after each step yields exactly one bookmark and one quote.
- [ ] **P6 · Grimmory (M).** Sign in, library, resumable download where ranges exist, bookmarks CRUD, contract tests pinned to the tag; progress only after T0 reads its schema. Acceptance: a fake Grimmory book downloads and its bookmarks round-trip.
- [ ] **P7 · Unified library (M).** `work_editions`, matching and linking with Undo, chips, card glyphs, the Continue row, per-account everything. Acceptance: a book on both services is one card; unlinking changes no file.
- [ ] **P8 · Hardening and release (M).** Battery prompt, notification denial, backup rules, network security config if D-T needs it, TalkBack, Bengali strings, `UI-Glossary`, changelog, ADRs, `Developing` file map, `Troubleshooting` rows for each new code, release notes with the owner-run checklist. Behind a "Listening (preview)" switch in Settings until the owner-run items pass, so a bad build can be hidden without a release.
- [ ] **Server issue on `aaronified/tippani`:** accept `voice` as a quote source (until then `manual`).
- [ ] **Not in this plan:** reading EPUBs, Play Store, iOS, podcasts, volume-key and physical-button bookmarks, OPDS, KOReader and Kobo sync.

## Decisions

New ADRs at build time (numbers taken then, after the last in `ADR-Index.md`; 0035 onward at the pin): sources and their sign-in; native service owns playback, tokens and media state; the work holds editions; progress, its playback clock and the banner-not-stop conflict rule; Whisper on the phone, its separate process and when it runs; bookmarks become quotes by an idempotent outbox; event-only retries.

## Open questions for the owner

| # | Question | Recommended | Cost of the other |
|---|---|---|---|
| D-Q | Does every bookmark become a quote at once, or open a Trim step first | Trim | A library filling with raw transcripts |
| D-A | Does the first play of an ABS book add it to the library | Yes | An extra tap per book |
| D-S | Is 45 s before and 15 s after right | Yes, adjustable | Cut sentences |
| D-L | Are all your audiobooks English | If yes, `base.en` only | A larger multilingual model and weaker Bengali |
| D-T | Are the ABS, Grimmory and Authelia URLs HTTPS with a public certificate, a private certificate authority, or HTTP | HTTPS | A private authority needs a network security config and a note on installing the certificate |
| D-M | Lowest Android version you need | Whatever Flutter's default allows | Notification-permission and foreground rules differ by version |
| D-G | Grimmory `/api/openapi.json` (`API_DOCS_ENABLED=true`) | Send it | Progress sync stays unplanned |

See also: [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md) · [ADR index](ADR-Index.md)
