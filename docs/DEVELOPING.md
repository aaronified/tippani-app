# Developing

## Build and test

You need Flutter (the version in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml); CI pins it) and the Android SDK.

```sh
flutter pub get
dart format lib test        # CI fails on unformatted code
flutter analyze
flutter test
flutter build apk --debug
```

`flutter test` needs no device and no network: the HTTP client is injected, and the tests give it a fake.

## Layout

| Path | What it is |
| --- | --- |
| `lib/main.dart` | Opens the stored settings and starts the app. |
| `lib/app.dart` | The theme (the phone's own colours where it has them, Tippani's red where it does not) and the bottom bar. A later phase adds its screen there. |
| `lib/app_controller.dart` | The state more than one screen needs: which server, and whether it answered and is compatible. |
| `lib/api/capabilities.dart` | The version handshake: the revision this build was written for, and the oldest server it accepts. |
| `lib/api/api_client.dart` | The one way the app speaks to a server: Bearer token, timeouts, and typed failures (network, timeout, unauthorised, server, bad response). |
| `lib/settings/server_url.dart` | Turns what a reader types into the address the app keeps, and says when plain `http` would send a credential across the internet. |
| `lib/settings/settings_store.dart` | The server address in preferences; the device token in secure storage and nowhere else. |
| `lib/screens/` | Home, Settings, and the connect screen. |
| `test/` | One file per unit above, and `connect_flow_test.dart` for the screens. |

## Decisions made in the scaffold

- **Package id** `io.github.aaronified.tippani`, as the plan suggested.
- **Cleartext http is allowed** (`android:usesCleartextTraffic`), because a self-hosted server on the home network is usually plain
  http and Android blocks it by default. The connect screen warns before it keeps an http address that is not on a private network.
- **The app refuses a server outside its range.** `builtForRevision` and `minServerRevision` in `lib/api/capabilities.dart` are the
  contract with [Tippani](https://github.com/aaronified/tippani): raise `minServerRevision` when a screen starts to need something a
  later server revision added, and the app will say "update the server" instead of calling a route that is not there.
- **`dynamic_color` is pinned to 1.8.x.** From 2.x it builds on the separate `material_ui` package, whose `ColorScheme` is not the one
  in Flutter's own material library, so the two cannot be mixed in one app yet.

## Not built

Pairing, capture, the offline queue, updates, donation, bug reports and the signed release are the rest of the
[plan](PLAN.md)'s task list, in that order.
