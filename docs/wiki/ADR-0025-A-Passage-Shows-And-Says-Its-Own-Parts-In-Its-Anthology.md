# ADR-0025: A passage shows and says its own parts in its anthology

- **Status:** Accepted and built; follows the server's ADR-0934 and widens [ADR-0023](ADR-0023-Which-Server-Settings-The-Phone-Offers.md).
  The owner, 15 November 2026: "there is no option to show the notes/translations of the quote. Everything that a quote has (even context) must be available to show in the anthology on a global basis with per quote override. And these shall be editable within the anthology."

**Decided.** What it shows lists every switch the server keeps except the three picture switches, in four groups: what the document prints about a passage, what the quote
carries (its note, translation, language, tags, context), what its book or film knows, and who is answerable for it. A passage's menu has
What it shows and says: for each switch, As the anthology / Show / Hide, and text boxes for the quote, its note, its translation and the context
before and after it. A text box that differs from the quote's own is a restatement for this anthology only; the button beside it puts the
quote's own words back, which sends "forget the restatement" and not the quote's words again, so a later change to the quote shows through.

**Older servers.** The server names the feature `anthology-entry-display` (API revision 12); without it the quote's own-part switches and the passage's
menu item are not offered, so no control saves and comes back off. Until the server has been asked (a phone that has not reached it yet) they are offered, as the poster's are; a change made then to a server that turns out to be older is refused when it goes up.

**Offline.** The change is applied to the cached anthology at once and waits in the queue like every other (`display`), in order with the rest.

**How a switch is sent.** The six with a column of their own stay at the top of the request; the rest go inside `fields`, which is also
where the web keeps them. The note is the one that shows until it is switched off.

**Also in this change (looks, from the owner's report of misaligned buttons and text boxes without wells).** Edit and Delete moved into the
anthology's menu so the title is not cut to eight letters; a passage has one menu, with Remove in it, instead of a loose cross beside it; and an input's fill is the container above a dialog's own, with a hairline, so a field reads as a well in light and in dark.

**Not carried over.** The portrait, character and signature pictures have a switch on the server and none here (the app draws no
pictures in an anthology); transliteration (dropped on the server in 0072).
