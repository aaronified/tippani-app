# Tippani for Android

A native Android app for keeping quotes: book highlights, film and show dialogue, and lines from anywhere. It is built to **work on
its own, with no server**. If you also run [Tippani](https://github.com/aaronified/tippani), a self-hosted home for your quotes, the
app can pair with it and the two stay in step. The server is optional ([docs/wiki/Plan.md](docs/wiki/Plan.md), section 0).

**Status: early.** What exists today is the base every later screen stands on, and pairing:

- It asks a Tippani server what it is, says whether this app and that server can talk, and pairs with it using a code from the
  server's Settings > Server > Devices (typed; no password on the phone). Settings lists the paired devices and unpairs any of them.
- It checks for a newer version of itself when it opens, and a message offers the download.
- After an update it shows what changed.
- It keeps an app log, and an admin can read the server's own log separately.
- It backs up and restores its settings.

It cannot yet capture a page, keep a library of its own, or show quotes, and there is no release. The local library comes next, then
capture. See [docs/wiki/Plan.md](docs/wiki/Plan.md) for what the app will do, what it reuses, how it will be signed and released, and what is
still undecided, and [docs/wiki/Developing.md](docs/wiki/Developing.md) to build it. Every decision is on a page of its own, listed in
[docs/wiki/ADR-Index.md](docs/wiki/ADR-Index.md); how a release is cut is in [docs/wiki/Releasing.md](docs/wiki/Releasing.md).

- **Android only.** No `ios/` directory will ship ([ADR-0001](docs/wiki/ADR-0001-Android-Only.md)).
- **Flutter**, with the Dart kept platform-neutral.
- **Nothing proprietary.** Text recognition uses Tesseract (Apache-2.0), not Google's ML Kit. The English and Hindi language data in
  `assets/tessdata` is Tesseract's `tessdata_fast` (Apache-2.0).
- **Server work the app needs** is filed as issues on [Tippani](https://github.com/aaronified/tippani/issues); this repository's
  issues are the app's.

## Licence

[GPL-3.0](LICENSE). Tippani itself is MIT.
