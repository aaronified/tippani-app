# ADR-0001: Android only; no unbuildable ios/ directory ships

- **Status:** Accepted. Carried over from Tippani's ADR-0014 when the app got its own repository; the decision is unchanged, and the app is at this
  repository's root, not in a `mobile/` directory.

**Decided.** The app is Flutter, Android only. There is no `ios/` directory in the tree.

**Why.** Flutter compiles for iOS and the Dart here stays platform-neutral, but building and signing for iOS needs a Mac and the owner does not have
one. An `ios/` directory nobody can build is a directory that rots, and it advertises a platform nobody can ship.

**Consequences.** A fork with a Mac adds iOS with `flutter create --platforms=ios .`; nothing here stops it. The licence ([ADR-0002](ADR-0002-Licence-Is-GPL-3.0-And-Nothing-Proprietary.md))
is chosen for Android and Google Play, not for Apple's App Store.
