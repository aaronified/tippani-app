# ADR-0022: Everything reads offline, and a change made offline waits for the server

- **Status:** Accepted and built (0.8.2); refines [ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md) and the Server and Settings split in
  [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md). The owner, 13 November 2026: "Everything should be available offline on the app (including
  contexts). Syncs with the server when connected. And server tab should be all about the server management and will have settings that also will sync
  with the server."

**Decided.**

- **A screen that only reads keeps the server's last answer.** `ApiClient.getJson` keeps the answer to a GET for the paths `OfflineCache` allows and,
  when the server cannot be reached (no network, or timed out), returns the kept one. Anything else, a refusal included, is the server's word and is
  thrown. The allowed paths are the display screens: anthologies, a quote's context, statistics, tags, stickers, the bin, people and characters, Checks,
  the metadata console, source files, the staged imports, devices, administration's lists, the context rules and the quiz's deck. **Not** the routes sync
  reads (a stale answer there would look like a server that had lost everything) and not `/auth/me`, whose failure is how the app learns it was
  unpaired; the Account page reads its own three answers through `getJsonKept` instead. A read of what was just saved is live (`getJsonLive`), so an old
  copy is never served in place of a timeout. A screen that shows a kept answer says so, with its date (`OfflineNote`).
  What a shelf and a work page draw is kept too (`keepWorkExtras`, after a sync): cover pictures, and each work's details and cast, at most 60
  requests a run, details read again after two weeks, and a run stops after three misses in a row.
- **A change made while the server cannot be reached is kept and sent in order.** Anthologies (`OfflineAnthologies`) apply the change to the kept copy at
  once and queue it, headings, commentary, grouping, front matter and description, the cover and poster pictures (each up to 1.5 MB; the phone keeps the file and shows it at once, and a second pick replaces the upload that waits) and the fill included; the queue is sent by every
  sync run that finds the server answering, and when the list is opened. The queue is read again around every send, so a change made while a request is
  out is never written over. An anthology made offline has a negative id until it is sent; what was queued against it follows it to its real id, and a
  screen that still holds the temporary id keeps working. A change the server refuses is dropped and shown. Preferences keep the settings changed offline
  apart, each with the value the phone held when it was made: it is sent only while the server still holds that value, so a setting changed on the web
  meanwhile wins, and the read-back never overwrites what is still waiting.
- **The context of every synced quote is kept on the phone**, one file each (`FileContextStore`): after each sync run the phone asks which quotes of each
  work have one (`/sources/context-ids`) and fetches those it does not hold, 150 a run. A quote the server lists but cannot find is noted as having none
  for a week. With no server the widest window kept answers whatever was asked.
- **The Server tab is everything the server holds.** Besides the connection, sync, devices, statistics, the bin, metadata, Checks, source files and
  administration, it carries **Your settings on the server**: the account, language, text and quotes, colours, sections (with how long the bin keeps
  things), the daily review and the context around a quote, whether or not the phone is paired. Settings keeps the app's own: the app's colours, tags
  (the library's vocabulary), reading aloud, updates, backup, the log and the licences. The admin section shows when the phone starts with no server (the
  last answer is remembered).
- **Unpairing, forgetting the server or a refused token discards the copy and everything that waited** (`OfflineCache.clear` and what registers with it), so
  a queued change is never sent to another account or another server.

**What stays online, and says so.** A count of what an anthology's fill would find, and an EPUB (Markdown is made from the phone's copy); the bin's restore
and every other write the server must judge; search through the server; the server's own log and the live job list. Source files stay on the server: only
their list and each quote's context are kept on the phone.

**Rejected.**

- *A local anthology table with its own two-way sync.* A kept copy and an ordered queue give the reader the same thing and avoid a second source of
  truth beside the fingerprint-based merge.
- *Keeping every GET.* Sync reads would be answered from the past.
- *SQLite for the cache.* Widget tests cannot drive real SQLite I/O, and the cache is small text keyed by path; the contexts, which are many, are files.

**Consequences.** The cache is bounded (3 MB, 400 entries, the oldest written first, anthologies pinned to two thirds, an answer larger than the cache not
kept). Moving a heading offline moves only the heading; the server settles the passages under it when the move is sent. A crash between sending a queued
change and saving the queue can send a new anthology or heading twice, because the server has no idempotency key.
