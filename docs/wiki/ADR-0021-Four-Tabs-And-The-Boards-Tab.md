# ADR-0021: Four tabs, and the Boards tab

- **Status:** Accepted and built; changes the navigation of [ADR-0007](ADR-0007-The-Harness-Is-The-Base-Every-Screen-Stands-On.md). The owner,
  9 November 2026.

**Decided.** The bottom bar is Home, Boards, Server and Settings.

- **Boards** is the name for the four pages of the reader's collection: Library, Catalogue, Quotes and Anthologies. The header names the board, with an
  arrow each way and a dot for each. A sideways swipe or drag moves between them, with the pager and the spring taken from Fluenough's tabs (stiffness 400,
  damping 0.75 on a fast release). The swipe works on Boards only. The sections the reader hid in Settings stay hidden.
- **Server** holds everything about the server: the connection and pairing, sync and conflicts, devices, imports and checks, people, details and
  duplicates, source files, and for an admin the administration and the server's log.
- **Settings** holds the app's own: colours, language and text size, sections, tags, reading aloud, updates, what's new, backup, the app's log and the
  licences.
- **One search bar**, on Home and on each board: a pill that suggests tokens (`tag:`, `by:`, `in:`) and then their values as you type. On a board it filters that
  board; a button widens the same words to the server's results. On Home, pressing Search opens the full search.
- **Home has an Add button** that offers every kind of quote the app and the server keep: a line from a book, a line from a film, show or game, a
  standalone quote, a scanned page, spoken words, and a file import.

**Consequences.** The Library, Catalogue and Quotes tabs no longer exist as tabs. Each page is the same screen as before, drawn without its own bar inside the
Boards tab. The Markdown export moved into the search box's end buttons, and the sync badge into the Boards header.
