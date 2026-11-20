# ADR-0032: Every screen that shows what the server holds draws the phone's copy first

- **Status:** Accepted and built. The owner, having asked for the Anthologies to behave like the rest of the app ([ADR-0030](ADR-0030-Anthologies-Draw-From-The-Phone-First-And-Ask-The-Server-Behind-It.md)), then decided: **cache-first everywhere**. One rule for every server-backed screen: draw the phone's copy at once, refresh behind it, show the shared offline note the same way everywhere. Refines [ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md).

**Why it was needed.** ADR-0022 kept the server's last answer, but only used it when the server *failed*: `ApiClient.getJson` asked first and fell back to the kept copy after a network error or the 15 second timeout. Every screen that reads a cacheable path therefore sat on a spinner for 15 seconds with a silent server, and most of them (Statistics, Tags, People, Checks, the bin, Devices, the metadata console) did not say the copy was the phone's at all: only Anthologies and the Server settings drew the note.

**Decided.** One mechanism, one rule.

| State | What shows |
|---|---|
| A copy is kept | The copy, immediately, with no spinner. |
| Nothing is kept | A spinner, then the screen's nothing-yet state (its own words, with Try again where the screen has one). |
| The server answers | Its answer replaces the copy in place (scroll and selection stay). The note, if it was up, goes. |
| The server cannot be reached | The copy stays; once the client gives up, the shared **Showing what this phone last saw** note appears at the top of the screen. |
| The server refuses (a 500, a 404 for something deleted on the web, a 403, a 429: every failure except a refused token, which unpairs the phone) | The copy stays and a different note says it is the phone's and that **the server did not accept the refresh**, with the server's own words when it gave some. It must not say the server cannot be reached: it answered. Only a screen with nothing shown says why in its own body. |
| The reader just changed something | The read that follows a write is **live**: it never answers from the phone. If that read cannot be answered either, the screen says so (its failure state, or for Tags the phone's own tags and the note) rather than leaving the list from before the change standing as if it were current. And the phone's copy of what the write touched is not drawn first by the next screen to open (see below). |

**How.**

- `CachedRead` (`lib/api/cached_read.dart`) is the helper every converted screen holds. `run` takes a turn number, so a slow earlier read never lands over a later one. On a first load it runs the screen's own loader once with `readFromPhone`, then runs it for real. A kept copy saved by an older version in a shape this one cannot read throws a `TypeError` (an `Error`, not an `Exception`), so that pass catches everything: it is passed over and the real read runs, instead of the screen staying on its spinner.
- `readFromPhone` is a *zone*: every `ApiClient.getJson` inside it answers from the kept copy or says there is none, and every other request is refused as if the network were down. A loader that reads three paths therefore needs no change at all, and draws the copy only if every read in it had one; the services, which differ a great deal, are untouched. `readLive` is the opposite zone (never from the phone, but the answer is kept); `readWithCopyShown` marks that a copy is on screen, so a refusal or a silent server sets the shared note instead of passing unseen.
- `OfflineNote` reads the phone's kept answers from an `OfflineScope` placed above the navigator, so a screen is not handed the controller to say what every screen says in the same place and words.
- **Writes keep the copy honest.** A successful change through `ApiClient` records, in `OfflineCache.noteWrite`, that the part of the server it touched (the first path segment, plus the parts whose answers it also changes: a quote changes the statistics and the tags) has a newer word than the phone's copy. `readForDraw` then declines such a copy for the first draw, so the Checks tab that re-opens itself after Fix all shows a spinner and then the truth, never the finding the reader just fixed. The copy is still there to fall back on when the server cannot be reached, because an old copy is better than none then. The record is per session, in memory.
- **The cache belongs to one server and one account.** `OfflineCache.clear` runs whenever the phone stops being paired (unpair, unpair every device, a refused token, the server forgotten), and forgets the write record with it. It also runs when the phone is pointed at a different server while still paired (`AppController.connect` with a different address), and when a pairing is made for a different account or server than the one the kept answers were written for (`OfflineCache.ownedBy`, recorded at each pairing; a phone with nothing recorded yet adopts its copy, because clearing would forget changes waiting in a queue). Tests unpair and pair again, and connect to a second server, and open a screen to see that none of the first one's copy shows.
- The queues are untouched: `OfflineAnthologies`, `OfflineWrites` and the capture queue send in the same order, with the same keys, and read the kept copy the same way ([ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md), [ADR-0025](ADR-0025-A-Passage-Shows-And-Says-Its-Own-Parts-In-Its-Anthology.md)). A flush inside a loader meets the network refusal of the kept-only zone as it would meet a server that cannot be reached.

**The screens.**

| Screen | Before | After |
|---|---|---|
| Anthologies: the list, an opened anthology, the chooser | Own mechanism (ADR-0030): copy first on a first load | Same, with the first draw going through `readForDraw` like the others (the raw copy only while changes wait on the phone, because they are written into it), plus a change with the server silent draws the kept copy at once; the note is on the opened anthology and the chooser too; a refusal says the copy is old |
| Statistics | Server first, spinner up to 15 s, no note | `CachedRead`; the note; pull to refresh |
| Tags | Server first (the phone's tags waited too) | `CachedRead`; the note; a read after rename, colour, merge or delete is live |
| People and Characters console | Three reads in turn, each up to 15 s | `CachedRead`; the note; live after a merge, a delete or a new character |
| Checks (stray marks, corrections, times and places) | Server first per tab | `CachedRead` in the shared tab loader; the note; live after accept, ignore or fix |
| Administration lists (users, library folders) | Server first | `CachedRead` in the shared admin loader; the note; live after a change |
| Backup and restore, metadata sources and keys | Server first | `CachedRead`; the note; live after a backup, a restore or a key change |
| The bin | Server first | `CachedRead`; the note; live after restore or delete |
| Paired devices | Server first | `CachedRead`; the note; live after unpairing one |
| Metadata console (gaps and duplicates) | Two reads in turn | `CachedRead`; the note; live after a check is applied or two works are merged |

**Not converted, and why.**

- **Reads that are not a display of the server's state.** Sync's own reads (`pull_sync`, `push_sync`, `board_sync`) must treat "the server answered" as fact; they never use the kept copy and never will. Search results and the quote lookups are a question put to the server with each keystroke. `/auth/me` is how the app learns it was unpaired.
- **Jobs and import progress** poll a thing that is changing; an old answer drawn first is wrong, not merely old.
- **Forms that fill their fields from the server** (the Account page, notification and widget-key settings, the context rules, a person's or character's own page, a work's details form) are edited in place: drawing a copy and then replacing it under a reader who has started typing is a different problem, and they already show the last answer through `getJsonKept` when the server cannot be reached.
- **The quiz** starts a session from a deck; a session that begins on a copy and is then replaced is not one session. The deck has its own queue (ADR-0022).
- **Source files** and **staged imports** mix reads with a running scan or paging; they are asked live.
- **Boards and the Library** read the phone's own database and were never server-first.

**Rejected.** A shorter timeout for every read (still a wait, and a wrong answer to "the server is slow"); each screen keeping its own copy of the rule (the Anthologies in ADR-0030 were exactly that, and drifted); a cache that every write clears whole (it would make the screen after any save a spinner); a `kept` method on every service (a dozen services and every fake would have to implement it, where one zone reaches all of them); keying every entry by server address and account (one owner is recorded and the cache cleared when it changes, which is the same thing with one comparison instead of a longer key on every read).
