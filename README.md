# Tippani for Android

A native Android client for [Tippani](https://github.com/aaronified/tippani), a self-hosted home for book highlights, film and show
dialogue, and quotes from anywhere. This app talks to **your own** Tippani server; it has no server of its own and no account with
anyone else.

**Status: not built.** This repository holds the plan and nothing else yet. There is no app code, no `android/` directory and no
release. See [docs/PLAN.md](docs/PLAN.md) for what the app will do, what it reuses, how it will be signed and released, and what is
still undecided.

- **Android only.** No `ios/` directory will ship ([ADR-0001](docs/ADR-0001-android-only.md)).
- **Flutter**, with the Dart kept platform-neutral.
- **Pairing, not passwords.** The app scans a QR code from Tippani's Settings and holds a device token, which the server can revoke.
- **Server work the app needs** is filed as issues on [Tippani](https://github.com/aaronified/tippani/issues); this repository's
  issues are the app's.

## Licence

[GPL-3.0](LICENSE). Tippani itself is MIT.
