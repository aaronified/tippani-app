# ADR-0031: Every share is one screen, with a subject

- **Status:** Accepted and built. The owner: "Share acts differently in different places. The share should be one unified screen (the one in the app right now)", and on the scope: every share in the app opens that one screen, anthologies included.

**Decided.** `ShareScreen` is the only way anything leaves the app through Android's share sheet. It takes a `ShareSubject`: **one quote** (`QuoteShare`), **several quotes** (`QuotesShare`: a selection, a whole work, the whole library), or **an anthology** (`AnthologyShare`). The screen is the same for all three: a Share title, a Format row, the parts to include where there are parts, the text that will be sent (editable), and Share, Copy and Save. The subject decides what is offered:

| Subject | Formats | Parts to switch | Notes |
|---|---|---|---|
| One quote | Picture, Plain text, Markdown, WhatsApp, Reddit | the quote's own parts | as before; the picture has Share, Copy picture, Save picture |
| Several quotes | Plain text, Markdown, WhatsApp, Reddit | the parts any of them has, one set for all | no picture: a picture of two hundred quotes is nothing anyone sends. Markdown is Tippani's own import file (ADR-0014) and keeps everything, so its parts row is replaced by a line saying so. A whole work is headed by its name and maker, once, and leaves them out of each credit line |
| An anthology | Plain text, Markdown, EPUB book | none | the plain text is made here; the Markdown and EPUB are the server's files, fetched when chosen (the only network use, as before). EPUB is a file: Share and Save, no Copy. A server that cannot make it says so and the plain text still works |

Text formats of every subject have **Share** (the words in the box, as edited), **Copy** and **Save** (a file: `.md` for Markdown and Reddit, `.txt` for the rest). Save was only on Markdown exports before; it is on every text format now, which is what "the same buttons" asks for.

**One sender.** Screens used to carry `share:`, `shareImage:` and `shareFile:` functions down through every constructor so a test could fake the sheet. They are gone. `Sharer` (`text`, `image`, `file`) is the one thing that calls `SharePlus`, and a test puts a `FakeSharer` in a `ShareScope` above the screen. The logs (`harness/log_screen.dart`, `server_log_screen.dart`) are not a quote, work or anthology and keep their own call.

| Where Share is pressed | Before | Now |
|---|---|---|
| A quote's card (Share button) | plain text straight to the sheet | the screen, one quote |
| A quote's menu (a search result has no button) | no menu item | the screen, one quote |
| The quote page | the screen | the screen, one quote |
| Selecting quotes, Share in the bar's More menu | not there | the screen: one quote if one is selected (so it has the picture), else several |
| Library bar, Share | menu: Share as Markdown / Save as Markdown file | the screen, every quote; Markdown is the same file as before |
| A work's menu, Share | the same two items | the screen, that work's quotes in reading order |
| A work's reading page, Share all | plain text to the sheet | the screen, that work with the page's translations and notes switches carried over |
| An anthology's Share button | plain text to the sheet | the screen, the anthology |
| An anthology's menu, Export | a sheet asking Save or Send, as Markdown or EPUB | gone: it is the same screen's Markdown and EPUB formats with Share and Save |
| Search, the context screen | search had none; context has none | search's result menu has it; the context viewer has no share, as before |

**Decisions the owner may want to reverse.** (1) An anthology's Markdown is shared as **text**, not as a `.md` file attachment as its Export did; Save writes the file. (2) A selection's Share is in the bar's **More** menu, not a button of its own: four icons already take the bar and a fifth leaves the "N selected" title a few letters. (3) A whole work shares as the same per-quote text as any set, headed by its name, and no longer in the reading page's chapter-grouped layout (`workShareText` is still the function behind that layout and is no longer called by a screen). (4) Anthologies get no WhatsApp or Reddit format; they were never shared that way.

**Rejected.** A separate screen for sets and for anthologies (that is how the three had drifted); keeping the export menu beside the screen (two ways to the same file); a picture of a set.
