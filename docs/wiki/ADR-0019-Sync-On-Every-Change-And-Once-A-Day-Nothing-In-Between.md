# ADR-0019: Sync on every change and once a day, with nothing in between

- **Status:** Accepted and built; replaces the timing part of [ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md). The owner,
  8 November 2026: "phone and server always stay in sync (no need for so many timed syncs, rather have one daily sync (if the app is on) or on connection
  (max once per day), and for the rest just sync on every change in the database)".

**Decided.** The app asks the server for as little as will keep the two in step.

- **On every change** to the library (an add, an edit, a delete, a favourite), a run starts four seconds later. Four seconds, not none, so that a burst of
  edits (typing into a form saves once; a bulk change is many) is one run.
- **Once a day:** a run is made when the app opens, when it comes back to the front, when the phone gets a network again, or (if the app is simply left on)
  when a day has passed since a run last finished. Each of those makes a run only if a day has passed since the last finished one, or a change is waiting.
- **A change that could not be sent** (no network, a sleeping server) is remembered (`auto_sync_dirty`, kept across restarts) and goes at the next of
  those: the next change, the app opening or coming back, or the network returning. **There is no retry timer and no back-off ladder.** The one timer
  left looks at the clock every half hour, makes no request, and starts a run only a day after one that finished.
- A server that refuses the phone is left alone until the phone is paired again.

**Why.** The first version ran every three minutes and backed off 30 seconds to five minutes. That is a lot of traffic to a home server and a lot of battery
for a library that changes a few times a day, and it was a guess at when the network was back. Connectivity is now known (`connectivity_plus`) and the
phone's own changes are known (the store's change stream), so nothing needs guessing.

**What the server's own changes do.** A change made on the web reaches the phone at the next run: the daily one, or the next time the phone changes
something (a run both sends and reads). The phone does not poll for it.

**State kept:** `auto_sync_last` (when a run last finished), `auto_sync_dirty`, `auto_sync` (the reader's switch).
