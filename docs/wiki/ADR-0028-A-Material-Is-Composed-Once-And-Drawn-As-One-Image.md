# ADR-0028: A material is composed once and drawn as one image

- **Status:** Accepted and built. The owner: "The app stutters a lot. This has started since we synced themes and materials, I think. If you cannot optimise them, we will need to shelve them." They were optimised to the budget below, so they are **not shelved**.

**Measured, because no phone was to hand.** The cost tests (`test/theme/material_cost_test.dart`) record what one paint of a surface puts on a canvas and count what rebuilds. Before the change, for one 360 by 200 surface:

| Material | draw ops per paint | shaders made per paint | layers | blend passes |
|---|---|---|---|---|
| a flat card | 1 | 0 | 0 | 0 |
| paper | 6 | 4 (two image shaders, two gradients) | 0 | overlay, screen, softLight |
| glass | 5 | 3 | 1 `saveLayer` | overlay, plus the pane's own layer |
| metal, marble | 7 | 5 | 0 | overlay, softLight, screen |

Every paint rebuilt all of that, two `ImageShader`s and the gradients included, and the same cards were rebuilt far more often than they changed:

- A list of cards: every `SurfaceCard` was rebuilt (7 of 7 built) by **any** preference write, including a sync that brought back exactly what the phone held (`PairedPreferences` announced every `_keep`). A surface read `PrefsScope`, which notifies every dependent on every change, and it read the whole `MediaQuery`, so a change in the phone's text size rebuilt every surface too. A quote's style read `PrefsScope` as well.
- The theme: `MaterialApp` was rebuilt on every preference and made two colour schemes and two `ThemeData` each time, to find them equal and throw them away.

Not found at fault: the tile cache (each tile is decoded once, `peek` costs a map lookup), and the per-card repaint boundary (a `ListView` already gives every child one).

**Decided.**

1. **Compose once, draw as one image.** `SurfaceImages` composes a surface (veil, both grain passes, light gradients, the pane's layer, the corner radius) into a `ui.Image` with `Picture.toImageSync` at the surface's exact size and the device's pixel ratio (1 to 3), and `MaterialPainter.paint` is one `drawImageRect` with a shared `Paint`. The key is everything the picture depends on: material, colour, accent, dials, light or dark, the tile, size, radius. Cards of the same size under the same material share one image. A set holds at most 48 MB, least recently used out first, disposed on the way out. Where the engine cannot make an image from a picture, the layers are drawn directly, as before. The look does not change: the same dials, the same order of layers.
2. **Narrow, by-value scopes.** `DerivedPrefsScopes` (once, in `app.dart`) reads the preferences and hands down a `MaterialLook` (`LookScope`) and a `ReadingPrefs` (`ReadingScope`, what `quoteStyle` and `quoteMeasure` use). Each tells its readers only when the value is not equal to the last. A screen shown without them reads the preferences itself, as before. A surface asks `MediaQuery` only for high contrast and the pixel ratio.
3. **An unchanged sync is not announced.** `PairedPreferences._keep` compares what it was given with what it holds and tells nobody when they are equal.
4. **The themes are built once.** `ThemeMemo` builds the light and dark `ThemeData` again only when the palette, the seed, the phone's own schemes or the look changed.

**The budget, held by the tests.** A material surface after its first paint: one draw operation (a flat card is one, and at most two more are allowed), no `saveLayer`, no shader made, nothing composed again. A screen of sixty cards composes at most two images. A preference that is not a look rebuilds no `SurfaceCard` and no `QuoteTile`; a look or a quote size still does, so the test is not vacuous. An equal sync announces nothing. Each of these was mutation-verified (removing the cache hit, always notifying, always rebuilding the theme, always notifying the reading scope, reading the whole `MediaQuery`, and no eviction each fail a test).

**What was not measured.** Frame times on a phone. The tests count operations and rebuilds, which is what they can see; whether the result is smooth enough is the owner's to say on their phone, and if it is not, the next step is the shelve switch this ADR did not need: one constant that paints every surface flat and hides the Materials entry, leaving the account's preferences untouched.

**Rejected.** Shelving the materials at once (the budget was reachable). One cached tile image per material, tiled with a shader (the two grain passes have different periods, so a composite tile seams). Caching at a bucketed size and cropping (the corners and the lights would sit wrongly). A `RepaintBoundary` per surface (a list already has one per child, and one more layer per card costs memory for nothing now that a repaint is one draw). Moving `PrefsScope` to an `InheritedModel` with an aspect for every key (every call site would have to name its keys; two small value scopes cover the readers that run once per card).

See also: [ADR-0024](ADR-0024-The-App-Wears-The-Accounts-Materials-Over-Material-You.md).
