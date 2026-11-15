# ADR-0024: The app wears the account's materials over Material You

- **Status:** Accepted and built; supersedes the textures half of [ADR-0005](ADR-0005-Material-You-Only.md) and of [ADR-0020](ADR-0020-The-Colours-Are-Chosen-In-Settings.md).
  The owner, 14 November 2026: "In the app, add the server textures and the texture mixer." and, when asked whether the look should follow the web's:
  sync with the web.

**Decided.** The app draws the server's materials. The account's `materialSet`, `tileGround`, `tileShell`, `tileCard`, `tileCover` and `texTweak`
preferences are read and written through the same preference calls as every other setting, so the web and the phone wear one look. Settings,
Materials has the set picker, a material for each of the four surfaces (background, bars, cards, covers) and the four light dials for every material
in use (hardness, glow through, colour spread, reflects the room).

**How a surface is drawn.** Material You still chooses the colour; a material lays its grain over that colour the way the web does
(`(1 - s) * colour + s * overlay(fine, coarse)`, then the dials as gradients). The 27 tiles, sizes, strengths and factory dials are the web's own
numbers. The background is painted under every page by the page transition, so each page brings its own opaque ground; bars, cards and a work with no
cover picture sit on their own surface. A card's texture is under its `Card`, whose material is clear, so ink from a tap shows over the grain.

**Consequences.**
- A phone that has not yet heard from the server has no material (the look the app had before), and so does a reader whose phone asks for high
  contrast. An account with none stored wears Manuscript, as on the web.
- The stored `texTweak` object is kept whole when a dial is saved: it also carries the web's glass dials, which this screen does not draw.
- Not carried over: true glass (the refracting lens and its five dials), the backdrop blur of a glass surface, and saved looks. A glass material is drawn
  as a translucent pane with its sweep and no blur.
- Rejected: wrapping every `Scaffold` in a texture (a transparent scaffold ghosts the page beneath during a transition), and painting only bars.
