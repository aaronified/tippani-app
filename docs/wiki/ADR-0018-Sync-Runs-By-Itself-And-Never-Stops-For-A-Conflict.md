# ADR-0018: Sync runs by itself and never stops for a conflict

- **Status:** Accepted and built. The owner, 7 November 2026: "Automatic sync: priority 1", and "put a separate menu for the sync conflicts. User can
  solve them later at their leisure; they need not solve everything as soon as they arise".

**Decided.** Once a server is paired, the app keeps the library in step without being asked (`lib/sync/auto_sync.dart`, `AutoSync`). A run
sends what is only on the phone (works first), then reads the server, brings down and sends changes, and applies deletes
([ADR-0017](ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md)). Search stays local; with the whole library on the phone it needs nothing more.

**When it runs: superseded by [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md), which has the timing now.** As first built: When the app opens; when it comes back to the front (unless it ran in the last 20 seconds); five seconds after the library is
changed (a burst of edits is one run); and about every three minutes while it is open. A switch in Settings > Sync with server turns the automatic
runs off; Sync now still works. What a sync itself writes does not start another run.

**When it fails.** A run that cannot finish (no network, a sleeping server, a server error) is tried again after 30 seconds, then 1, 2 and 5
minutes, never faster. A server that no longer accepts the phone is not retried until the phone is paired again. Nothing is half applied: a run
reads before it writes, and a stop leaves what is left for the next run.

**Conflicts do not stop it.** A quote or work changed on both sides is left exactly as it is and counted. The reader settles them from
**Settings > Sync conflicts** (or the badge on the Library's app bar), one at a time or, after a confirmation, all at once, whenever they like.
A conflict left alone is found again by every later run and stays on the list; the rest of the library keeps syncing around it. They are held in
memory, not stored: after the app restarts the first run finds them again, so there is nothing to get out of step.

**One at a time.** `PullSync.sync()` and `PushSync.push()` return the run in progress to a second caller instead of starting another, so a
tap on Sync now while an automatic run is going waits for it and shows its result.

**Not done.** It does not wait for the network coming back (that would need a connectivity package): the three-minute tick and the back-off find
it. There is no background run when the app is closed; Android limits that and the app does not ask for it.
