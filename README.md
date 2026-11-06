# Tippani for Android

A native Android client for [Tippani](https://github.com/aaronified/tippani), a self-hosted home for book highlights, film and show
dialogue, and quotes from anywhere. This app talks to **your own** Tippani server; it has no server of its own and no account with
anyone else.

**Status: scaffold and base only.** The app opens, lets you enter your server's address, asks it what it is (`GET /capabilities`) and
says whether this app and that server can talk. It also has what every later screen stands on: a check for a newer version of itself
on open (a message offers the download), what changed after an update, a log, and backup and restore of its settings. It cannot pair,
capture or show quotes yet, and there is no release. See
[docs/PLAN.md](docs/PLAN.md) for what comes next, what it reuses, how it will be signed and released, and what is still undecided, and
[docs/DEVELOPING.md](docs/DEVELOPING.md) to build it.

- **Android only.** No `ios/` directory will ship ([ADR-0001](docs/ADR-0001-android-only.md)).
- **Flutter**, with the Dart kept platform-neutral.
- **Pairing, not passwords.** The app scans a QR code from Tippani's Settings and holds a device token, which the server can revoke.
- **Server work the app needs** is filed as issues on [Tippani](https://github.com/aaronified/tippani/issues); this repository's
  issues are the app's.

## Licence

[GPL-3.0](LICENSE). Tippani itself is MIT.
