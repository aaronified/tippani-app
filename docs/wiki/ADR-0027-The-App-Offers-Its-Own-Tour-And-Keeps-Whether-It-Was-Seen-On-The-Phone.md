# ADR-0027: The app offers its own tour, and keeps whether it was seen on the phone

- **Status:** Accepted and built. The web has a first-run tour and per-screen tours; the owner asked for tours in the app, refined for the app.

**Decided.** The first time the app opens with a library it offers a short tour, once. A dimmed screen has a hole over one real control, and a card says one sentence about it with **Skip**, **Back**, **Next** (**Done** on the last stop) and "n of N". Settings has **Take the tour** to play it again.

| Stop | Points at | Left out when |
|---|---|---|
| Welcome | nothing (the middle of the screen) | never |
| Add anything | the Add button on Home | the phone has no Home tab (no quiz on the server) |
| Home | the Home tab | same |
| Your shelves | the Boards tab | every shelf is hidden and none can show |
| Anthologies | the Boards tab | the Anthologies shelf is not offered |
| Your server | the Server tab | never |
| Keeping in step | the Server tab | the phone is not paired |
| Settings | the Settings tab | never |

The card is a sentence about a control, not a feature list: the web's tour shows every feature on a desktop with a "more" fold, and a phone has the width for neither. Search is named in the Boards sentence instead of a stop of its own, because its button is drawn by each shelf, not by the shell, and a stop that points at a tab while talking about a button elsewhere points at nothing.

**Kept on the phone, in its own keys.** `tour_outcome` (`finished` or `dismissed`) and `tour_version` in the phone's preferences. There is no server field, and the web's tour state is deliberately not shared: it records that someone has seen the web's screens, and a reader who finished that has not seen a bottom bar. Sharing would silently skip the tour for exactly the people who have never held the app. The version lets a later, longer tour be offered once more to those who finished this one. Neither key is in a backup.

**A stop is shown only for a control that is there.** Each stop holds a `GlobalKey` hung on the real widget (the shell does this). A key that finds no built widget, or one on a tab that is not the open one after the stop has opened its own tab, skips the stop, and "n of N" counts only the stops that will be shown. A hidden section, a missing server feature or an admin-only tab therefore never gets a stop pointing at nothing.

**Built for a phone.** The card sits on the side of the target that is nearer the thumb (above the bottom bar, below a control at the top), scrolls inside itself when text is large, and wraps its buttons. Moving the hole is animated only where animations are on; with them off the content is all there at once. The card's text is a live region, so a screen reader says it when the stop changes, and the app under the dimmed screen is hidden from it. The dimmed screen takes presses, so a tap on the highlighted control does not do what it does outside the tour.

**Offered of itself only on a new install; never restarts.** The harness records whether any version had ever been written to the phone when the app opened (before the what's-new pass writes one), and only then offers the tour, once the library is up and nothing is stored about it. Someone upgrading has the app already and a What's new dialog to read, so for them the tour is Settings > Take the tour and nothing more; this also keeps it from ever appearing over that dialog. Nothing starts it again after Skip, Done or the system Back, which counts as Skip. The ring is measured again when the screen changes shape or the text size changes, a stop whose control has gone is passed over, and when the tour ends the reader is back on the tab they started on.

**Rejected.** A tour package (a hand-built overlay is under 300 lines and follows the app's theme, text size and tab list, which a package's step list would have to be told about); a per-screen "?" (each screen would need keys the screens do not have, and Take the tour already replays the walk; it can be added later screen by screen); storing the outcome on the account (see above).
