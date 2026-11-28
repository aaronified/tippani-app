# lib/listen/abs

Talking to one Audiobookshelf server, as one signed-in user. Pure Dart, no Flutter, so every file here is tested without a device.

- `abs_client.dart`: `AbsClient`. Checks an address (`/status`), signs in with a password or finishes a browser sign-in, keeps the token pair fresh, and asks for libraries, books, progress, play sessions and bookmarks. Refresh tokens rotate, so only one refresh runs at a time and every waiting call shares it. An expired access token is refreshed once and the call repeated. Failures are an `AbsFailure`; the words for the reader are chosen where they are shown.
- `abs_models.dart`: the small, forgiving shapes (`AbsStatus`, `AbsTokens`, `AbsBook`, `AbsBookDetail`, `AbsPlaySession`, `AbsBookmark`, `AbsMe`, ...). A missing or null field becomes an empty value. Read from the owner's server, 2.37.2.
- `pkce.dart`: the PKCE verifier, challenge and `state` for the browser sign-in.

Things the code relies on, measured on the owner's server: ABS answers many writes with a bare `OK` (not JSON); a bookmark is keyed by its whole second, so two in one second are one; a track streams with an `Authorization: Bearer` header and a `Range` header, with no token in the address; failed logins share one bucket for every client, so a login is never retried in a loop.

Tests: `test/listen/`, using the in-memory server in `test/support/fake_abs.dart`.
