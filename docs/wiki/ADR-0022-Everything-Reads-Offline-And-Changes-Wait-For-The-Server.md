# ADR-0022: Everything reads offline, and a change made offline waits for the server

- **Status:** Accepted and built; refines [ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md) and the Server and Settings split in
  [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md). The owner, 13 November 2026: "Everything should be available offline on the app (including
  contexts). Syncs with the server when connected. And server tab should be all about the server management and will have settings that also will sync
  with the server."

**Decided.**

- **A screen that only reads keeps the server's last answer.** `ApiClient.getJson` keeps the answer to a GET for the paths `OfflineCache` allows and,
  when the server cannot be reached (no network, or timed out), returns the kept one. Anything else, a refusal included, is the server's word and is
  thrown. The allowed paths are the display screens: anthologies, a quote's context, statistics, tags, stickers, the bin, people and characters, Checks,
  the metadata console, source files, administration's lists, the context rules and the quiz's deck. **Not** the routes sync reads (a stale answer there
  would look like a server that had lost everything) and not `/auth/me`, whose failure is how the app learns it was unpaired; the Account page reads
  its own three answers through `getJsonKept` instead.
- **A change made while the server cannot be reached is kept and sent in order.** Anthologies (`OfflineAnthologies`) apply the change to the kept copy at
  once and queue it; the queue is sent by every sync run that finds the server answering, and when the list is opened. An anthology made offline has a
  negative id until it is sent, and what was queued against it follows it to its real id. A change the server refuses is dropped and shown, so it never
  blocks the ones behind it. Preferences keep the settings changed offline apart and send them before the server's copy is read back, because reading it
  back first put the old values over the change.
- **The Server tab is everything the server holds.** Besides the connection, sync, devices, statistics, the bin, metadata, Checks, source files and
  administration, it now carries **Your settings on the server**: the account, colours, the daily review and the context around a quote. Settings keeps the
  app's own: language, text and quotes, sections, tags, reading aloud, updates, backup, the log and the licences. The admin section still shows when the
  phone starts with no server (the last answer is remembered).

**What stays online, and says so.** An anthology's cover picture, fill and export while it has not been sent; the bin's restore and every other write the
server must judge; search through the server; the server's own log and the live job list. Source files stay on the server: only a quote's context, and
the contexts of favourite quotes after each sync, are kept on the phone.

**Rejected.**

- *A local anthology table with its own two-way sync.* A kept copy and an ordered queue give the reader the same thing and avoid a second source of
  truth beside the fingerprint-based merge.
- *Keeping every GET.* Sync reads would be answered from the past.
- *SQLite for the cache.* Widget tests cannot drive real SQLite I/O, and the cache is small text keyed by path.

**Consequences.** The cache is bounded (3 MB, 400 entries, least recently used first, anthologies pinned) and is cleared when the phone is unpaired or the
server forgotten. A kept answer carries the date it was saved. Moving a heading offline moves only the heading; the server settles the passages under it
when the move is sent.
