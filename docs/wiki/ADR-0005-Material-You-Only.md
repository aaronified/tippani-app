# ADR-0005: The look is Material You only

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** Material 3 with Android's dynamic colour (`dynamic_color`), Tippani's red as the seed where the phone gives none, and the system's
light and dark setting. The web app's themes, material sets and textures are not carried over, and are not a later phase.

**Consequences.** A synced account's theme preferences are ignored here. `dynamic_color` is pinned to 1.8.x: from 2.x it builds on the separate
`material_ui` package, whose `ColorScheme` is not the one in Flutter's own material library, so the two cannot be mixed yet.
