# ADR-0023: Which server settings the phone offers

- **Status:** Accepted and built (0.9.0); refines [ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md), which put the server's settings on the
  Server tab. The owner asked for all the filed work to be done; the issue (#89) said a decision was needed first, and this is it.

**Decided.** The Server tab offers a server setting when the phone has something that setting drives, or the server's own behaviour changes with it. It does
not draw a setting the phone would ignore. The server's preferences are kept whole on the phone (`ServerPrefs.raw`) and sent back whole-keyed, so a setting the
phone does not draw is never lost when one is saved.

| Setting | On the phone | Why |
|---|---|---|
| Language, text size, quote shape, colours, sections, bin keep time, daily review size and scope, context rules | Offered (0.8.2) | the phone applies them or the server's answers change |
| **Which questions each review deck asks** (`srQuestions`) | Offered (0.9.0), on Daily review | the server builds the deck from it, so it changes the phone's quiz; the phone keeps the server's three rules (flip never daily, no unknown kind, a deck keeps one kind that suits every card) so a bad combination is never sent |
| Theme, accent, contrast, material sets, grounds, tile looks, fonts and their styles, mono and hand sizes | Web only | they describe how the web draws; the phone keeps its own look (Settings, App colours) |
| Interface fallback, read languages, text order, language marks, voices per language | Web only | each drives a display the phone does not have; offering a switch that changes nothing is worse than none |
| Dock order (`sectionOrder`) | Web only | the phone's tabs are not the web's dock |
| The numbers behind the schedule (`srTuning`) | Web only | a bad value gives a quietly useless schedule, not an error; the web labels it as the in-depth control and the phone has no room to explain it |

**Why.** A setting on a screen is a promise that pressing it does something. Thirty-six of the web's fifty-four preference keys would be switches that change
nothing on a phone. The two groups that do matter on a phone, the review's questions and Jobs, are now there.

**Reset all data is not on the phone either** (issue 93): it deletes every account's library, needs a downloaded safety copy the phone cannot check the owner kept,
and the web has it behind the same two steps. Unpair every device is on the Paired devices screen.

**Revisit when** the phone gains something a web-only setting would drive (a text-order setting needs a card that can show the original beside a translation).

See also: [ADR index](ADR-Index.md) · [Plan](Plan.md)
