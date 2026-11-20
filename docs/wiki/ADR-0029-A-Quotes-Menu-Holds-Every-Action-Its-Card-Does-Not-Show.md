# ADR-0029: A quote's menu holds every action its card does not show, and one function builds it

- **Status:** Accepted and built. The owner: "The context menus are missing most of the actions (all quote level actions that are not showing on the card, must be in the context menu)."

**Decided.** A quote drawn as a card has four buttons of its own (Favourite, Copy, Read aloud, Share) and a "More for this quote" menu. The menu holds every other action a quote supports anywhere in the app, so a reader never has to open the quote to edit, colour, tag, file or delete it. One class, `QuoteMenu` (`lib/screens/quote_menu.dart`), builds the items and does what each one does; every screen that draws a card builds one `QuoteMenu` and hands it to the card, and the card's own buttons call the same `QuoteMenu.run`, so a button and its menu item cannot differ ("two things that look the same behave the same"). Colour, Add a tag, Take a tag off and Move to a board are the bulk bar's own functions called with a selection of one, and Delete is the quote page's own deletion (with Undo), moved to one function that both call.

| Action | On the card? | In the menu now |
|---|---|---|
| Open the quote | the card is the press target | yes (was) |
| Select (start selecting) | long press | yes (was), only where the screen can select (library, work) |
| Favourite | star button | not where the star is; yes on a search result |
| Copy | button | not where the button is; yes on a search result |
| Read aloud / Stop | button | not where the button is; yes on a search result |
| Share | button | not where the button is; yes on a search result |
| Edit | no | **added** |
| Colour | no (a stripe) | **added** |
| Add a tag | no (tags are drawn, not pressed) | **added** |
| Take a tag off | no | **added**, only when the quote has a tag |
| Move to a board | no | **added**, only for a quote of no work (a quote of a book or film is filed by its work, the same rule as the bulk move) |
| Add to anthology | no | yes (was), only with a server that has anthologies and a quote that is on it |
| Open the work | no | **added**, only where the card's header names a work (not on that work's own page) |
| Show where it comes from (context) | no | **added**, only with a server to ask and a quote that is on it |
| Delete | no | **added**, last, below a divider; asks first and offers Undo |

**The same menu everywhere the card is drawn:** the library, a work's page, a board, a filtered list (a tag or a name) and Home. A search result is a different widget that draws no buttons, so it gets a "More for this quote" button of its own, for a hit that is on the phone, and its menu holds all of the above including the four the card has as buttons (the menu is given the set of buttons its card draws, `quoteCardButtons`, and leaves those out; a row with none leaves out nothing). A hit that is on the server only has nothing to act on and no menu.

**Left as it is.** A long press still selects where a screen can select, and adds to an anthology where it cannot. "Set one field" and "Take a tag off many" are bulk-only: Edit is the one-quote form for the fields. The picture options live on the share screen (ADR-0031), reached by Share, so "Save picture" is not a menu item of its own.

**Rejected.** A second menu builder per screen (that is how the library's menu and the board's already differed); icons in the menu (the bulk bar's menu is text, and two menus that look alike must be alike); a long-press menu in place of selection (selection is what the library and a work are for, and a long press was already taken).
